#!/usr/bin/env python3
"""Fail CI when known App Store trust regressions return."""

from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[1]


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


violations: list[str] = []
project = read("Zoon.xcodeproj/project.pbxproj")

if "INFOPLIST_KEY_NSHealthUpdateUsageDescription" not in project:
    violations.append("The app archive must declare Apple's required HealthKit update purpose string.")
elif "never writes to or changes your Health data" not in project:
    violations.append("The HealthKit update purpose string must make Zoon's read-only boundary explicit.")

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

journal_ui = read("Zoon/Views/JournalView.swift")
if "Confirm and save" not in journal_ui or "confirmNaturalJournal" not in journal_ui:
    violations.append("Natural Journal must show an explicit confirmation step before saving observations.")
parser = read("Zoon/Insights/NaturalJournalParser.swift")
if "late coffee" not in parser or "Rule(tag: .caffeine, phrases:" not in parser:
    violations.append("Natural Journal must keep generic caffeine separate from explicitly late caffeine.")

if violations:
    print("Release trust audit failed:")
    for violation in violations:
        print(f"- {violation}")
    sys.exit(1)

print("Release trust audit passed.")
