#!/usr/bin/env python3
"""Fails when the project's platform floor or language mode drifts, or when a
build setting asks Xcode for an Info.plist key it will never write.

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

# Every INFOPLIST_KEY_* name Xcode's Info.plist generator actually writes.
#
# The generator (swift-build, Sources/SWBTaskExecution/TaskActions/
# InfoPlistProcessorTaskAction.swift, `defaultInfoPlistContent`) copies a
# fixed list -- `generatedInfoPlistKeys`, `usageDescriptionStringKeys` and the
# two `_Generation` switches -- and only for names that
# Sources/SWBCore/Settings/BuiltinMacros.swift declares. Any other
# INFOPLIST_KEY_* setting is dropped without a warning or an error. That is how
# UIBackgroundModes, NSAlarmKitUsageDescription and
# UILaunchScreen_BackgroundColor were absent from every build while the project
# file said otherwise. A key that is not on this list belongs in the target's
# INFOPLIST_FILE (for the app, Zoon/Info.plist). `~iphone`/`~ipad` variants are
# spelled `_iPhone`/`_iPad` in the setting name, as below.
#
# Taken from swift-build `main`, September 2026 (Xcode 26.6 builds here). If a
# newer Xcode learns a key, add it only once a built bundle shows it written.
SUPPORTED_INFOPLIST_KEYS = frozenset({
    "CFBundleDisplayName", "CLKComplicationPrincipalClass",
    "GCSupportsControllerUserInteraction", "GCSupportsGameMode",
    "ITSAppUsesNonExemptEncryption", "ITSEncryptionExportComplianceCode",
    "LSApplicationCategoryType", "LSBackgroundOnly", "LSSupportsOpeningDocumentsInPlace",
    "LSUIElement", "MetalCaptureEnabled", "NFCReaderUsageDescription",
    "NSAccessoryTrackingUsageDescription", "NSAppDataUsageDescription",
    "NSAppleEventsUsageDescription", "NSAppleMusicUsageDescription",
    "NSBluetoothAlwaysUsageDescription", "NSBluetoothPeripheralUsageDescription",
    "NSBluetoothWhileInUseUsageDescription", "NSCalendarsFullAccessUsageDescription",
    "NSCalendarsUsageDescription", "NSCalendarsWriteOnlyAccessUsageDescription",
    "NSCameraUsageDescription", "NSContactsUsageDescription",
    "NSCriticalMessagingUsageDescription", "NSDesktopFolderUsageDescription",
    "NSDocumentsFolderUsageDescription", "NSDownloadsFolderUsageDescription",
    "NSFaceIDUsageDescription", "NSFallDetectionUsageDescription",
    "NSFileProviderDomainUsageDescription", "NSFileProviderPresenceUsageDescription",
    "NSFinancialDataUsageDescription", "NSFocusStatusUsageDescription",
    "NSGKFriendListUsageDescription", "NSHandsTrackingUsageDescription",
    "NSHealthClinicalHealthRecordsShareUsageDescription", "NSHealthShareUsageDescription",
    "NSHealthUpdateUsageDescription", "NSHomeKitUsageDescription",
    "NSHumanReadableCopyright", "NSIdentityUsageDescription",
    "NSLocalNetworkUsageDescription", "NSLocationAlwaysAndWhenInUseUsageDescription",
    "NSLocationAlwaysUsageDescription", "NSLocationUsageDescription",
    "NSLocationWhenInUseUsageDescription", "NSMainNibFile", "NSMainStoryboardFile",
    "NSMicrophoneUsageDescription", "NSMotionUsageDescription",
    "NSNearbyInteractionAllowOnceUsageDescription", "NSNearbyInteractionUsageDescription",
    "NSNetworkVolumesUsageDescription", "NSPhotoLibraryAddUsageDescription",
    "NSPhotoLibraryUsageDescription", "NSPrincipalClass",
    "NSRemindersFullAccessUsageDescription", "NSRemindersUsageDescription",
    "NSRemovableVolumesUsageDescription", "NSSensorKitPrivacyPolicyURL",
    "NSSensorKitUsageDescription", "NSSiriUsageDescription",
    "NSSpeechRecognitionUsageDescription", "NSStickerSharingLevel",
    "NSSupportsLiveActivities", "NSSupportsLiveActivitiesFrequentUpdates",
    "NSSystemAdministrationUsageDescription", "NSSystemExtensionUsageDescription",
    "NSUserTrackingUsageDescription", "NSVideoSubscriberAccountUsageDescription",
    "NSViewGestureRecognizerIsExclusive", "NSVoIPUsageDescription",
    "NSWorldSensingUsageDescription", "OSBundleUsageDescription",
    "UIApplicationSceneManifest_Generation", "UIApplicationSupportsIndirectInputEvents",
    "UILaunchScreen_Generation", "UILaunchStoryboardName", "UIMainStoryboardFile",
    "UIRequiredDeviceCapabilities", "UIRequiresFullScreen", "UIStatusBarHidden",
    "UIStatusBarStyle", "UISupportedInterfaceOrientations",
    "UISupportedInterfaceOrientations_iPad", "UISupportedInterfaceOrientations_iPhone",
    "UISupportsDocumentBrowser", "UIUserInterfaceStyle", "WKApplication",
    "WKCompanionAppBundleIdentifier", "WKExtensionDelegateClassName",
    "WKRunsIndependentlyOfCompanionApp", "WKSupportsLiveActivityLaunchAttributeTypes",
    "WKWatchOnly",
})

text = Path(sys.argv[1] if len(sys.argv) > 1 else "Zoon.xcodeproj/project.pbxproj").read_text(encoding="utf-8")
failures = []
for key, allowed in EXPECTED.items():
    found = set(re.findall(rf"\b{key} = ([^;]+);", text))
    if not found:
        failures.append(f"{key}: not set anywhere")
    elif not found <= allowed:
        failures.append(f"{key}: found {sorted(found)}, expected {sorted(allowed)}")

# An assignment, not a mention: comments in the project file talk about
# INFOPLIST_KEY_* settings without setting one.
infoplist_keys = sorted(set(re.findall(r"\bINFOPLIST_KEY_([A-Za-z0-9_]+)\s*=", text)))
for name in infoplist_keys:
    if name not in SUPPORTED_INFOPLIST_KEYS:
        failures.append(
            f"INFOPLIST_KEY_{name}: Xcode's Info.plist generator ignores this setting, so "
            "whatever it was meant to write never reaches the built bundle. Write that key "
            "in the target's INFOPLIST_FILE (for the app, Zoon/Info.plist) instead."
        )

root = Path(sys.argv[1]).resolve().parent.parent if len(sys.argv) > 1 else Path(".")
for catalog in CATALOGS:
    path = root / catalog
    if not path.exists():
        failures.append(f"{catalog}: missing")
        continue
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
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
print(f"All {len(infoplist_keys)} INFOPLIST_KEY_* names are ones Xcode's generator writes: "
      + ", ".join(infoplist_keys))
