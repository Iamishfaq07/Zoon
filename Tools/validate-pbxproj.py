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

# The app's Info.plist contract lives beside this script so the Linux check
# here and the check on the built bundle (build.yml, screenshots.yml,
# testflight.yml) read one list.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import app_bundle_contract  # noqa: E402

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

    # ZoonTests is a standalone library bundle: no TEST_HOST, no
    # BUNDLE_LOADER, so there is no "Zoon" module for @testable to import and
    # the target fails with "unable to resolve module dependency: 'Zoon'".
    # App-side code reaches these tests by being listed in
    # TESTS_EXTRA_APP_FILES (generate-pbxproj.py), which compiles it directly
    # into the bundle -- so the symbols are already visible with no import at
    # all. This has now cost two separate ~10-minute macOS runs; catching it
    # here costs milliseconds, on Linux, before anything is compiled.
    testable_error = check_no_testable_import(os.path.dirname(os.path.dirname(path)))
    if testable_error:
        print(testable_error)
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



def check_no_testable_import(root):
    """Reject `@testable import Zoon` anywhere under ZoonTests/."""
    folder = os.path.join(root, 'ZoonTests')
    if not os.path.isdir(folder):
        return None
    offenders = []
    for dirpath, dirnames, filenames in os.walk(folder):
        for name in sorted(filenames):
            if not name.endswith('.swift'):
                continue
            full = os.path.join(dirpath, name)
            with open(full, encoding='utf-8') as handle:
                for number, line in enumerate(handle, 1):
                    if line.strip() == '@testable import Zoon':
                        rel = os.path.relpath(full, root)
                        offenders.append(f"{rel}:{number}")
    if not offenders:
        return None
    listed = '\n  '.join(offenders)
    return ("`@testable import Zoon` cannot work in ZoonTests -- the target "
            "has no TEST_HOST, so no Zoon module exists to import:\n  "
            f"{listed}\n"
            "Delete the line. If the symbol it was reaching for is app-side, "
            "add that file to TESTS_EXTRA_APP_FILES in "
            "Tools/generate-pbxproj.py and regenerate.")


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


# With GENERATE_INFOPLIST_FILE = YES, Xcode writes each placeholder key from
# a build setting and merges it over the INFOPLIST_FILE, so for those
# configurations the file need not carry them -- but the settings must exist.
# EXECUTABLE_NAME and PRODUCT_BUNDLE_PACKAGE_TYPE always have Xcode defaults.
GENERATED_PLACEHOLDER_SETTINGS = {
    'CFBundleIdentifier': 'PRODUCT_BUNDLE_IDENTIFIER',
    'CFBundleName': 'PRODUCT_NAME',
    'CFBundleShortVersionString': 'MARKETING_VERSION',
    'CFBundleVersion': 'CURRENT_PROJECT_VERSION',
}


def _unquote(value):
    return value.strip('"') if isinstance(value, str) else value


def _configurations(objects, owner):
    """The XCBuildConfiguration objects of a target or project object."""
    lst = objects.get(owner.get('buildConfigurationList'), {})
    return [objects[c] for c in lst.get('buildConfigurations', []) if c in objects]


def _infoplist_key_settings(settings):
    """The Info.plist keys a configuration sets through INFOPLIST_KEY_*.

    Maps Xcode's macro spelling back to the key it writes: `_iPhone` and
    `_iPad` suffixes stand for the `~iphone` and `~ipad` variants.
    """
    keys = set()
    for name in settings:
        if name.startswith('INFOPLIST_KEY_'):
            key = name[len('INFOPLIST_KEY_'):]
            keys.add(key.replace('_iPhone', '~iphone').replace('_iPad', '~ipad'))
    return keys


def check_infoplists(objects, root):
    """Validate every Info.plist referenced by an INFOPLIST_FILE setting.

    Returns an error string, or None when everything checks out.
    """
    project = next((o for o in objects.values()
                    if isinstance(o, dict) and o.get('isa') == 'PBXProject'), {})
    project_settings = {c.get('name'): c.get('buildSettings') or {}
                        for c in _configurations(objects, project)}

    loaded = {}

    def load(rel):
        if rel not in loaded:
            full = os.path.join(root, rel)
            if not os.path.exists(full):
                return None, f"INFOPLIST_FILE points at a missing file: {rel}"
            try:
                with open(full, 'rb') as handle:
                    loaded[rel] = plistlib.load(handle)
            except Exception as exc:
                return None, f"{rel} is not a readable plist: {exc}"
        return loaded[rel], None

    for oid in sorted(objects):
        obj = objects[oid]
        if not isinstance(obj, dict) or obj.get('isa') != 'XCBuildConfiguration':
            continue
        settings = obj.get('buildSettings') or {}
        rel = _unquote(settings.get('INFOPLIST_FILE'))
        if not rel:
            continue
        data, error = load(rel)
        if error:
            return error
        if not isinstance(data, dict):
            return f"{rel} is not a dictionary"

        generated = _unquote(settings.get('GENERATE_INFOPLIST_FILE')) == 'YES'
        if generated:
            effective = {**project_settings.get(obj.get('name'), {}), **settings}
            unset = [f"{key} (from {setting})"
                     for key, setting in GENERATED_PLACEHOLDER_SETTINGS.items()
                     if not data.get(key) and not _unquote(effective.get(setting))]
            if unset:
                return (f"{rel} ({obj.get('name')}) relies on GENERATE_INFOPLIST_FILE for "
                        f"{', '.join(unset)}, but the build setting is not set")
            # One definition per key. A generated scalar silently replaces the
            # file's, so the file would say one thing and the bundle another.
            twice = sorted(_infoplist_key_settings(settings) & set(data))
            if twice:
                return (f"{rel} and INFOPLIST_KEY_* settings ({obj.get('name')}) both define "
                        f"{', '.join(twice)}; keep each key in one place")
        else:
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

    return check_app_infoplist(objects, root, load)


def check_app_infoplist(objects, root, load):
    """The iOS app's own Info.plist: present in every configuration, generated
    keys still on, and carrying what only the file can say.

    Every build before this check shipped without background audio or the
    AlarmKit purpose string, because they were INFOPLIST_KEY_* settings Xcode
    ignores. This makes the file that replaced them impossible to unhook
    quietly: dropping INFOPLIST_FILE from one configuration, or a key from
    the file, fails here in milliseconds on Linux.
    """
    apps = []
    for obj in objects.values():
        if not isinstance(obj, dict) or obj.get('isa') != 'PBXNativeTarget':
            continue
        if _unquote(obj.get('productType')) != 'com.apple.product-type.application':
            continue
        configs = _configurations(objects, obj)
        if any(_unquote((c.get('buildSettings') or {}).get('SDKROOT')) == 'watchos'
               for c in configs):
            continue
        apps.append((obj, configs))
    if len(apps) != 1:
        return f"expected exactly one iOS application target, found {len(apps)}"
    target, configs = apps[0]
    name = target.get('name')

    for config in configs:
        settings = config.get('buildSettings') or {}
        label = f"{name} ({config.get('name')})"
        rel = _unquote(settings.get('INFOPLIST_FILE'))
        if not rel:
            return (f"{label} has no INFOPLIST_FILE, so the built app loses background "
                    "audio, the AlarmKit purpose string and the launch-screen colour")
        if _unquote(settings.get('GENERATE_INFOPLIST_FILE')) != 'YES':
            return (f"{label} turned GENERATE_INFOPLIST_FILE off, so none of its "
                    "INFOPLIST_KEY_* purpose strings would be written")
        data, error = load(rel)
        if error:
            return error
        problems = app_bundle_contract.check_source_plist(data)
        if problems:
            return f"{rel} ({label}): " + "; ".join(problems)
        colour = data['UILaunchScreen']['UIColorName']
        colourset = os.path.join(os.path.dirname(rel), 'Assets.xcassets',
                                 f"{colour}.colorset", 'Contents.json')
        if not os.path.exists(os.path.join(root, colourset)):
            return f"{rel} names launch colour {colour!r}, but {colourset} does not exist"

    # Copied as a resource as well as processed, the plist makes the build
    # fail with "Multiple commands produce .../Info.plist".
    for phase_id in target.get('buildPhases', []):
        phase = objects.get(phase_id, {})
        if phase.get('isa') != 'PBXResourcesBuildPhase':
            continue
        for build_file in phase.get('files', []):
            ref = objects.get(objects.get(build_file, {}).get('fileRef'), {})
            if os.path.basename(_unquote(ref.get('path') or '')) == 'Info.plist':
                return f"{name} copies an Info.plist in Copy Bundle Resources"
    return None


if __name__ == '__main__':
    try:
        code = main(sys.argv[1] if len(sys.argv) > 1 else 'Zoon.xcodeproj/project.pbxproj')
    except BrokenPipeError:
        # Output was piped into something that closed early (`| head`).
        code = 0
    sys.exit(code)
