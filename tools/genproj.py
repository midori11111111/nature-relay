#!/usr/bin/env python3
"""Generate NatureRelay.xcodeproj/project.pbxproj from sources (single app target).
Usage: TEAM_ID=ABCDE12345 python3 tools/genproj.py
"""
import os

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
group = "NatureRelay"
srcdir = os.path.join(root, group)
TEAM_ID = os.environ.get("TEAM_ID", "").strip()
BUILD_NUMBER = os.environ.get("BUILD_NUMBER", "5").strip() or "5"
MARKETING_VERSION = os.environ.get("MARKETING_VERSION", "1.0").strip() or "1.0"

swift_files = sorted(f for f in os.listdir(srcdir) if f.endswith(".swift"))
resources = []
for resource, resource_type in [("SpeciesCharacters", "folder"), ("SpeciesCharactersA", "folder"), ("NatureRelayConfig.json", "text.json")]:
    if os.path.exists(os.path.join(srcdir, resource)):
        resources.append((resource, resource_type))
if os.path.isfile(os.path.join(root, "Resources", "character-asset-credits.json")):
    resources.append(("../Resources/character-asset-credits.json", "text.json"))
if os.path.isdir(os.path.join(root, "Resources", "CaliforniaCatalog")):
    resources.append(("../Resources/CaliforniaCatalog", "folder"))
if os.path.isdir(os.path.join(srcdir, "MobileNetV2FP16.mlmodelc")):
    resources.append(("MobileNetV2FP16.mlmodelc", "folder"))
if os.path.isfile(os.path.join(srcdir, "DemoFlower.jpg")):
    resources.append(("DemoFlower.jpg", "image.jpeg"))
if os.path.isfile(os.path.join(srcdir, "DemoAIFlower.webp")):
    resources.append(("DemoAIFlower.webp", "image.webp"))
if os.path.isfile(os.path.join(srcdir, "CompanionPoppy-v2.png")):
    resources.append(("CompanionPoppy-v2.png", "image.png"))
if os.path.isfile(os.path.join(srcdir, "CompanionFlowerStyle.png")):
    resources.append(("CompanionFlowerStyle.png", "image.png"))
if os.path.isfile(os.path.join(srcdir, "LiveScanSample.jpg")):
    resources.append(("LiveScanSample.jpg", "image.jpeg"))
if os.path.isdir(os.path.join(srcdir, "Assets.xcassets")):
    resources.append(("Assets.xcassets", "folder.assetcatalog"))
if os.path.isfile(os.path.join(srcdir, "PrivacyInfo.xcprivacy")):
    resources.append(("PrivacyInfo.xcprivacy", "text.plist.xml"))

_c = [0]
def uid():
    _c[0] += 1
    return "AB01" + format(_c[0], "020X")

proj_id, main_group, prod_group, src_group = uid(), uid(), uid(), uid()
target_id, product_ref = uid(), uid()
sources_phase, resources_phase, frameworks_phase = uid(), uid(), uid()
bcl_proj, bcl_tgt = uid(), uid()
debug_proj, release_proj, debug_tgt, release_tgt = uid(), uid(), uid(), uid()

swift_entries = [(uid(), uid(), f) for f in swift_files]
res_entries = [(uid(), uid(), name, ftype) for name, ftype in resources]

def pbx():
    L = ["// !$*UTF8*$!", "{", "\tarchiveVersion = 1;", "\tclasses = {};",
         "\tobjectVersion = 56;", "\tobjects = {"]
    L.append("/* Begin PBXBuildFile section */")
    for ref, bf, name in swift_entries:
        L.append(f"\t\t{bf} = {{isa = PBXBuildFile; fileRef = {ref} /* {name} */; }};")
    for ref, bf, name, _ in res_entries:
        L.append(f"\t\t{bf} = {{isa = PBXBuildFile; fileRef = {ref} /* {name} */; }};")
    L.append("/* End PBXBuildFile section */")

    L.append("/* Begin PBXFileReference section */")
    L.append(f'\t\t{product_ref} /* NatureRelay.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = NatureRelay.app; sourceTree = BUILT_PRODUCTS_DIR; }};')
    for ref, bf, name in swift_entries:
        L.append(f'\t\t{ref} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{name}"; sourceTree = "<group>"; }};')
    for ref, bf, name, ftype in res_entries:
        L.append(f'\t\t{ref} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = {ftype}; path = "{name}"; sourceTree = "<group>"; }};')
    L.append("/* End PBXFileReference section */")

    L.append("/* Begin PBXFrameworksBuildPhase section */")
    L.append(f"\t\t{frameworks_phase} = {{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; }};")
    L.append("/* End PBXFrameworksBuildPhase section */")

    L.append("/* Begin PBXGroup section */")
    L.append(f"\t\t{main_group} = {{isa = PBXGroup; children = (")
    L.append(f"\t\t\t{src_group} /* NatureRelay */,")
    L.append(f"\t\t\t{prod_group} /* Products */,")
    L.append("\t\t); sourceTree = \"<group>\"; };")
    L.append(f"\t\t{prod_group} /* Products */ = {{isa = PBXGroup; children = (")
    L.append(f"\t\t\t{product_ref} /* NatureRelay.app */,")
    L.append("\t\t); name = Products; sourceTree = \"<group>\"; };")
    L.append(f"\t\t{src_group} /* NatureRelay */ = {{isa = PBXGroup; children = (")
    for ref, bf, name in swift_entries:
        L.append(f"\t\t\t{ref} /* {name} */,")
    for ref, bf, name, _ in res_entries:
        L.append(f"\t\t\t{ref} /* {name} */,")
    L.append("\t\t); path = NatureRelay; sourceTree = \"<group>\"; };")
    L.append("/* End PBXGroup section */")

    L.append("/* Begin PBXNativeTarget section */")
    L.append(f"\t\t{target_id} /* NatureRelay */ = {{isa = PBXNativeTarget; buildConfigurationList = {bcl_tgt}; buildPhases = (")
    L.append(f"\t\t\t{sources_phase},\n\t\t\t{frameworks_phase},\n\t\t\t{resources_phase},")
    L.append(f"\t\t); buildRules = (); dependencies = (); name = NatureRelay; productName = NatureRelay; productReference = {product_ref} /* NatureRelay.app */; productType = \"com.apple.product-type.application\"; }};")
    L.append("/* End PBXNativeTarget section */")

    L.append("/* Begin PBXProject section */")
    L.append(f"\t\t{proj_id} /* Project object */ = {{isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = 1; LastSwiftUpdateCheck = 2660; LastUpgradeCheck = 2660; TargetAttributes = {{ {target_id} = {{ CreatedOnToolsVersion = 26.6; }}; }}; }}; buildConfigurationList = {bcl_proj}; compatibilityVersion = \"Xcode 14.0\"; developmentRegion = ja; hasScannedForEncodings = 0; knownRegions = (en, ja, Base); mainGroup = {main_group}; productRefGroup = {prod_group} /* Products */; projectDirPath = \"\"; projectRoot = \"\"; targets = ( {target_id} /* NatureRelay */, ); }};")
    L.append("/* End PBXProject section */")

    L.append("/* Begin PBXResourcesBuildPhase section */")
    L.append(f"\t\t{resources_phase} = {{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (")
    for ref, bf, name, _ in res_entries:
        L.append(f"\t\t\t{bf} /* {name} in Resources */,")
    L.append("\t\t); runOnlyForDeploymentPostprocessing = 0; };")
    L.append("/* End PBXResourcesBuildPhase section */")

    L.append("/* Begin PBXSourcesBuildPhase section */")
    L.append(f"\t\t{sources_phase} = {{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (")
    for ref, bf, name in swift_entries:
        L.append(f"\t\t\t{bf} /* {name} in Sources */,")
    L.append("\t\t); runOnlyForDeploymentPostprocessing = 0; };")
    L.append("/* End PBXSourcesBuildPhase section */")

    common = ('ALWAYS_SEARCH_USER_PATHS = NO; CLANG_ANALYZER_NONNULL = YES; '
        'CLANG_ENABLE_MODULES = YES; CLANG_ENABLE_OBJC_ARC = YES; '
        'ENABLE_STRICT_OBJC_MSGSEND = YES; GCC_C_LANGUAGE_STANDARD = gnu17; '
        'CLANG_CXX_LANGUAGE_STANDARD = "gnu++20"; ENABLE_USER_SCRIPT_SANDBOXING = YES; '
        'SDKROOT = iphoneos; IPHONEOS_DEPLOYMENT_TARGET = 17.0; SWIFT_EMIT_LOC_STRINGS = YES; ')
    L.append("/* Begin XCBuildConfiguration section */")
    L.append(f"\t\t{debug_proj} /* Debug */ = {{isa = XCBuildConfiguration; buildSettings = {{ {common} GCC_OPTIMIZATION_LEVEL = 0; ONLY_ACTIVE_ARCH = YES; SWIFT_OPTIMIZATION_LEVEL = \"-Onone\"; SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG; ENABLE_TESTABILITY = YES; DEBUG_INFORMATION_FORMAT = dwarf; COPY_PHASE_STRIP = NO; }}; name = Debug; }};")
    L.append(f"\t\t{release_proj} /* Release */ = {{isa = XCBuildConfiguration; buildSettings = {{ {common} SWIFT_OPTIMIZATION_LEVEL = \"-O\"; SWIFT_COMPILATION_MODE = wholemodule; DEBUG_INFORMATION_FORMAT = \"dwarf-with-dsym\"; ENABLE_NS_ASSERTIONS = NO; COPY_PHASE_STRIP = NO; VALIDATE_PRODUCT = YES; }}; name = Release; }};")
    if TEAM_ID:
        sign = (f'CODE_SIGN_STYLE = Automatic; DEVELOPMENT_TEAM = {TEAM_ID}; CODE_SIGN_IDENTITY = "Apple Development"; ')
    else:
        sign = 'CODE_SIGN_STYLE = Automatic; CODE_SIGNING_REQUIRED = NO; CODE_SIGNING_ALLOWED = NO; '
    tgt = ('ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon; '
        'ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor; '
        + sign +
        f'CURRENT_PROJECT_VERSION = {BUILD_NUMBER}; MARKETING_VERSION = {MARKETING_VERSION}; '
        'GENERATE_INFOPLIST_FILE = YES; '
        'INFOPLIST_KEY_CFBundleDisplayName = "Nature Relay"; '
        'INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES; '
        'INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES; '
        'INFOPLIST_KEY_UILaunchScreen_Generation = YES; '
        'INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = "UIInterfaceOrientationPortrait"; '
        'LD_RUNPATH_SEARCH_PATHS = "@executable_path/Frameworks"; '
        'PRODUCT_BUNDLE_IDENTIFIER = com.tomoki.naturerelay; '
        'PRODUCT_NAME = "$(TARGET_NAME)"; SWIFT_VERSION = 5.0; '
        'TARGETED_DEVICE_FAMILY = "1"; ENABLE_PREVIEWS = YES; '
        'INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO; '
        'INFOPLIST_KEY_NSLocationWhenInUseUsageDescription = "Find nature near you and place a discovery on your map."; '
        'INFOPLIST_KEY_NSCameraUsageDescription = "Photograph a plant or animal to create a nature discovery."; '
        'INFOPLIST_KEY_NSPhotoLibraryUsageDescription = "Read the location and date of the photo you select for your nature journal. You can allow only selected photos."; '
        'INFOPLIST_KEY_PHPhotoLibraryPreventAutomaticLimitedAccessAlert = YES; ')
    L.append(f"\t\t{debug_tgt} /* Debug */ = {{isa = XCBuildConfiguration; buildSettings = {{ {tgt} }}; name = Debug; }};")
    L.append(f"\t\t{release_tgt} /* Release */ = {{isa = XCBuildConfiguration; buildSettings = {{ {tgt} }}; name = Release; }};")
    L.append("/* End XCBuildConfiguration section */")

    L.append("/* Begin XCConfigurationList section */")
    L.append(f"\t\t{bcl_proj} = {{isa = XCConfigurationList; buildConfigurations = ( {debug_proj} /* Debug */, {release_proj} /* Release */, ); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }};")
    L.append(f"\t\t{bcl_tgt} = {{isa = XCConfigurationList; buildConfigurations = ( {debug_tgt} /* Debug */, {release_tgt} /* Release */, ); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }};")
    L.append("/* End XCConfigurationList section */")

    L += ["\t};", f"\trootObject = {proj_id} /* Project object */;", "}"]
    return "\n".join(L)

def scheme_xml():
    return f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2660" version="1.7">
   <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">
            <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target_id}" BuildableName="NatureRelay.app" BlueprintName="NatureRelay" ReferencedContainer="container:NatureRelay.xcodeproj"></BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES">
      <BuildableProductRunnable runnableDebuggingMode="0">
         <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target_id}" BuildableName="NatureRelay.app" BlueprintName="NatureRelay" ReferencedContainer="container:NatureRelay.xcodeproj"></BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES">
      <BuildableProductRunnable runnableDebuggingMode="0">
         <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target_id}" BuildableName="NatureRelay.app" BlueprintName="NatureRelay" ReferencedContainer="container:NatureRelay.xcodeproj"></BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration="Debug"></AnalyzeAction>
   <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"></ArchiveAction>
</Scheme>
'''

projdir = os.path.join(root, "NatureRelay.xcodeproj")
os.makedirs(projdir, exist_ok=True)
open(os.path.join(projdir, "project.pbxproj"), "w").write(pbx())
schemedir = os.path.join(projdir, "xcshareddata", "xcschemes")
os.makedirs(schemedir, exist_ok=True)
open(os.path.join(schemedir, "NatureRelay.xcscheme"), "w").write(scheme_xml())
print(f"wrote pbxproj | swift: {len(swift_entries)} | resources: {[r[2] for r in res_entries]} | TEAM_ID: {TEAM_ID or '(none)'} | version {MARKETING_VERSION} ({BUILD_NUMBER})")
