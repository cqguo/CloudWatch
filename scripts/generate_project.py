#!/usr/bin/env python3
"""Generate a dependency-free watchOS Xcode project."""
import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
def uid(value):
    return hashlib.sha1(value.encode()).hexdigest()[:24].upper()

objects = []
def add(name, value):
    objects.append(f"{uid(name)} = {{ {value} }};")
    return uid(name)

source_builds, resource_builds, refs = [], [], []
for path in sorted((ROOT / "CloudWatch").rglob("*")):
    if any(part.endswith(".xcassets") for part in path.parts):
        continue
    if path.suffix not in (".swift", ".wav", ".c", ".h", ".js", ".html", ".json"):
        continue
    relative = path.relative_to(ROOT).as_posix()
    filetype = {".swift":"sourcecode.swift", ".c":"sourcecode.c.c", ".h":"sourcecode.c.h", ".wav":"audio.wav", ".js":"sourcecode.javascript", ".html":"text.html", ".json":"text.json"}[path.suffix]
    ref = add(relative, f'isa = PBXFileReference; lastKnownFileType = {filetype}; path = "{relative}"; sourceTree = SOURCE_ROOT;')
    refs.append(ref)
    if path.suffix == ".h":
        continue
    build = add(relative + ":build", f"isa = PBXBuildFile; fileRef = {ref};")
    (source_builds if path.suffix in (".swift", ".c") else resource_builds).append(build)

asset = add("assets", 'isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = CloudWatch/Assets.xcassets; sourceTree = SOURCE_ROOT;')
refs.append(asset)
resource_builds.append(add("assets:build", f"isa = PBXBuildFile; fileRef = {asset};"))

def items(values):
    return "(" + ",".join(values) + ("," if values else "") + ")"

product = add("product", 'isa = PBXFileReference; explicitFileType = wrapper.application; path = CloudWatch.app; sourceTree = BUILT_PRODUCTS_DIR;')
products = add("products", f'isa = PBXGroup; name = Products; children = ({product},); sourceTree = "<group>";')
group = add("group", f'isa = PBXGroup; children = {items(refs + [products])}; sourceTree = "<group>";')
sources = add("sources", f"isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {items(source_builds)}; runOnlyForDeploymentPostprocessing = 0;")
resources = add("resources", f"isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = {items(resource_builds)}; runOnlyForDeploymentPostprocessing = 0;")
frameworks = add("frameworks", "isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;")
project_configs, target_configs = [], []
for config in ("Debug", "Release"):
    opt = 'SWIFT_OPTIMIZATION_LEVEL = "-Onone"; DEBUG_INFORMATION_FORMAT = dwarf; SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;' if config == "Debug" else 'SWIFT_COMPILATION_MODE = wholemodule; SWIFT_OPTIMIZATION_LEVEL = "-O"; DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";'
    project_configs.append(add("project:" + config, f'isa = XCBuildConfiguration; name = {config}; buildSettings = {{ CLANG_ENABLE_MODULES = YES; SWIFT_VERSION = 5.0; {opt} }};'))
    target_configs.append(add("target:" + config, f'''isa = XCBuildConfiguration; name = {config}; buildSettings = {{
        PRODUCT_NAME = CloudWatch;
        PRODUCT_BUNDLE_IDENTIFIER = com.guochengqian.cloudwatch;
        SDKROOT = watchos;
        SUPPORTED_PLATFORMS = "watchos watchsimulator";
        WATCHOS_DEPLOYMENT_TARGET = 10.0;
        TARGETED_DEVICE_FAMILY = 4;
        INFOPLIST_FILE = CloudWatch/Info.plist;
        GENERATE_INFOPLIST_FILE = NO;
        CODE_SIGN_STYLE = Automatic;
        DEVELOPMENT_TEAM = "";
        SWIFT_EMIT_LOC_STRINGS = YES;
        ENABLE_PREVIEWS = YES;
        ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
        LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks";
    }};'''))
pc = add("project-configs", f"isa = XCConfigurationList; buildConfigurations = {items(project_configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;")
tc = add("target-configs", f"isa = XCConfigurationList; buildConfigurations = {items(target_configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;")
target = add("target", f'isa = PBXNativeTarget; buildConfigurationList = {tc}; buildPhases = ({sources},{frameworks},{resources},); buildRules = (); dependencies = (); name = CloudWatch; productName = CloudWatch; productReference = {product}; productType = "com.apple.product-type.application";')
project = add("project", f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 2650; TargetAttributes = {{ {target} = {{ CreatedOnToolsVersion = 26.5; }}; }}; }}; buildConfigurationList = {pc}; compatibilityVersion = "Xcode 14.0"; developmentRegion = "zh-Hans"; hasScannedForEncodings = 0; knownRegions = ("zh-Hans", en, Base,); mainGroup = {group}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = ({target},);')
project_dir = ROOT / "CloudWatch.xcodeproj"
project_dir.mkdir(exist_ok=True)
(project_dir / "project.pbxproj").write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n' + '\n'.join(objects) + f'\n}}; rootObject = {project}; }}\n')
scheme_dir = project_dir / "xcshareddata/xcschemes"
scheme_dir.mkdir(parents=True, exist_ok=True)
ref = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="CloudWatch.app" BlueprintName="CloudWatch" ReferencedContainer="container:CloudWatch.xcodeproj"/>'
(scheme_dir / "CloudWatch.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2650" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref}</BuildActionEntry></BuildActionEntries></BuildAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/>
<ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
print("Generated CloudWatch.xcodeproj.")
