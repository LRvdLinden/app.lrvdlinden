#!/usr/bin/env python3
"""Schrijft LRbeheer.xcodeproj (Xcode 16+-formaat met gesynchroniseerde mappen).

Targets:
  LRbeheer           app (iPhone + iPad, iOS 17+), map LRbeheer/
  BingrKit           framework met de volledige BingrBeheer-app        (Modules/BingrKit)
  TunrKit            framework met de volledige BeheerTunr-app         (Modules/TunrKit)
  PasrKit            framework met de volledige PasrBeheer-app         (Modules/PasrKit)
  P2000Kit           framework met de volledige P2000Beheer-app        (Modules/P2000Kit)
  LRbeheerWidgets    widget-extensie met de widgets van BingrBeheer    (Widgets/BingrWidgets)

Bestanden die je in deze mappen zet, neemt Xcode vanzelf mee; draai dit script alleen opnieuw als instellingen of
targets veranderen (bv. het buildnummer hieronder).

Gebruik (vanuit beheer/): python3 tools/make_project.py
"""
import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
NAME = "LRbeheer"
BUNDLE = "app.lrvdlinden.lrbeheer"
TEAM = "EU3UY476T6"
VERSION = "1.0.0"
BUILD = "22"
IOS = "18.0"  # P2000Beheer vraagt iOS 18 (TabView met Tab, sidebarAdaptable); Bingr, Tunr en Pasr 17

FRAMEWORKS = [
    ("BingrKit", "Modules/BingrKit", "bingrkit"),
    ("TunrKit", "Modules/TunrKit", "tunrkit"),
    ("PasrKit", "Modules/PasrKit", "pasrkit"),
    ("P2000Kit", "Modules/P2000Kit", "p2000kit"),
]


def oid(name):
    return hashlib.md5(("lrbeheer." + name).encode()).hexdigest()[:24].upper()


def q(v):
    s = str(v)
    if s and all(c.isalnum() or c in "._/" for c in s) and not s[0].isdigit():
        return s
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def block(d, ind):
    out = []
    for k in sorted(d):
        v = d[k]
        if isinstance(v, list):
            inner = "".join(f"{ind}\t\t{q(x)},\n" for x in v)
            out.append(f"{ind}\t{q(k)} = (\n{inner}{ind}\t);")
        else:
            out.append(f"{ind}\t{q(k)} = {q(v)};")
    return "\n".join(out)


PROJECT = {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS": "YES",
    "CLANG_ENABLE_MODULES": "YES",
    "CLANG_ENABLE_OBJC_ARC": "YES",
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": BUILD,
    "DEVELOPMENT_TEAM": TEAM,
    "ENABLE_STRICT_OBJC_MSGSEND": "YES",
    "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
    "GCC_C_LANGUAGE_STANDARD": "gnu17",
    "IPHONEOS_DEPLOYMENT_TARGET": IOS,
    "LOCALIZATION_PREFERS_STRING_CATALOGS": "YES",
    "MACOSX_DEPLOYMENT_TARGET": "15.0",
    "MARKETING_VERSION": VERSION,
    "SDKROOT": "iphoneos",
    "SWIFT_VERSION": "5.0",
    "TARGETED_DEVICE_FAMILY": "1,2",
}
DEBUG = {**PROJECT, "DEBUG_INFORMATION_FORMAT": "dwarf", "ENABLE_TESTABILITY": "YES", "GCC_OPTIMIZATION_LEVEL": "0",
         "ONLY_ACTIVE_ARCH": "YES", "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG $(inherited)",
         "SWIFT_OPTIMIZATION_LEVEL": "-Onone"}
RELEASE = {**PROJECT, "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym", "ENABLE_NS_ASSERTIONS": "NO",
           "SWIFT_COMPILATION_MODE": "wholemodule", "VALIDATE_PRODUCT": "YES"}

COMMON_TARGET = {
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": BUILD,
    "DEVELOPMENT_TEAM": TEAM,
    "IPHONEOS_DEPLOYMENT_TARGET": IOS,
    "MARKETING_VERSION": VERSION,
    # Mac: echte Mac-app via Mac Catalyst (zoals BingrBeheer), zelfde bundle-id als iOS (universal purchase).
    # macOS 15 = de Catalyst-versie van iOS 18.
    "SUPPORTS_MACCATALYST": "YES",
    "DERIVE_MACCATALYST_PRODUCT_BUNDLE_IDENTIFIER": "NO",
    "MACOSX_DEPLOYMENT_TARGET": "15.0",
    "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD": "NO",
    "SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD": "NO",
    "SWIFT_EMIT_LOC_STRINGS": "YES",
    "TARGETED_DEVICE_FAMILY": "1,2",
}

APP = {
    **COMMON_TARGET,
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
    "CODE_SIGN_ENTITLEMENTS": "Config/LRbeheer.entitlements",
    "ENABLE_PREVIEWS": "YES",
    "GENERATE_INFOPLIST_FILE": "YES",
    "INFOPLIST_FILE": "Config/Info.plist",
    "INFOPLIST_KEY_CFBundleDisplayName": "LRbeheer",
    "INFOPLIST_KEY_ITSAppUsesNonExemptEncryption": "NO",
    "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.business",
    "INFOPLIST_KEY_NSFaceIDUsageDescription": "LRbeheer gebruikt Face ID om de app en de beheeromgevingen te ontgrendelen.",
    "INFOPLIST_KEY_NSPhotoLibraryUsageDescription": "LRbeheer gebruikt je foto's alleen als je een icoon, banner of afbeelding uploadt.",
    "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES",
    "INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents": "YES",
    "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad": "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight",
    "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone": "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight",
    "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"],
    "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE,
    "PRODUCT_NAME": NAME,
    "SWIFT_EMIT_LOC_STRINGS": "YES",
    "CODE_SIGN_ENTITLEMENTS[sdk=macosx*]": "Config/LRbeheer-macOS.entitlements",
}


def framework_settings(name, suffix):
    return {
        **COMMON_TARGET,
        "APPLICATION_EXTENSION_API_ONLY": "NO",
        "BUILD_LIBRARY_FOR_DISTRIBUTION": "NO",
        "DEFINES_MODULE": "NO",  # alleen Swift: de .swiftmodule is genoeg, geen umbrella header
        "DYLIB_COMPATIBILITY_VERSION": "1",
        "DYLIB_CURRENT_VERSION": "1",
        "DYLIB_INSTALL_NAME_BASE": "@rpath",
        "ENABLE_MODULE_VERIFIER": "NO",
        "GENERATE_INFOPLIST_FILE": "YES",
        "INFOPLIST_KEY_NSHumanReadableCopyright": "",
        "INSTALL_PATH": "$(LOCAL_LIBRARY_DIR)/Frameworks",
        "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks", "@loader_path/Frameworks"],
        "PRODUCT_BUNDLE_IDENTIFIER": f"{BUNDLE}.{suffix}",
        "PRODUCT_NAME": "$(TARGET_NAME:c99extidentifier)",
        "SKIP_INSTALL": "YES",
        "SWIFT_INSTALL_OBJC_HEADER": "NO",
        "VERSIONING_SYSTEM": "apple-generic",
        "VERSION_INFO_PREFIX": "",
    }


WIDGETS = {
    **COMMON_TARGET,
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
    "CODE_SIGN_ENTITLEMENTS": "Config/Widgets.entitlements",
    "CODE_SIGN_ENTITLEMENTS[sdk=macosx*]": "Config/Widgets-macOS.entitlements",
    "GENERATE_INFOPLIST_FILE": "YES",
    "INFOPLIST_FILE": "Config/Widgets-Info.plist",
    "INFOPLIST_KEY_CFBundleDisplayName": "LRbeheer",
    "INFOPLIST_KEY_NSHumanReadableCopyright": "",
    "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks", "@executable_path/../../Frameworks"],
    "PRODUCT_BUNDLE_IDENTIFIER": f"{BUNDLE}.widget",
    "PRODUCT_NAME": "LRbeheerWidgets",
    "SKIP_INSTALL": "YES",
}


def build():
    targets = []  # (key, name, product file, product type, explicit type, sync dir, settings)
    targets.append(("app", NAME, f"{NAME}.app", "com.apple.product-type.application", "wrapper.application", "LRbeheer", APP))
    for name, path, suffix in FRAMEWORKS:
        targets.append((name, name, f"{name}.framework", "com.apple.product-type.framework", "wrapper.framework", path,
                        framework_settings(name, suffix)))
    targets.append(("widgets", "LRbeheerWidgets", "LRbeheerWidgets.appex", "com.apple.product-type.app-extension",
                    "wrapper.app-extension", "Widgets/BingrWidgets", WIDGETS))

    config_files = ["Info.plist", "LRbeheer.entitlements", "LRbeheer-macOS.entitlements", "Widgets-Info.plist",
                    "Widgets.entitlements", "Widgets-macOS.entitlements"]
    I = lambda k: oid(k)

    s = []
    s.append("// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {\n\t};\n\tobjectVersion = 77;\n\tobjects = {\n")

    # build files: frameworks linken + embedden in de app; widget embedden
    s.append("\n/* Begin PBXBuildFile section */\n")
    for name, _, _ in FRAMEWORKS:
        s.append(f"\t\t{I('bf.link.' + name)} /* {name}.framework in Frameworks */ = {{isa = PBXBuildFile; fileRef = {I('prod.' + name)} /* {name}.framework */; }};\n")
        s.append(f"\t\t{I('bf.embed.' + name)} /* {name}.framework in Embed Frameworks */ = {{isa = PBXBuildFile; fileRef = {I('prod.' + name)} /* {name}.framework */; settings = {{ATTRIBUTES = (CodeSignOnCopy, RemoveHeadersOnCopy, ); }}; }};\n")
    s.append(f"\t\t{I('bf.embed.widgets')} /* LRbeheerWidgets.appex in Embed Foundation Extensions */ = {{isa = PBXBuildFile; fileRef = {I('prod.widgets')} /* LRbeheerWidgets.appex */; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};\n")
    s.append("/* End PBXBuildFile section */\n")

    # container item proxies (afhankelijkheden)
    s.append("\n/* Begin PBXContainerItemProxy section */\n")
    for key, name, *_ in targets[1:]:
        s.append(f"\t\t{I('proxy.' + key)} /* PBXContainerItemProxy */ = {{\n\t\t\tisa = PBXContainerItemProxy;\n\t\t\tcontainerPortal = {I('project')} /* Project object */;\n\t\t\tproxyType = 1;\n\t\t\tremoteGlobalIDString = {I('target.' + key)};\n\t\t\tremoteInfo = {name};\n\t\t}};\n")
    s.append("/* End PBXContainerItemProxy section */\n")

    # copy-files fases van de app
    s.append("\n/* Begin PBXCopyFilesBuildPhase section */\n")
    files = "".join(f"\t\t\t\t{I('bf.embed.' + n)} /* {n}.framework in Embed Frameworks */,\n" for n, _, _ in FRAMEWORKS)
    s.append(f"\t\t{I('phase.embedfw')} /* Embed Frameworks */ = {{\n\t\t\tisa = PBXCopyFilesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tdstPath = \"\";\n\t\t\tdstSubfolderSpec = 10;\n\t\t\tfiles = (\n{files}\t\t\t);\n\t\t\tname = \"Embed Frameworks\";\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};\n")
    s.append(f"\t\t{I('phase.embedext')} /* Embed Foundation Extensions */ = {{\n\t\t\tisa = PBXCopyFilesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tdstPath = \"\";\n\t\t\tdstSubfolderSpec = 13;\n\t\t\tfiles = (\n\t\t\t\t{I('bf.embed.widgets')} /* LRbeheerWidgets.appex in Embed Foundation Extensions */,\n\t\t\t);\n\t\t\tname = \"Embed Foundation Extensions\";\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};\n")
    s.append("/* End PBXCopyFilesBuildPhase section */\n")

    # file references
    s.append("\n/* Begin PBXFileReference section */\n")
    for key, name, prod, _, ftype, _, _ in targets:
        pk = "prod.app" if key == "app" else ("prod.widgets" if key == "widgets" else "prod." + key)
        s.append(f"\t\t{I(pk)} /* {prod} */ = {{isa = PBXFileReference; explicitFileType = {ftype}; includeInIndex = 0; path = {q(prod)}; sourceTree = BUILT_PRODUCTS_DIR; }};\n")
    for f in config_files:
        t = "text.plist.entitlements" if f.endswith(".entitlements") else "text.plist.xml"
        s.append(f"\t\t{I('file.' + f)} /* {f} */ = {{isa = PBXFileReference; lastKnownFileType = {t}; path = {q(f)}; sourceTree = \"<group>\"; }};\n")
    for f in ["README.md"]:
        s.append(f"\t\t{I('file.' + f)} /* {f} */ = {{isa = PBXFileReference; lastKnownFileType = net.daringfireball.markdown; path = {q(f)}; sourceTree = \"<group>\"; }};\n")
    s.append("/* End PBXFileReference section */\n")

    # gesynchroniseerde mappen
    s.append("\n/* Begin PBXFileSystemSynchronizedRootGroup section */\n")
    for key, name, _, _, _, path, _ in targets:
        s.append(f"\t\t{I('sync.' + key)} /* {path} */ = {{\n\t\t\tisa = PBXFileSystemSynchronizedRootGroup;\n\t\t\tpath = {q(path)};\n\t\t\tsourceTree = \"<group>\";\n\t\t}};\n")
    s.append("/* End PBXFileSystemSynchronizedRootGroup section */\n")

    # frameworks-fases
    s.append("\n/* Begin PBXFrameworksBuildPhase section */\n")
    for key, *_ in targets:
        files = ""
        if key == "app":
            files = "".join(f"\t\t\t\t{I('bf.link.' + n)} /* {n}.framework in Frameworks */,\n" for n, _, _ in FRAMEWORKS)
        s.append(f"\t\t{I('phase.fw.' + key)} /* Frameworks */ = {{\n\t\t\tisa = PBXFrameworksBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n{files}\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};\n")
    s.append("/* End PBXFrameworksBuildPhase section */\n")

    # groepen
    s.append("\n/* Begin PBXGroup section */\n")
    modules_children = "".join(f"\t\t\t\t{I('sync.' + n)} /* {p} */,\n" for n, p, _ in FRAMEWORKS)
    s.append(f"\t\t{I('group.main')} = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t\t{I('file.README.md')} /* README.md */,\n\t\t\t\t{I('sync.app')} /* LRbeheer */,\n\t\t\t\t{I('group.modules')} /* Modules */,\n\t\t\t\t{I('sync.widgets')} /* Widgets/BingrWidgets */,\n\t\t\t\t{I('group.config')} /* Config */,\n\t\t\t\t{I('group.products')} /* Products */,\n\t\t\t);\n\t\t\tsourceTree = \"<group>\";\n\t\t}};\n")
    s.append(f"\t\t{I('group.modules')} /* Modules */ = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n{modules_children}\t\t\t);\n\t\t\tname = Modules;\n\t\t\tsourceTree = \"<group>\";\n\t\t}};\n")
    cfg_children = "".join(f"\t\t\t\t{I('file.' + f)} /* {f} */,\n" for f in config_files)
    s.append(f"\t\t{I('group.config')} /* Config */ = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n{cfg_children}\t\t\t);\n\t\t\tpath = Config;\n\t\t\tsourceTree = \"<group>\";\n\t\t}};\n")
    prods = ""
    for key, name, prod, *_ in targets:
        pk = "prod.app" if key == "app" else ("prod.widgets" if key == "widgets" else "prod." + key)
        prods += f"\t\t\t\t{I(pk)} /* {prod} */,\n"
    s.append(f"\t\t{I('group.products')} /* Products */ = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n{prods}\t\t\t);\n\t\t\tname = Products;\n\t\t\tsourceTree = \"<group>\";\n\t\t}};\n")
    s.append("/* End PBXGroup section */\n")

    # targets
    s.append("\n/* Begin PBXNativeTarget section */\n")
    for key, name, prod, ptype, _, path, _ in targets:
        pk = "prod.app" if key == "app" else ("prod.widgets" if key == "widgets" else "prod." + key)
        phases = [f"{I('phase.src.' + key)} /* Sources */", f"{I('phase.fw.' + key)} /* Frameworks */", f"{I('phase.res.' + key)} /* Resources */"]
        deps = ""
        if key == "app":
            phases += [f"{I('phase.embedfw')} /* Embed Frameworks */", f"{I('phase.embedext')} /* Embed Foundation Extensions */"]
            deps = "".join(f"\t\t\t\t{I('dep.' + k)} /* PBXTargetDependency */,\n" for k, *_ in targets[1:])
        ph = "".join(f"\t\t\t\t{p},\n" for p in phases)
        s.append(f"\t\t{I('target.' + key)} /* {name} */ = {{\n\t\t\tisa = PBXNativeTarget;\n\t\t\tbuildConfigurationList = {I('cl.' + key)} /* Build configuration list for PBXNativeTarget \"{name}\" */;\n\t\t\tbuildPhases = (\n{ph}\t\t\t);\n\t\t\tbuildRules = (\n\t\t\t);\n\t\t\tdependencies = (\n{deps}\t\t\t);\n\t\t\tfileSystemSynchronizedGroups = (\n\t\t\t\t{I('sync.' + key)} /* {path} */,\n\t\t\t);\n\t\t\tname = {q(name)};\n\t\t\tpackageProductDependencies = (\n\t\t\t);\n\t\t\tproductName = {q(name)};\n\t\t\tproductReference = {I(pk)} /* {prod} */;\n\t\t\tproductType = {q(ptype)};\n\t\t}};\n")
    s.append("/* End PBXNativeTarget section */\n")

    # project
    tattrs = "".join(f"\t\t\t\t\t{I('target.' + k)} = {{\n\t\t\t\t\t\tCreatedOnToolsVersion = 26.0;\n\t\t\t\t\t}};\n" for k, *_ in targets)
    tlist = "".join(f"\t\t\t\t{I('target.' + k)} /* {n} */,\n" for k, n, *_ in targets)
    s.append(f"\n/* Begin PBXProject section */\n\t\t{I('project')} /* Project object */ = {{\n\t\t\tisa = PBXProject;\n\t\t\tattributes = {{\n\t\t\t\tBuildIndependentTargetsInParallel = 1;\n\t\t\t\tLastSwiftUpdateCheck = 2600;\n\t\t\t\tLastUpgradeCheck = 2600;\n\t\t\t\tTargetAttributes = {{\n{tattrs}\t\t\t\t}};\n\t\t\t}};\n\t\t\tbuildConfigurationList = {I('cl.project')} /* Build configuration list for PBXProject \"{NAME}\" */;\n\t\t\tdevelopmentRegion = nl;\n\t\t\thasScannedForEncodings = 0;\n\t\t\tknownRegions = (\n\t\t\t\tnl,\n\t\t\t\ten,\n\t\t\t\tBase,\n\t\t\t);\n\t\t\tmainGroup = {I('group.main')};\n\t\t\tminimizedProjectReferenceProxies = 1;\n\t\t\tpreferredProjectObjectVersion = 77;\n\t\t\tproductRefGroup = {I('group.products')} /* Products */;\n\t\t\tprojectDirPath = \"\";\n\t\t\tprojectRoot = \"\";\n\t\t\ttargets = (\n{tlist}\t\t\t);\n\t\t}};\n/* End PBXProject section */\n")

    # resources en sources
    s.append("\n/* Begin PBXResourcesBuildPhase section */\n")
    for key, *_ in targets:
        s.append(f"\t\t{I('phase.res.' + key)} /* Resources */ = {{\n\t\t\tisa = PBXResourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};\n")
    s.append("/* End PBXResourcesBuildPhase section */\n")
    s.append("\n/* Begin PBXSourcesBuildPhase section */\n")
    for key, *_ in targets:
        s.append(f"\t\t{I('phase.src.' + key)} /* Sources */ = {{\n\t\t\tisa = PBXSourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};\n")
    s.append("/* End PBXSourcesBuildPhase section */\n")

    # afhankelijkheden
    s.append("\n/* Begin PBXTargetDependency section */\n")
    for key, name, *_ in targets[1:]:
        s.append(f"\t\t{I('dep.' + key)} /* PBXTargetDependency */ = {{\n\t\t\tisa = PBXTargetDependency;\n\t\t\ttarget = {I('target.' + key)} /* {name} */;\n\t\t\ttargetProxy = {I('proxy.' + key)} /* PBXContainerItemProxy */;\n\t\t}};\n")
    s.append("/* End PBXTargetDependency section */\n")

    # build-configuraties
    s.append("\n/* Begin XCBuildConfiguration section */\n")

    def cfg(key, name, d):
        return f"\t\t{I(key)} /* {name} */ = {{\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = {{\n{block(d, chr(9) * 3)}\n\t\t\t}};\n\t\t\tname = {name};\n\t\t}};\n"
    s.append(cfg("cfg.project.debug", "Debug", DEBUG))
    s.append(cfg("cfg.project.release", "Release", RELEASE))
    for key, _, _, _, _, _, st in targets:
        s.append(cfg(f"cfg.{key}.debug", "Debug", st))
        s.append(cfg(f"cfg.{key}.release", "Release", st))
    s.append("/* End XCBuildConfiguration section */\n")

    s.append("\n/* Begin XCConfigurationList section */\n")

    def cl(key, d, r, comment):
        return (f"\t\t{I(key)} /* {comment} */ = {{\n\t\t\tisa = XCConfigurationList;\n\t\t\tbuildConfigurations = (\n"
                f"\t\t\t\t{I(d)} /* Debug */,\n\t\t\t\t{I(r)} /* Release */,\n\t\t\t);\n"
                f"\t\t\tdefaultConfigurationIsVisible = 0;\n\t\t\tdefaultConfigurationName = Release;\n\t\t}};\n")
    s.append(cl("cl.project", "cfg.project.debug", "cfg.project.release", f'Build configuration list for PBXProject "{NAME}"'))
    for key, name, *_ in targets:
        s.append(cl("cl." + key, f"cfg.{key}.debug", f"cfg.{key}.release", f'Build configuration list for PBXNativeTarget "{name}"'))
    s.append("/* End XCConfigurationList section */\n")

    s.append(f"\t}};\n\trootObject = {I('project')} /* Project object */;\n}}\n")
    return "".join(s)


SCHEME = """<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "2600" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{target}" BuildableName = "LRbeheer.app" BlueprintName = "LRbeheer" ReferencedContainer = "container:LRbeheer.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES">
   </TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{target}" BuildableName = "LRbeheer.app" BlueprintName = "LRbeheer" ReferencedContainer = "container:LRbeheer.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""

if __name__ == "__main__":
    proj = ROOT / f"{NAME}.xcodeproj"
    (proj / "xcshareddata" / "xcschemes").mkdir(parents=True, exist_ok=True)
    (proj / "project.pbxproj").write_text(build())
    (proj / "xcshareddata" / "xcschemes" / f"{NAME}.xcscheme").write_text(SCHEME.replace("{target}", oid("target.app")))
    ws = proj / "project.xcworkspace"
    ws.mkdir(exist_ok=True)
    (ws / "contents.xcworkspacedata").write_text('<?xml version="1.0" encoding="UTF-8"?>\n<Workspace\n   version = "1.0">\n   <FileRef\n      location = "self:">\n   </FileRef>\n</Workspace>\n')
    print("Geschreven:", proj)
