#!/usr/bin/env python3
"""Strict parser for the old-style (NeXTSTEP) plist that pbxproj uses.

Written because structural checks on braces and UUIDs passed while Xcode still
rejected the file outright — a `name = ;` empty value is well-balanced and
completely invalid. This actually parses the grammar, so that class of bug
fails here instead of on a CI runner.
"""
import re
import sys

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

    isas = {}
    for oid, obj in objects.items():
        if isinstance(obj, dict):
            isas[obj.get('isa', '?')] = isas.get(obj.get('isa', '?'), 0) + 1

    print(f"PLIST OK — {len(objects)} objects, rootObject resolves, no dangling refs")
    for isa, n in sorted(isas.items()):
        print(f"    {n:3d}  {isa}")
    return 0


if __name__ == '__main__':
    try:
        code = main(sys.argv[1] if len(sys.argv) > 1 else 'Zoon.xcodeproj/project.pbxproj')
    except BrokenPipeError:
        # Output was piped into something that closed early (`| head`).
        code = 0
    sys.exit(code)
