#!/usr/bin/env python3
"""Fails when the project's platform floor or language mode drifts.

The audit's baseline is iOS 18 / watchOS 10 and Swift 5 language mode (Swift 6
is a staged migration, not a flag flip). A generator change that silently
raised a deployment target would drop supported devices; one that flipped the
language mode would surface hundreds of concurrency errors at once. Either
should be a deliberate edit to this file, not a side effect.
"""
import re
import sys
from pathlib import Path

EXPECTED = {
    "IPHONEOS_DEPLOYMENT_TARGET": {"18.0"},
    "WATCHOS_DEPLOYMENT_TARGET": {"10.0"},
    "SWIFT_VERSION": {"5.0"},
}

text = Path(sys.argv[1] if len(sys.argv) > 1 else "Zoon.xcodeproj/project.pbxproj").read_text()
failures = []
for key, allowed in EXPECTED.items():
    found = set(re.findall(rf"\b{key} = ([^;]+);", text))
    if not found:
        failures.append(f"{key}: not set anywhere")
    elif not found <= allowed:
        failures.append(f"{key}: found {sorted(found)}, expected {sorted(allowed)}")

if failures:
    print("Build settings drifted from the audited baseline:")
    for f in failures:
        print(f"  - {f}")
    sys.exit(1)
print("Build settings match the audited baseline: " + ", ".join(f"{k}={'/'.join(sorted(v))}" for k, v in EXPECTED.items()))
