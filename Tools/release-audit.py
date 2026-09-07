#!/usr/bin/env python3
"""Fail CI when known App Store trust regressions return."""

from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[1]


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


violations: list[str] = []
project = read("Zoon.xcodeproj/project.pbxproj")

if "NSHealthUpdateUsageDescription" in project:
    violations.append(
        "The read-only app declares NSHealthUpdateUsageDescription; only add it if Zoon starts writing Health data."
    )

user_surfaces = [
    path
    for folder in ("Zoon", "ZoonWidget", "ZoonWatch", "ZoonWatchWidget")
    for path in (ROOT / folder).rglob("*.swift")
]
for path in user_surfaces:
    source = path.read_text(encoding="utf-8")
    if "Cardiovascular Age" in source or "CardiovascularAgeCard" in source:
        violations.append(f"Unvalidated cardiovascular-age UI remains in {path.relative_to(ROOT)}")
    if "Sleep Regularity Index" in source or "sleep regularity index" in source:
        violations.append(f"Partial timing metric is presented as SRI in {path.relative_to(ROOT)}")

if violations:
    print("Release trust audit failed:")
    for violation in violations:
        print(f"- {violation}")
    sys.exit(1)

print("Release trust audit passed.")
