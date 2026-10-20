#!/usr/bin/env python3
"""Generate a deterministic, ordinary Xcode application project from Sources/."""
import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
def ident(name):
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()

def main():
    sources = sorted((ROOT / 'Sources').glob('*.swift'))
    objects = []
    def obj(name, body):
        objects.append(f'\t\t{ident(name)} = {{ {body} }};')
        return ident(name)
    source_refs, build_refs = [], []
    for source in sources:
        ref = obj('ref:' + source.name, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "Sources/{source.name}"; sourceTree = "<group>";')
        source_refs.append(ref)
        build_refs.append(obj('build:' + source.name, f'isa = PBXBuildFile; fileRef = {ref};'))
    res = obj('resources', 'isa = PBXFileReference; lastKnownFileType = folder; path = Resources; sourceTree = "<group>";')
    res_build = obj('resources:build', f'isa = PBXBuildFile; fileRef = {res};')
    icon = obj('icon', 'isa = PBXFileReference; lastKnownFileType = image.icns; path = Resources/MacPaint.icns; sourceTree = "<group>";')
    icon_build = obj('icon:build', f'isa = PBXBuildFile; fileRef = {icon};')
    app = obj('product', 'isa = PBXFileReference; explicitFileType = wrapper.application; path = MacPaintNative.app; sourceTree = BUILT_PRODUCTS_DIR;')
    products = obj('products', f'isa = PBXGroup; children = ({app},); name = Products; sourceTree = "<group>";')
    group = obj('rootgroup', f'isa = PBXGroup; children = ({",".join(source_refs + [res, products])},); sourceTree = "<group>";')
    compile_phase = obj('sources-phase', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(build_refs)},); runOnlyForDeploymentPostprocessing = 0;')
    resources_phase = obj('resources-phase', f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({res_build},{icon_build},); runOnlyForDeploymentPostprocessing = 0;')
    framework_phase = obj('frameworks-phase', 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
    helper_phase = obj('mcp-helper-phase', '''isa = PBXShellScriptBuildPhase; buildActionMask = 2147483647;
        files = (); inputPaths = (); outputPaths = ("$(TARGET_BUILD_DIR)/$(EXECUTABLE_FOLDER_PATH)/MacPaintMCP",);
        runOnlyForDeploymentPostprocessing = 0; shellPath = /bin/sh;
        shellScript = "ln -sf MacPaintNative \\"$TARGET_BUILD_DIR/$EXECUTABLE_FOLDER_PATH/MacPaintMCP\\"\\n";
        name = "Bundle MCP entry point";''')
    project_configs, target_configs = [], []
    for name in ['Debug', 'Release']:
        project_configs.append(obj('project-config:' + name, f'isa = XCBuildConfiguration; name = {name}; buildSettings = {{ SDKROOT = macosx; MACOSX_DEPLOYMENT_TARGET = 15.0; CLANG_ENABLE_MODULES = YES; }};'))
        optimization = '-Onone' if name == 'Debug' else '-O'
        target_configs.append(obj('target-config:' + name, f'''isa = XCBuildConfiguration; name = {name}; buildSettings = {{
            ARCHS = arm64; PRODUCT_NAME = MacPaintNative; PRODUCT_BUNDLE_IDENTIFIER = org.macpaint.native;
            SWIFT_VERSION = 5.0; SWIFT_OPTIMIZATION_LEVEL = "{optimization}";
            INFOPLIST_FILE = Info.plist; CODE_SIGN_STYLE = Automatic;
            ENABLE_HARDENED_RUNTIME = YES; COMBINE_HIDPI_IMAGES = YES;
            LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/../Frameworks";
            }};'''))
    project_list = obj('project-config-list', f'isa = XCConfigurationList; buildConfigurations = ({",".join(project_configs)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
    target_list = obj('target-config-list', f'isa = XCConfigurationList; buildConfigurations = ({",".join(target_configs)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
    target = obj('target', f'''isa = PBXNativeTarget; buildConfigurationList = {target_list};
        buildPhases = ({compile_phase}, {framework_phase}, {resources_phase}, {helper_phase},); buildRules = (); dependencies = ();
        name = MacPaintNative; productName = MacPaintNative; productReference = {app}; productType = "com.apple.product-type.application";''')
    project = obj('project', f'''isa = PBXProject; attributes = {{ LastUpgradeCheck = 2700; }};
        buildConfigurationList = {project_list}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en;
        knownRegions = (en, Base); mainGroup = {group}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = ({target},);''')
    folder = ROOT / 'MacPaintNative.xcodeproj'
    folder.mkdir(exist_ok=True)
    (folder / 'project.pbxproj').write_text('// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {};\n\tobjectVersion = 56;\n\tobjects = {\n' + '\n'.join(objects) + f'\n\t}};\n\trootObject = {project};\n}}\n')
    print(f'Generated Xcode project with {len(sources)} Swift sources')

if __name__ == '__main__':
    main()
