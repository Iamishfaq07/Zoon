#!/usr/bin/env python3
"""Fails when the project's platform floor or language mode drifts.

The audit's baseline is iOS 18 / watchOS 10 and Swift 5 language mode (Swift 6
is a staged migration, not a flag flip). A generator change that silently
raised a deployment target would drop supported devices; one that flipped the
language mode would surface hundreds of concurrency errors at once. Either
should be a deliberate edit to this file, not a side effect.
"""
import json
import re
import sys
from pathlib import Path

EXPECTED = {
    "IPHONEOS_DEPLOYMENT_TARGET": {"18.0"},
    "WATCHOS_DEPLOYMENT_TARGET": {"10.0"},
    "SWIFT_VERSION": {"5.0"},
    # Audit §15: literals are extracted into the String Catalogs below.
    "LOCALIZATION_PREFERS_STRING_CATALOGS": {"YES"},
    "SWIFT_EMIT_LOC_STRINGS": {"YES"},
}

# Every target a person reads text from has an English-source String Catalog.
CATALOGS = ["Zoon/Localizable.xcstrings", "ZoonWidget/Localizable.xcstrings", "ZoonWatch/Localizable.xcstrings"]

text = Path(sys.argv[1] if len(sys.argv) > 1 else "Zoon.xcodeproj/project.pbxproj").read_text()
failures = []
for key, allowed in EXPECTED.items():
    found = set(re.findall(rf"\b{key} = ([^;]+);", text))
    if not found:
        failures.append(f"{key}: not set anywhere")
    elif not found <= allowed:
        failures.append(f"{key}: found {sorted(found)}, expected {sorted(allowed)}")

root = Path(sys.argv[1]).resolve().parent.parent if len(sys.argv) > 1 else Path(".")
for catalog in CATALOGS:
    path = root / catalog
    if not path.exists():
        failures.append(f"{catalog}: missing")
        continue
    try:
        data = json.loads(path.read_text())
    except json.JSONDecodeError as error:
        failures.append(f"{catalog}: not valid JSON ({error})")
        continue
    if data.get("sourceLanguage") != "en":
        failures.append(f"{catalog}: sourceLanguage is {data.get('sourceLanguage')!r}, expected 'en'")
    if not isinstance(data.get("strings"), dict):
        failures.append(f"{catalog}: no 'strings' table")
# One Copy Bundle Resources entry per catalog: a catalog on disk that no
# target copies is a catalog nothing is ever translated from.
bundled = len(re.findall(r"/\* Localizable\.xcstrings in Resources \*/ = \{isa = PBXBuildFile", text))
if bundled < len(CATALOGS):
    failures.append(f"String Catalogs: {bundled} bundled into targets, expected {len(CATALOGS)}")

if failures:
    print("Build settings drifted from the audited baseline:")
    for f in failures:
        print(f"  - {f}")
    sys.exit(1)
print("Build settings match the audited baseline: " + ", ".join(f"{k}={'/'.join(sorted(v))}" for k, v in EXPECTED.items()))
