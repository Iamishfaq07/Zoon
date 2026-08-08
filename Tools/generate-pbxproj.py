#!/usr/bin/env python3
"""Generate Zoon.xcodeproj/project.pbxproj with explicit file references.

Classic pbxproj format (objectVersion 56) so it opens in Xcode 15 and 16 alike,
and so Shared/ membership in both targets is expressed the ordinary way: the
same PBXFileReference appears in two PBXSourcesBuildPhases via two distinct
PBXBuildFile entries.
"""
import hashlib
import os

ROOT = "/home/user/Zoon"

APP = "Zoon"
EXT = "ZoonWidgetExtension"

_used = {}


def uid(key):
    """Deterministic 24-char uppercase hex ID from a key."""
    h = hashlib.md5(key.encode()).hexdigest()[:24].upper()
    if h in _used and _used[h] != key:
        raise SystemExit(f"UUID collision: {key} vs {_used[h]}")
    _used[h] = key
    return h


def swift_files(folder):
    out = []
    for dirpath, dirnames, filenames in os.walk(os.path.join(ROOT, folder)):
        dirnames[:] = sorted(d for d in dirnames if not d.endswith(".xcassets"))
        for f in sorted(filenames):
            if f.endswith(".swift"):
                out.append(os.path.relpath(os.path.join(dirpath, f), ROOT))
    return sorted(out)


SHARED = swift_files("Shared")
APP_SRC = swift_files("Zoon")
EXT_SRC = swift_files("ZoonWidget")

APP_ASSETS = "Zoon/Assets.xcassets"
EXT_ASSETS = "ZoonWidget/Assets.xcassets"
DOCS = ["README.md", "SETUP.md", "project.yml", "LICENSE", ".gitignore"]

# ---------------------------------------------------------------- objects

obj = []


def emit(section, body):
    obj.append((section, body))


# --- PBXFileReference -----------------------------------------------------
def file_ref(path, ftype=None, name=None):
    fid = uid("ref:" + path)
    base = name or os.path.basename(path)
    if ftype is None:
        if base.endswith(".swift"):
            ftype = "sourcecode.swift"
        elif base.endswith(".xcassets"):
            ftype = "folder.assetcatalog"
        elif base.endswith(".md"):
            ftype = "net.daringfireball.markdown"
        elif base.endswith(".yml"):
            ftype = "text.yaml"
        else:
            ftype = "text"
    emit("PBXFileReference",
         f'\t\t{fid} /* {base} */ = {{isa = PBXFileReference; '
         f'lastKnownFileType = {ftype}; path = "{base}"; sourceTree = "<group>"; }};')
    return fid


refs = {}
for p in SHARED + APP_SRC + EXT_SRC + [APP_ASSETS, EXT_ASSETS] + DOCS:
    refs[p] = file_ref(p)

APP_PRODUCT = uid("product:app")
EXT_PRODUCT = uid("product:ext")
emit("PBXFileReference",
     f'\t\t{APP_PRODUCT} /* Zoon.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; '
     f'includeInIndex = 0; path = Zoon.app; sourceTree = BUILT_PRODUCTS_DIR; }};')
emit("PBXFileReference",
     f'\t\t{EXT_PRODUCT} /* {EXT}.appex */ = {{isa = PBXFileReference; '
     f'explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = {EXT}.appex; '
     f'sourceTree = BUILT_PRODUCTS_DIR; }};')


# --- PBXBuildFile ---------------------------------------------------------
def build_file(path, target):
    bid = uid(f"build:{target}:{path}")
    base = os.path.basename(path)
    emit("PBXBuildFile",
         f'\t\t{bid} /* {base} in Sources */ = {{isa = PBXBuildFile; '
         f'fileRef = {refs[path]} /* {base} */; }};')
    return bid


app_sources = [build_file(p, APP) for p in APP_SRC + SHARED]
ext_sources = [build_file(p, EXT) for p in EXT_SRC + SHARED]


def resource_file(path, target):
    bid = uid(f"res:{target}:{path}")
    base = os.path.basename(path)
    emit("PBXBuildFile",
         f'\t\t{bid} /* {base} in Resources */ = {{isa = PBXBuildFile; '
         f'fileRef = {refs[path]} /* {base} */; }};')
    return bid


app_resources = [resource_file(APP_ASSETS, APP)]
ext_resources = [resource_file(EXT_ASSETS, EXT)]

EMBED_BF = uid("embed:appex")
emit("PBXBuildFile",
     f'\t\t{EMBED_BF} /* {EXT}.appex in Embed Foundation Extensions */ = {{isa = PBXBuildFile; '
     f'fileRef = {EXT_PRODUCT} /* {EXT}.appex */; '
     f'settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};')


# --- PBXGroup -------------------------------------------------------------
def group(key, name, children, path=None):
    gid = uid("group:" + key)
    kids = "\n".join(f'\t\t\t\t{c},' for c in children)
    # An empty value ("name = ;") is a plist parse error, and Xcode rejects the
    # whole project for it. The root group legitimately has neither name nor
    # path, so both lines must be omitted rather than emitted blank.
    path_line = f'\n\t\t\tpath = {path};' if path else ''
    name_line = f'\n\t\t\tname = {name};' if (not path and name) else ''
    comment = f' /* {name} */' if name else ''
    emit("PBXGroup",
         f'\t\t{gid}{comment} = {{\n'
         f'\t\t\tisa = PBXGroup;\n'
         f'\t\t\tchildren = (\n{kids}\n\t\t\t);'
         f'{name_line}{path_line}\n'
         f'\t\t\tsourceTree = "<group>";\n'
         f'\t\t}};')
    return gid


def tree_groups(prefix, files, extra=()):
    """Build nested groups mirroring the directory layout under `prefix`."""
    subdirs = {}
    direct = []
    for p in files:
        rel = os.path.relpath(p, prefix)
        if os.sep in rel:
            head = rel.split(os.sep)[0]
            subdirs.setdefault(head, []).append(p)
        else:
            direct.append(p)
    children = []
    for name in sorted(subdirs):
        children.append(tree_groups(os.path.join(prefix, name), subdirs[name]))
    children += [refs[p] for p in sorted(direct)]
    children += list(extra)
    return group(prefix, os.path.basename(prefix), children, path=os.path.basename(prefix))


shared_group = tree_groups("Shared", SHARED)
app_group = tree_groups("Zoon", APP_SRC, extra=[refs[APP_ASSETS]])
ext_group = tree_groups("ZoonWidget", EXT_SRC, extra=[refs[EXT_ASSETS]])
docs_group = group("docs", "Documentation", [refs[d] for d in DOCS])
products_group = group("products", "Products", [APP_PRODUCT, EXT_PRODUCT])
main_group = group("main", "", [shared_group, app_group, ext_group, docs_group, products_group])

# --- Build phases ---------------------------------------------------------
APP_SOURCES_PHASE = uid("phase:app:sources")
EXT_SOURCES_PHASE = uid("phase:ext:sources")
APP_RES_PHASE = uid("phase:app:res")
EXT_RES_PHASE = uid("phase:ext:res")
APP_FW_PHASE = uid("phase:app:fw")
EXT_FW_PHASE = uid("phase:ext:fw")
EMBED_PHASE = uid("phase:app:embed")


def phase(pid, isa, name, files, extra=""):
    listed = "\n".join(f'\t\t\t\t{f},' for f in files)
    emit(isa,
         f'\t\t{pid} /* {name} */ = {{\n'
         f'\t\t\tisa = {isa};\n'
         f'\t\t\tbuildActionMask = 2147483647;\n'
         f'{extra}'
         f'\t\t\tfiles = (\n{listed}\n\t\t\t);\n'
         f'{"" if isa != "PBXCopyFilesBuildPhase" else chr(9) * 3 + "name = " + chr(34) + name + chr(34) + ";" + chr(10)}'
         f'\t\t\trunOnlyForDeploymentPostprocessing = 0;\n'
         f'\t\t}};')


phase(APP_SOURCES_PHASE, "PBXSourcesBuildPhase", "Sources", app_sources)
phase(EXT_SOURCES_PHASE, "PBXSourcesBuildPhase", "Sources", ext_sources)
phase(APP_RES_PHASE, "PBXResourcesBuildPhase", "Resources", app_resources)
phase(EXT_RES_PHASE, "PBXResourcesBuildPhase", "Resources", ext_resources)
phase(APP_FW_PHASE, "PBXFrameworksBuildPhase", "Frameworks", [])
phase(EXT_FW_PHASE, "PBXFrameworksBuildPhase", "Frameworks", [])
phase(EMBED_PHASE, "PBXCopyFilesBuildPhase", "Embed Foundation Extensions", [EMBED_BF],
      extra='\t\t\tdstPath = "";\n\t\t\tdstSubfolderSpec = 13;\n')

# --- Target dependency ----------------------------------------------------
PROJECT = uid("project")
APP_TARGET = uid("target:app")
EXT_TARGET = uid("target:ext")
PROXY = uid("proxy:ext")
DEP = uid("dep:ext")

emit("PBXContainerItemProxy",
     f'\t\t{PROXY} /* PBXContainerItemProxy */ = {{\n'
     f'\t\t\tisa = PBXContainerItemProxy;\n'
     f'\t\t\tcontainerPortal = {PROJECT} /* Project object */;\n'
     f'\t\t\tproxyType = 1;\n'
     f'\t\t\tremoteGlobalIDString = {EXT_TARGET};\n'
     f'\t\t\tremoteInfo = {EXT};\n'
     f'\t\t}};')
emit("PBXTargetDependency",
     f'\t\t{DEP} /* PBXTargetDependency */ = {{\n'
     f'\t\t\tisa = PBXTargetDependency;\n'
     f'\t\t\ttarget = {EXT_TARGET} /* {EXT} */;\n'
     f'\t\t\ttargetProxy = {PROXY} /* PBXContainerItemProxy */;\n'
     f'\t\t}};')

# --- Targets --------------------------------------------------------------
APP_CFG_LIST = uid("cfglist:app")
EXT_CFG_LIST = uid("cfglist:ext")
PROJ_CFG_LIST = uid("cfglist:project")

emit("PBXNativeTarget",
     f'\t\t{APP_TARGET} /* {APP} */ = {{\n'
     f'\t\t\tisa = PBXNativeTarget;\n'
     f'\t\t\tbuildConfigurationList = {APP_CFG_LIST} /* Build configuration list for PBXNativeTarget "{APP}" */;\n'
     f'\t\t\tbuildPhases = (\n'
     f'\t\t\t\t{APP_SOURCES_PHASE} /* Sources */,\n'
     f'\t\t\t\t{APP_FW_PHASE} /* Frameworks */,\n'
     f'\t\t\t\t{APP_RES_PHASE} /* Resources */,\n'
     f'\t\t\t\t{EMBED_PHASE} /* Embed Foundation Extensions */,\n'
     f'\t\t\t);\n'
     f'\t\t\tbuildRules = (\n\t\t\t);\n'
     f'\t\t\tdependencies = (\n\t\t\t\t{DEP} /* PBXTargetDependency */,\n\t\t\t);\n'
     f'\t\t\tname = {APP};\n'
     f'\t\t\tproductName = {APP};\n'
     f'\t\t\tproductReference = {APP_PRODUCT} /* Zoon.app */;\n'
     f'\t\t\tproductType = "com.apple.product-type.application";\n'
     f'\t\t}};')

emit("PBXNativeTarget",
     f'\t\t{EXT_TARGET} /* {EXT} */ = {{\n'
     f'\t\t\tisa = PBXNativeTarget;\n'
     f'\t\t\tbuildConfigurationList = {EXT_CFG_LIST} /* Build configuration list for PBXNativeTarget "{EXT}" */;\n'
     f'\t\t\tbuildPhases = (\n'
     f'\t\t\t\t{EXT_SOURCES_PHASE} /* Sources */,\n'
     f'\t\t\t\t{EXT_FW_PHASE} /* Frameworks */,\n'
     f'\t\t\t\t{EXT_RES_PHASE} /* Resources */,\n'
     f'\t\t\t);\n'
     f'\t\t\tbuildRules = (\n\t\t\t);\n'
     f'\t\t\tdependencies = (\n\t\t\t);\n'
     f'\t\t\tname = {EXT};\n'
     f'\t\t\tproductName = {EXT};\n'
     f'\t\t\tproductReference = {EXT_PRODUCT} /* {EXT}.appex */;\n'
     f'\t\t\tproductType = "com.apple.product-type.app-extension";\n'
     f'\t\t}};')

emit("PBXProject",
     f'\t\t{PROJECT} /* Project object */ = {{\n'
     f'\t\t\tisa = PBXProject;\n'
     f'\t\t\tattributes = {{\n'
     f'\t\t\t\tBuildIndependentTargetsInParallel = 1;\n'
     f'\t\t\t\tLastSwiftUpdateCheck = 1520;\n'
     f'\t\t\t\tLastUpgradeCheck = 1520;\n'
     f'\t\t\t\tTargetAttributes = {{\n'
     f'\t\t\t\t\t{APP_TARGET} = {{CreatedOnToolsVersion = 15.2; }};\n'
     f'\t\t\t\t\t{EXT_TARGET} = {{CreatedOnToolsVersion = 15.2; }};\n'
     f'\t\t\t\t}};\n'
     f'\t\t\t}};\n'
     f'\t\t\tbuildConfigurationList = {PROJ_CFG_LIST} /* Build configuration list for PBXProject "{APP}" */;\n'
     f'\t\t\tcompatibilityVersion = "Xcode 14.0";\n'
     f'\t\t\tdevelopmentRegion = en;\n'
     f'\t\t\thasScannedForEncodings = 0;\n'
     f'\t\t\tknownRegions = (\n\t\t\t\ten,\n\t\t\t\tBase,\n\t\t\t);\n'
     f'\t\t\tmainGroup = {main_group};\n'
     f'\t\t\tproductRefGroup = {products_group} /* Products */;\n'
     f'\t\t\tprojectDirPath = "";\n'
     f'\t\t\tprojectRoot = "";\n'
     f'\t\t\ttargets = (\n'
     f'\t\t\t\t{APP_TARGET} /* {APP} */,\n'
     f'\t\t\t\t{EXT_TARGET} /* {EXT} */,\n'
     f'\t\t\t);\n'
     f'\t\t}};')

# --- Build configurations -------------------------------------------------
HEALTH_DESC = ("Zoon reads your sleep, heart rate, HRV, respiratory rate, blood oxygen "
               "and wrist temperature to explain how you slept. Everything is processed "
               "on this device and never leaves it.")

PROJ_COMMON = """				ALWAYS_SEARCH_USER_PATHS = NO;
				ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES;
				CLANG_ANALYZER_NONNULL = YES;
				CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION = YES_AGGRESSIVE;
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				CLANG_WARN_BOOL_CONVERSION = YES;
				CLANG_WARN_DOCUMENTATION_COMMENTS = YES;
				CLANG_WARN_EMPTY_BODY = YES;
				CLANG_WARN_UNREACHABLE_CODE = YES;
				COPY_PHASE_STRIP = NO;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				ENABLE_USER_SCRIPT_SANDBOXING = YES;
				GCC_C_LANGUAGE_STANDARD = gnu17;
				GCC_NO_COMMON_BLOCKS = YES;
				GCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
				GCC_WARN_UNUSED_VARIABLE = YES;
				IPHONEOS_DEPLOYMENT_TARGET = 18.0;
				LOCALIZATION_PREFERS_STRING_CATALOGS = YES;
				MTL_FAST_MATH = YES;
				SDKROOT = iphoneos;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = 1;
"""

# GENERATE_INFOPLIST_FILE is deliberately *not* here: the app generates its
# Info.plist and the extension ships an explicit one. See EXT_SETTINGS.
TARGET_COMMON = """				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				ENABLE_PREVIEWS = YES;
				MARKETING_VERSION = 1.0;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_EMIT_LOC_STRINGS = YES;
"""

configs = {
    uid("cfg:proj:Debug"): ("Debug", PROJ_COMMON + """				DEBUG_INFORMATION_FORMAT = dwarf;
				ENABLE_TESTABILITY = YES;
				GCC_DYNAMIC_NO_PIC = NO;
				GCC_OPTIMIZATION_LEVEL = 0;
				GCC_PREPROCESSOR_DEFINITIONS = (
					"DEBUG=1",
					"$(inherited)",
				);
				MTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
				ONLY_ACTIVE_ARCH = YES;
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
"""),
    uid("cfg:proj:Release"): ("Release", PROJ_COMMON + """				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
				ENABLE_NS_ASSERTIONS = NO;
				MTL_ENABLE_DEBUG_INFO = NO;
				SWIFT_COMPILATION_MODE = wholemodule;
				VALIDATE_PRODUCT = YES;
"""),
}

APP_SETTINGS = TARGET_COMMON + f"""				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_KEY_CFBundleDisplayName = Zoon;
				INFOPLIST_KEY_NSHealthShareUsageDescription = "{HEALTH_DESC}";
				INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
				INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;
				INFOPLIST_KEY_NSSupportsLiveActivities = YES;
				INFOPLIST_KEY_UILaunchScreen_Generation = YES;
				INFOPLIST_KEY_UISupportedInterfaceOrientations = "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown";
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				PRODUCT_BUNDLE_IDENTIFIER = com.zoon.sleep;
"""

EXT_SETTINGS = TARGET_COMMON + """				ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
				ASSETCATALOG_COMPILER_WIDGET_BACKGROUND_COLOR_NAME = WidgetBackground;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = ZoonWidget/Info.plist;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
					"@executable_path/../../Frameworks",
				);
				PRODUCT_BUNDLE_IDENTIFIER = com.zoon.sleep.ZoonWidget;
				SKIP_INSTALL = YES;
"""

for key, settings in (("app", APP_SETTINGS), ("ext", EXT_SETTINGS)):
    for cfg in ("Debug", "Release"):
        configs[uid(f"cfg:{key}:{cfg}")] = (cfg, settings)

for cid, (name, settings) in configs.items():
    emit("XCBuildConfiguration",
         f'\t\t{cid} /* {name} */ = {{\n'
         f'\t\t\tisa = XCBuildConfiguration;\n'
         f'\t\t\tbuildSettings = {{\n{settings}\t\t\t}};\n'
         f'\t\t\tname = {name};\n'
         f'\t\t}};')


def cfg_list(lid, label, debug, release):
    emit("XCConfigurationList",
         f'\t\t{lid} /* {label} */ = {{\n'
         f'\t\t\tisa = XCConfigurationList;\n'
         f'\t\t\tbuildConfigurations = (\n'
         f'\t\t\t\t{debug} /* Debug */,\n'
         f'\t\t\t\t{release} /* Release */,\n'
         f'\t\t\t);\n'
         f'\t\t\tdefaultConfigurationIsVisible = 0;\n'
         f'\t\t\tdefaultConfigurationName = Release;\n'
         f'\t\t}};')


cfg_list(PROJ_CFG_LIST, f'Build configuration list for PBXProject "{APP}"',
         uid("cfg:proj:Debug"), uid("cfg:proj:Release"))
cfg_list(APP_CFG_LIST, f'Build configuration list for PBXNativeTarget "{APP}"',
         uid("cfg:app:Debug"), uid("cfg:app:Release"))
cfg_list(EXT_CFG_LIST, f'Build configuration list for PBXNativeTarget "{EXT}"',
         uid("cfg:ext:Debug"), uid("cfg:ext:Release"))

# ---------------------------------------------------------------- assemble
ORDER = ["PBXBuildFile", "PBXContainerItemProxy", "PBXCopyFilesBuildPhase",
         "PBXFileReference", "PBXFrameworksBuildPhase", "PBXGroup",
         "PBXNativeTarget", "PBXProject", "PBXResourcesBuildPhase",
         "PBXSourcesBuildPhase", "PBXTargetDependency",
         "XCBuildConfiguration", "XCConfigurationList"]

out = ["// !$*UTF8*$!", "{", "\tarchiveVersion = 1;", "\tclasses = {",
       "\t};", "\tobjectVersion = 56;", "\tobjects = {", ""]

for section in ORDER:
    bodies = sorted(b for s, b in obj if s == section)
    if not bodies:
        continue
    out.append(f"/* Begin {section} section */")
    out.extend(bodies)
    out.append(f"/* End {section} section */")
    out.append("")

out.append("\t};")
out.append(f"\trootObject = {PROJECT} /* Project object */;")
out.append("}")

path = os.path.join(ROOT, "Zoon.xcodeproj", "project.pbxproj")
with open(path, "w") as fh:
    fh.write("\n".join(out) + "\n")

print(f"wrote {path}")

# ---------------------------------------------------------------- scheme
#
# Generated here rather than hand-maintained: the scheme references the app
# target by ID, so regenerating the project silently invalidates a stale
# scheme, and xcodebuild reports that as "Scheme Zoon is not currently
# configured for the build action" rather than anything about IDs.

SCHEME = f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "2600"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{APP_TARGET}"
               BuildableName = "Zoon.app"
               BlueprintName = "Zoon"
               ReferencedContainer = "container:Zoon.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{APP_TARGET}"
            BuildableName = "Zoon.app"
            BlueprintName = "Zoon"
            ReferencedContainer = "container:Zoon.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{APP_TARGET}"
            BuildableName = "Zoon.app"
            BlueprintName = "Zoon"
            ReferencedContainer = "container:Zoon.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""

scheme_dir = os.path.join(ROOT, "Zoon.xcodeproj", "xcshareddata", "xcschemes")
os.makedirs(scheme_dir, exist_ok=True)
scheme_path = os.path.join(scheme_dir, "Zoon.xcscheme")
with open(scheme_path, "w") as fh:
    fh.write(SCHEME)
print(f"wrote {scheme_path}")
print(f"  shared sources : {len(SHARED)} (in both targets)")
print(f"  app sources    : {len(APP_SRC)}")
print(f"  widget sources : {len(EXT_SRC)}")
print(f"  app build files: {len(app_sources)}")
print(f"  ext build files: {len(ext_sources)}")
print(f"  APP_TARGET={APP_TARGET}  EXT_TARGET={EXT_TARGET}")
