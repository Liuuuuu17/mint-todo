#!/usr/bin/env python3
"""Generate a small native Xcode project with proper widget metadata extraction."""
from pathlib import Path
import hashlib
import os
import plistlib

root = Path(__file__).resolve().parent
project = root / 'MintWidgetsTrial.xcodeproj'
project.mkdir(exist_ok=True)
objects = {}

def identifier(name):
    return hashlib.sha256(name.encode()).hexdigest()[:24].upper()

def add(object_name, isa, **values):
    key = identifier(object_name)
    objects[key] = dict(isa=isa, **values)
    return key

def build_file(name, file_ref, **values):
    return add('build-' + name, 'PBXBuildFile', fileRef=file_ref, **values)

app_sources = [
    'MintTodo.swift', 'FontSettings.swift', 'AppearanceSettings.swift', 'RemindersSync.swift',
    'GoalModels.swift', 'OrbPlanSchema.swift', 'GoalStore.swift', 'MarkdownNotes.swift',
    'PlanPrompt.swift', 'AIClient.swift', 'AISettingsView.swift', 'GoalEditorView.swift',
    'GoalViews.swift', 'LongTermTasksView.swift', 'PlanRevision.swift', 'WindowResizeEdges.swift', 'AppUpdater.swift',
    'DesktopWidgets/WidgetTrialCoordinator.swift', 'NaturalTaskTime.swift',
]
shared_sources = ['DesktopWidgets/WidgetData.swift', 'DesktopWidgets/MintWidgetViews.swift', 'DesktopWidgets/WidgetActionIntent.swift']
widget_sources = shared_sources + ['DesktopWidgets/WidgetExtension.swift']
references = {}
for path in dict.fromkeys(app_sources + widget_sources + ['DesktopWidgets/TrialIcon.icns']):
    references[path] = add('file-' + path, 'PBXFileReference', path=path, sourceTree='<group>',
                           lastKnownFileType='image.icns' if path.endswith('.icns') else 'sourcecode.swift')

app_product = add('product-app', 'PBXFileReference', path='Mint Todo Widgets Trial.app',
                  explicitFileType='wrapper.application', sourceTree='BUILT_PRODUCTS_DIR', includeInIndex=0)
widget_product = add('product-widget', 'PBXFileReference', path='Mint Widgets.appex',
                     explicitFileType='wrapper.app-extension', sourceTree='BUILT_PRODUCTS_DIR', includeInIndex=0)
products = add('products', 'PBXGroup', name='Products', children=[app_product, widget_product], sourceTree='<group>')
main_group = add('main-group', 'PBXGroup', path='..', children=list(references.values()) + [products], sourceTree='<group>')

app_source_phase = add('app-sources', 'PBXSourcesBuildPhase', buildActionMask=2147483647,
                       files=[build_file('app-' + p, references[p]) for p in app_sources + shared_sources], runOnlyForDeploymentPostprocessing=0)
widget_source_phase = add('widget-sources', 'PBXSourcesBuildPhase', buildActionMask=2147483647,
                          files=[build_file('widget-' + p, references[p]) for p in widget_sources], runOnlyForDeploymentPostprocessing=0)
app_resources = add('app-resources', 'PBXResourcesBuildPhase', buildActionMask=2147483647,
                    files=[build_file('icon', references['DesktopWidgets/TrialIcon.icns'])], runOnlyForDeploymentPostprocessing=0)
widget_resources = add('widget-resources', 'PBXResourcesBuildPhase', buildActionMask=2147483647, files=[], runOnlyForDeploymentPostprocessing=0)
app_frameworks = add('app-frameworks', 'PBXFrameworksBuildPhase', buildActionMask=2147483647, files=[], runOnlyForDeploymentPostprocessing=0)
widget_frameworks = add('widget-frameworks', 'PBXFrameworksBuildPhase', buildActionMask=2147483647, files=[], runOnlyForDeploymentPostprocessing=0)
embed = add('embed-widget', 'PBXCopyFilesBuildPhase', name='Embed Widget Extension', buildActionMask=2147483647,
            dstPath='', dstSubfolderSpec=13, files=[build_file('embed-widget', widget_product,
            settings={'ATTRIBUTES': ['RemoveHeadersOnCopy']})], runOnlyForDeploymentPostprocessing=0)
sparkle = add('embed-sparkle', 'PBXShellScriptBuildPhase', name='Embed Sparkle', buildActionMask=2147483647,
              shellPath='/bin/zsh', shellScript='mkdir -p "$TARGET_BUILD_DIR/$FRAMEWORKS_FOLDER_PATH"\nrm -rf "$TARGET_BUILD_DIR/$FRAMEWORKS_FOLDER_PATH/Sparkle.framework"\nditto --norsrc --noextattr "$SRCROOT/../.build-deps/Sparkle-2.10.0/Sparkle.framework" "$TARGET_BUILD_DIR/$FRAMEWORKS_FOLDER_PATH/Sparkle.framework"\n',
              inputPaths=[], outputPaths=[], runOnlyForDeploymentPostprocessing=0, alwaysOutOfDate=1)

common = {
    'SDKROOT': 'macosx', 'MACOSX_DEPLOYMENT_TARGET': '14.0', 'SWIFT_VERSION': '5.0',
    'CODE_SIGN_IDENTITY': '-', 'CODE_SIGN_STYLE': 'Manual', 'DEVELOPMENT_TEAM': '',
    'ENABLE_USER_SCRIPT_SANDBOXING': 'NO', 'CLANG_ENABLE_MODULES': 'YES',
    'SWIFT_OPTIMIZATION_LEVEL': '-Onone', 'DEBUG_INFORMATION_FORMAT': 'dwarf',
    'ONLY_ACTIVE_ARCH': 'YES', 'GENERATE_INFOPLIST_FILE': 'NO',
    'CURRENT_PROJECT_VERSION': '15', 'MARKETING_VERSION': '2.5.1',
}
local_actions = [] if os.environ.get('MINT_WIDGET_USE_APP_INTENTS') == '1' else ['MINT_WIDGET_LOCAL_ACTIONS']
app_settings = dict(common, PRODUCT_NAME='Mint Todo Widgets Trial', PRODUCT_MODULE_NAME='MintWidgetsTrial',
                    PRODUCT_BUNDLE_IDENTIFIER='com.codex.minttodo.widgettrial', INFOPLIST_FILE='$(SRCROOT)/Trial-Info.plist',
                    SWIFT_ACTIVE_COMPILATION_CONDITIONS=['$(inherited)', 'MINT_WIDGET_TRIAL'] + local_actions,
                    FRAMEWORK_SEARCH_PATHS=['$(inherited)', '$(SRCROOT)/../.build-deps/Sparkle-2.10.0'],
                    LD_RUNPATH_SEARCH_PATHS=['$(inherited)', '@executable_path/../Frameworks'],
                    OTHER_LDFLAGS=['$(inherited)', '-framework', 'Sparkle'])
widget_settings = dict(common, PRODUCT_NAME='Mint Widgets', PRODUCT_MODULE_NAME='MintWidgetsExtension',
                       PRODUCT_BUNDLE_IDENTIFIER='com.codex.minttodo.widgettrial.widgets',
                       INFOPLIST_FILE='$(SRCROOT)/Widget-Info.plist', CODE_SIGN_ENTITLEMENTS='$(SRCROOT)/Widget.entitlements',
                       APPLICATION_EXTENSION_API_ONLY='YES', SKIP_INSTALL='YES', ENABLE_APP_SANDBOX='YES',
                       SWIFT_ACTIVE_COMPILATION_CONDITIONS=['$(inherited)'] + local_actions,
                       LD_RUNPATH_SEARCH_PATHS=['$(inherited)', '@executable_path/../Frameworks'])

def configurations(name, settings):
    configs = [add(name + '-' + label, 'XCBuildConfiguration', name=label, buildSettings=settings) for label in ['Debug', 'Release']]
    return add(name + '-config-list', 'XCConfigurationList', buildConfigurations=configs, defaultConfigurationIsVisible=0, defaultConfigurationName='Debug')

widget_target = add('widget-target', 'PBXNativeTarget', name='MintWidgetsExtension', productName='Mint Widgets',
                    productReference=widget_product, productType='com.apple.product-type.app-extension',
                    buildConfigurationList=configurations('widget', widget_settings),
                    buildPhases=[widget_source_phase, widget_frameworks, widget_resources], buildRules=[], dependencies=[])
proxy = add('extension-proxy', 'PBXContainerItemProxy', containerPortal=identifier('project'), proxyType=1,
             remoteGlobalIDString=widget_target, remoteInfo='MintWidgetsExtension')
dependency = add('extension-dependency', 'PBXTargetDependency', target=widget_target, targetProxy=proxy)
app_target = add('app-target', 'PBXNativeTarget', name='MintWidgetsTrial', productName='Mint Todo Widgets Trial',
                 productReference=app_product, productType='com.apple.product-type.application',
                 buildConfigurationList=configurations('app', app_settings),
                 buildPhases=[app_source_phase, app_frameworks, app_resources, embed, sparkle], buildRules=[], dependencies=[dependency])
project_id = add('project', 'PBXProject', attributes={'LastUpgradeCheck': '1600', 'BuildIndependentTargetsInParallel': 'YES'},
                 buildConfigurationList=configurations('project', common), compatibilityVersion='Xcode 14.0',
                 developmentRegion='zh-Hans', knownRegions=['en', 'zh-Hans', 'Base'], mainGroup=main_group,
                 productRefGroup=products, projectDirPath='', projectRoot='', targets=[app_target, widget_target])
document = dict(archiveVersion=1, classes={}, objectVersion=56, objects=objects, rootObject=project_id)
def string_numbers(value):
    if isinstance(value, dict):
        return {key: string_numbers(item) for key, item in value.items()}
    if isinstance(value, list):
        return [string_numbers(item) for item in value]
    return str(value) if isinstance(value, int) else value
(project / 'project.pbxproj').write_bytes(plistlib.dumps(string_numbers(document), sort_keys=False))
scheme_dir = project / 'xcshareddata/xcschemes'
scheme_dir.mkdir(parents=True, exist_ok=True)
ref = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app_target}" BuildableName="Mint Todo Widgets Trial.app" BlueprintName="MintWidgetsTrial" ReferencedContainer="container:MintWidgetsTrial.xcodeproj"/>'
(scheme_dir / 'MintWidgetsTrial.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
<BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref}</BuildActionEntry>
</BuildActionEntries></BuildAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
print(project)
