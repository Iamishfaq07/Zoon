#!/usr/bin/env python3
"""What Zoon.app's Info.plist must contain, checked on the bundle Xcode built.

Why this exists: the app's background audio mode, its AlarmKit purpose string
and its launch-screen colour were written as INFOPLIST_KEY_* build settings
that Xcode's Info.plist generator does not know. It drops unknown names
without a warning, so every build compiled clean, passed every test, and
shipped without them: Sleep Sounds and Snore Check stopped when the phone
locked, and AlarmKit could never be authorised. Nothing that reads source
could see it. Only the finished bundle says what was really written, so this
reads the finished bundle.

The same module holds the contract for Zoon/Info.plist itself (the keys the
generator cannot write), which Tools/validate-pbxproj.py checks on Linux in
milliseconds, before any macOS minute is spent. One list, two checkpoints.

Usage:
    python3 Tools/app_bundle_contract.py path/to/Zoon.app   # or .../Info.plist
    python3 Tools/app_bundle_contract.py --self-test

Exit status 1 names every missing or malformed key, as GitHub annotations.
"""
from __future__ import annotations

import contextlib
import io
import os
import plistlib
import sys
import tempfile

# Exactly these background modes and no others. App Review (guideline 2.5.4)
# expects each declared mode to be used for its purpose; audio is used for
# Sleep Sounds, the Wind Down narration and Snore Check. Adding a mode is a
# decision, so it means editing this tuple as well as Zoon/Info.plist.
BACKGROUND_MODES = ("audio",)

# The colour set the system launch screen fills with. Must exist in
# Zoon/Assets.xcassets (Tools/validate-pbxproj.py checks that).
LAUNCH_SCREEN_COLOR = "LaunchBackground"

# The keys Zoon/Info.plist has to carry itself, because no INFOPLIST_KEY_*
# build setting can produce them. Anything else belongs in build settings.
FILE_KEYS = ("UIBackgroundModes", "NSAlarmKitUsageDescription", "UILaunchScreen")

# A purpose string for every protected resource the app asks for, and what
# asks for it. A missing string is a crash at the request for HealthKit, the
# microphone, speech and calendars, and a feature that can never work for
# AlarmKit. NSCalendarsFullAccessUsageDescription is the one iOS 17+ reads for
# `requestFullAccessToEvents`; the app's floor is iOS 18.
USAGE_DESCRIPTIONS = {
    "NSHealthShareUsageDescription": "reading Health data (HealthKitManager)",
    "NSHealthUpdateUsageDescription": "HealthKit authorisation; states the read-only boundary",
    "NSMicrophoneUsageDescription": "Snore Check and Voice Journal",
    "NSSpeechRecognitionUsageDescription": "Voice Journal transcription",
    "NSCalendarsFullAccessUsageDescription": "tomorrow's first event (EventKitCommitmentReader)",
    "NSAlarmKitUsageDescription": "the wake alarm and nap alarms (WakeAlarm, NapWake)",
}


def _nonempty_string(data: dict, key: str, why: str) -> list[str]:
    value = data.get(key)
    if not isinstance(value, str) or not value.strip():
        return [f"{key} is missing or empty -- needed for {why}"]
    return []


def _background_modes(data: dict) -> list[str]:
    modes = data.get("UIBackgroundModes")
    if not isinstance(modes, list) or not all(isinstance(m, str) for m in modes):
        return ["UIBackgroundModes is missing (or not an array of strings): without "
                "'audio' iOS suspends Zoon seconds after lock, and Sleep Sounds, the "
                "Wind Down narration and Snore Check stop"]
    problems = []
    missing = [m for m in BACKGROUND_MODES if m not in modes]
    if missing:
        problems.append(f"UIBackgroundModes lacks {missing}: Sleep Sounds, the Wind Down "
                        "narration and Snore Check stop when the phone locks")
    extra = sorted(set(modes) - set(BACKGROUND_MODES))
    if extra:
        problems.append(f"UIBackgroundModes declares {extra}, which nothing in Zoon is "
                        "known to use (App Review 2.5.4). If a feature now needs it, add "
                        "it to BACKGROUND_MODES in Tools/app_bundle_contract.py as well")
    return problems


def _launch_screen(data: dict) -> list[str]:
    screen = data.get("UILaunchScreen")
    if not isinstance(screen, dict):
        return ["UILaunchScreen is missing (or not a dictionary): iOS then requires a "
                "launch storyboard, and the app has none"]
    if screen.get("UIColorName") != LAUNCH_SCREEN_COLOR:
        return [f"UILaunchScreen.UIColorName is {screen.get('UIColorName')!r}, expected "
                f"{LAUNCH_SCREEN_COLOR!r}: cold launch flashes the system background "
                "before the night gradient"]
    return []


def check_source_plist(data: object) -> list[str]:
    """The keys Zoon/Info.plist must declare itself. Returns problems."""
    if not isinstance(data, dict):
        return ["the plist is not a dictionary"]
    return (_background_modes(data)
            + _nonempty_string(data, "NSAlarmKitUsageDescription",
                               USAGE_DESCRIPTIONS["NSAlarmKitUsageDescription"])
            + _launch_screen(data))


def check_built_plist(data: object) -> list[str]:
    """The whole contract for the built Zoon.app/Info.plist. Returns problems."""
    if not isinstance(data, dict):
        return ["the plist is not a dictionary"]
    problems = _background_modes(data) + _launch_screen(data)
    for key, why in USAGE_DESCRIPTIONS.items():
        problems += _nonempty_string(data, key, why)
    for key in ("CFBundleIdentifier", "CFBundleExecutable",
                "CFBundleShortVersionString", "CFBundleVersion"):
        problems += _nonempty_string(data, key, "installing the app at all")
    if data.get("NSSupportsLiveActivities") is not True:
        problems.append("NSSupportsLiveActivities is not true: the nap and Wind Down "
                        "Live Activities cannot start")
    if not isinstance(data.get("UIApplicationSceneManifest"), dict):
        problems.append("UIApplicationSceneManifest is missing: the SwiftUI scene "
                        "configuration the app launches into")
    return problems


def load_plist(path: str) -> object:
    """Reads Info.plist from a bundle directory or a plist path (XML or binary)."""
    if os.path.isdir(path):
        path = os.path.join(path, "Info.plist")
    with open(path, "rb") as handle:
        return plistlib.load(handle)


def main(argv: list[str]) -> int:
    if argv == ["--self-test"]:
        self_test()
        return 0
    if len(argv) != 1:
        print(__doc__.strip().split("\n\nUsage:")[0])
        print("\nusage: app_bundle_contract.py <Zoon.app | Info.plist> | --self-test")
        return 2
    target = argv[0]
    try:
        data = load_plist(target)
    except (OSError, plistlib.InvalidFileException, ValueError) as error:
        print(f"::error::Could not read the built Info.plist at {target}: {error}")
        return 1
    problems = check_built_plist(data)
    if problems:
        print(f"The built Info.plist at {target} breaks the app's bundle contract:")
        for problem in problems:
            print(f"::error::{problem}")
        print("The keys Xcode's generator cannot write live in Zoon/Info.plist; the rest "
              "are INFOPLIST_KEY_* settings in Tools/generate-pbxproj.py.")
        return 1
    print(f"Bundle contract holds for {target}:")
    print(f"  UIBackgroundModes = {data['UIBackgroundModes']}")
    print(f"  UILaunchScreen.UIColorName = {data['UILaunchScreen']['UIColorName']}")
    print(f"  purpose strings present: {', '.join(sorted(USAGE_DESCRIPTIONS))}")
    print("  NSSupportsLiveActivities = true; scene manifest, identifier and versions present")
    return 0


def _good() -> dict:
    return {
        "CFBundleIdentifier": "com.zoon.sleep",
        "CFBundleExecutable": "Zoon",
        "CFBundleShortVersionString": "1.0",
        "CFBundleVersion": "1",
        "UIBackgroundModes": ["audio"],
        # The shape Xcode really writes when UILaunchScreen_Generation is also
        # on: the generated empty dictionary merged into the file's. Accepted.
        "UILaunchScreen": {"UIColorName": "LaunchBackground", "UILaunchScreen": {}},
        "NSSupportsLiveActivities": True,
        "UIApplicationSceneManifest": {"UIApplicationSupportsMultipleScenes": True,
                                       "UISceneConfigurations": {}},
        **{key: f"Purpose text for {key}." for key in USAGE_DESCRIPTIONS},
    }


def self_test() -> None:
    good = _good()
    assert check_built_plist(good) == [], check_built_plist(good)
    assert check_source_plist(good) == [], check_source_plist(good)

    def without(key: str) -> dict:
        data = dict(good)
        del data[key]
        return data

    def replaced(key: str, value: object) -> dict:
        data = dict(good)
        data[key] = value
        return data

    def fails(problems: list[str], *needles: str) -> None:
        assert problems, "expected a failure"
        for needle in needles:
            assert any(needle in p for p in problems), (needle, problems)

    # The exact bundle CI built before the fix (run 36353047082): no audio
    # mode, no AlarmKit string, a launch screen with no colour.
    before = without("UIBackgroundModes")
    del before["NSAlarmKitUsageDescription"]
    before["UILaunchScreen"] = {"UILaunchScreen": {}}
    fails(check_built_plist(before), "UIBackgroundModes is missing",
          "NSAlarmKitUsageDescription", "UIColorName")
    assert len(check_built_plist(before)) == 3, check_built_plist(before)
    fails(check_source_plist(before), "UIBackgroundModes", "NSAlarmKit", "UILaunchScreen")

    # Background modes: missing audio, an undeclared extra, the wrong type.
    fails(check_built_plist(replaced("UIBackgroundModes", [])), "lacks ['audio']")
    fails(check_built_plist(replaced("UIBackgroundModes", ["audio", "fetch"])), "['fetch']")
    fails(check_built_plist(replaced("UIBackgroundModes", "audio")), "not an array")

    # Every purpose string is required and must not be blank.
    for key in USAGE_DESCRIPTIONS:
        fails(check_built_plist(without(key)), key)
        fails(check_built_plist(replaced(key, "   ")), key)
    # The source contract only asks the file for what the generator cannot
    # write -- a HealthKit string there would be a second definition.
    assert check_source_plist({"UIBackgroundModes": ["audio"],
                               "NSAlarmKitUsageDescription": "x",
                               "UILaunchScreen": {"UIColorName": "LaunchBackground"}}) == []

    # Launch screen: wrong colour, wrong type.
    fails(check_built_plist(replaced("UILaunchScreen", {"UIColorName": "Other"})), "'Other'")
    fails(check_built_plist(replaced("UILaunchScreen", "LaunchBackground")), "not a dictionary")

    # The rest of the bundle contract.
    fails(check_built_plist(replaced("NSSupportsLiveActivities", False)), "Live Activities")
    fails(check_built_plist(without("UIApplicationSceneManifest")), "scene")
    fails(check_built_plist(replaced("CFBundleVersion", "")), "CFBundleVersion")
    assert check_built_plist(["not", "a", "dict"]) == ["the plist is not a dictionary"]

    # The CLI reads a bundle directory holding a *binary* plist, which is the
    # format Xcode writes, and exits non-zero on a broken one. Its output is
    # captured: in CI a printed `::error::` line becomes a red annotation on
    # the run even though this is the checker proving it can fail.
    with tempfile.TemporaryDirectory() as tmp:
        app = os.path.join(tmp, "Zoon.app")
        os.mkdir(app)
        with open(os.path.join(app, "Info.plist"), "wb") as handle:
            plistlib.dump(good, handle, fmt=plistlib.FMT_BINARY)
        with contextlib.redirect_stdout(io.StringIO()) as captured:
            assert main([app]) == 0
        assert "Bundle contract holds" in captured.getvalue(), captured.getvalue()
        with open(os.path.join(app, "Info.plist"), "wb") as handle:
            plistlib.dump(before, handle, fmt=plistlib.FMT_BINARY)
        with contextlib.redirect_stdout(io.StringIO()) as captured:
            assert main([app]) == 1
            assert main([os.path.join(tmp, "Missing.app")]) == 1
        assert captured.getvalue().count("::error::") == 4, captured.getvalue()

    # The checked-in file satisfies its half of the contract.
    here = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                        "Zoon", "Info.plist")
    if os.path.exists(here):
        assert check_source_plist(load_plist(here)) == [], check_source_plist(load_plist(here))

    print("self-test passed")


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
