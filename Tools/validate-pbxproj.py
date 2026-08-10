#!/usr/bin/env python3
"""Strict parser for the old-style (NeXTSTEP) plist that pbxproj uses.

Written because structural checks on braces and UUIDs passed while Xcode still
rejected the file outright — a `name = ;` empty value is well-balanced and
completely invalid. This actually parses the grammar, so that class of bug
fails here instead of on a CI runner.
"""
import os
import plistlib
import re
import sys
import xml.etree.ElementTree as ET

UNQUOTED = re.compile(r'[A-Za-z0-9_$./:-]+')


class ParseError(Exception):
    pass


class Parser:
    def __init__(self, text):
        self.s = text
        self.i = 0

    def line_of(self, pos):
        return self.s.count('\n', 0, pos) + 1

    def error(self, msg):
        line = self.line_of(self.i)
        near = self.s[max(0, self.i - 60):self.i + 60].replace('\n', '\\n')
        raise ParseError(f"line {line}: {msg}\n    near: ...{near}...")

    def skip(self):
        """Whitespace and both comment styles."""
        while self.i < len(self.s):
            c = self.s[self.i]
            if c in ' \t\n\r':
                self.i += 1
            elif self.s.startswith('/*', self.i):
                end = self.s.find('*/', self.i + 2)
                if end < 0:
                    self.error("unterminated /* comment")
                self.i = end + 2
            elif self.s.startswith('//', self.i):
                nl = self.s.find('\n', self.i)
                self.i = len(self.s) if nl < 0 else nl + 1
            else:
                return

    def value(self):
        self.skip()
        if self.i >= len(self.s):
            self.error("unexpected end of file")
        c = self.s[self.i]
        if c == '{':
            return self.dict()
        if c == '(':
            return self.array()
        if c == '"':
            return self.quoted()
        if c == '<':
            return self.data()
        m = UNQUOTED.match(self.s, self.i)
        if not m:
            self.error(f"expected a value, found {c!r} "
                       f"(an empty value like `key = ;` is invalid)")
        self.i = m.end()
        return m.group(0)

    def quoted(self):
        self.i += 1
        out = []
        while self.i < len(self.s):
            c = self.s[self.i]
            if c == '\\':
                out.append(self.s[self.i:self.i + 2])
                self.i += 2
            elif c == '"':
                self.i += 1
                return ''.join(out)
            else:
                out.append(c)
                self.i += 1
        self.error("unterminated quoted string")

    def data(self):
        end = self.s.find('>', self.i)
        if end < 0:
            self.error("unterminated <data>")
        self.i = end + 1
        return "<data>"

    def dict(self):
        self.i += 1  # {
        out = {}
        while True:
            self.skip()
            if self.i >= len(self.s):
                self.error("unterminated dictionary")
            if self.s[self.i] == '}':
                self.i += 1
                return out
            key = self.value()
            self.skip()
            if self.i >= len(self.s) or self.s[self.i] != '=':
                self.error(f"expected '=' after key {key!r}")
            self.i += 1
            val = self.value()
            self.skip()
            if self.i >= len(self.s) or self.s[self.i] != ';':
                self.error(f"expected ';' after value for key {key!r}")
            self.i += 1
            out[key] = val

    def array(self):
        self.i += 1  # (
        out = []
        while True:
            self.skip()
            if self.i >= len(self.s):
                self.error("unterminated array")
            if self.s[self.i] == ')':
                self.i += 1
                return out
            out.append(self.value())
            self.skip()
            if self.i < len(self.s) and self.s[self.i] == ',':
                self.i += 1

    def parse(self):
        self.skip()
        root = self.value()
        self.skip()
        if self.i != len(self.s):
            self.error("trailing content after root object")
        return root


def main(path):
    text = open(path).read()
    # The // !$*UTF8*$! header is a pbxproj marker, not plist content.
    if text.startswith('//'):
        text = text[text.index('\n') + 1:]

    try:
        root = Parser(text).parse()
    except ParseError as e:
        print(f"PARSE ERROR in {path}\n{e}")
        return 1

    if not isinstance(root, dict):
        print("root is not a dictionary")
        return 1

    objects = root.get('objects')
    if not isinstance(objects, dict):
        print("missing or malformed `objects` dictionary")
        return 1

    rootObject = root.get('rootObject')
    if rootObject not in objects:
        print(f"rootObject {rootObject} is not present in objects")
        return 1

    # Every value that looks like an object ID must resolve.
    dangling = []
    def walk(v):
        if isinstance(v, dict):
            for x in v.values():
                walk(x)
        elif isinstance(v, list):
            for x in v:
                walk(x)
        elif isinstance(v, str) and re.fullmatch(r'[0-9A-F]{24}', v):
            if v not in objects:
                dangling.append(v)
    walk(objects)

    if dangling:
        print(f"dangling object references: {sorted(set(dangling))}")
        return 1

    # The scheme references the app target by ID, so a regenerated project
    # silently invalidates a stale scheme — and xcodebuild reports that as
    # "Scheme Zoon is not currently configured for the build action", which
    # points nowhere near the actual cause. An empty scheme file produces the
    # same message, and is easy to create by accident.
    scheme_dir = os.path.join(os.path.dirname(path), 'xcshareddata', 'xcschemes')
    if os.path.isdir(scheme_dir):
        for name in sorted(os.listdir(scheme_dir)):
            if not name.endswith('.xcscheme'):
                continue
            scheme_path = os.path.join(scheme_dir, name)
            if os.path.getsize(scheme_path) == 0:
                print(f"scheme {name} is empty")
                return 1
            try:
                tree = ET.parse(scheme_path)
            except ET.ParseError as exc:
                print(f"scheme {name} is not valid XML: {exc}")
                return 1
            blueprints = {
                ref.get('BlueprintIdentifier')
                for ref in tree.iter('BuildableReference')
            }
            if not blueprints:
                print(f"scheme {name} references no buildable")
                return 1
            unresolved = {b for b in blueprints if b not in objects}
            if unresolved:
                print(f"scheme {name} references unknown targets: {sorted(unresolved)}")
                return 1

    # Any Info.plist the project points at with INFOPLIST_FILE.
    #
    # This exists because an app extension whose Info.plist is missing a key is
    # not a build error — it builds clean and then iOS refuses to install the
    # host app with "Invalid placeholder attributes", which cost several macOS
    # runs to track down. These keys are checkable on Linux in milliseconds.
    plist_error = check_infoplists(objects, os.path.dirname(os.path.dirname(path)))
    if plist_error:
        print(plist_error)
        return 1

    isas = {}
    for oid, obj in objects.items():
        if isinstance(obj, dict):
            isas[obj.get('isa', '?')] = isas.get(obj.get('isa', '?'), 0) + 1

    print(f"PLIST OK — {len(objects)} objects, rootObject resolves, "
          f"no dangling refs, schemes resolve, Info.plists complete")
    for isa, n in sorted(isas.items()):
        print(f"    {n:3d}  {isa}")
    return 0


PLACEHOLDER_REQUIRED = [
    'CFBundleIdentifier',
    'CFBundleExecutable',
    'CFBundleName',
    'CFBundlePackageType',
    'CFBundleShortVersionString',
    # The one that actually broke: its absence is reported as "invalid
    # placeholder attributes", never as a missing key.
    'CFBundleVersion',
]


def check_infoplists(objects, root):
    """Validate every Info.plist referenced by an INFOPLIST_FILE setting.

    Returns an error string, or None when everything checks out.
    """
    paths = set()
    for obj in objects.values():
        if not isinstance(obj, dict) or obj.get('isa') != 'XCBuildConfiguration':
            continue
        value = (obj.get('buildSettings') or {}).get('INFOPLIST_FILE')
        if value:
            paths.add(value.strip('"'))

    for rel in sorted(paths):
        full = os.path.join(root, rel)
        if not os.path.exists(full):
            return f"INFOPLIST_FILE points at a missing file: {rel}"
        try:
            with open(full, 'rb') as handle:
                data = plistlib.load(handle)
        except Exception as exc:
            return f"{rel} is not a readable plist: {exc}"

        missing = [k for k in PLACEHOLDER_REQUIRED if not data.get(k)]
        if missing:
            return f"{rel} is missing required key(s): {', '.join(missing)}"

        # App extensions specifically.
        if data.get('CFBundlePackageType') == 'XPC!':
            extension = data.get('NSExtension')
            if not isinstance(extension, dict):
                return (f"{rel} declares CFBundlePackageType XPC! "
                        f"but has no NSExtension dictionary")
            if not extension.get('NSExtensionPointIdentifier'):
                return f"{rel} has NSExtension without NSExtensionPointIdentifier"

    return None


if __name__ == '__main__':
    try:
        code = main(sys.argv[1] if len(sys.argv) > 1 else 'Zoon.xcodeproj/project.pbxproj')
    except BrokenPipeError:
        # Output was piped into something that closed early (`| head`).
        code = 0
    sys.exit(code)
