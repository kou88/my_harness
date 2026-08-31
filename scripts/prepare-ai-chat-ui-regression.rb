#!/usr/bin/env ruby
# Generate a disposable Simulator host that compiles the production chat sources.
# Its bundle/data/transport are separate from MyHarness; never installs over user data.
require 'xcodeproj'
require 'tmpdir'

root = File.expand_path('..', __dir__)
directory = Dir.mktmpdir('myharness-chat-ui-')
project = Xcodeproj::Project.new(File.join(directory, 'ChatUIRegression.xcodeproj'))
target = project.new_target(:application, 'ChatUIRegression', :ios, '17.0')
sources = %w[
  MyHarness/domain/ai/AIModels.swift
  MyHarness/domain/ai/AIMessageContent.swift
  MyHarness/domain/ai/AICodeSyntax.swift
  MyHarness/state/AIChatState.state.swift
  MyHarness/view/AIConversationList.view.swift
  MyHarness/view/AIChatScreen.view.swift
  MyHarness/view/AIHarnessControls.view.swift
  MyHarness/view/AIChatControls.view.swift
  MyHarness/view/AISharing.view.swift
  MyHarness/view/AIChatMessages.view.swift
  MyHarness/view/AISelectableText.view.swift
  MyHarness/view/AIMermaidCodeBlock.view.swift
  MyHarness/view/ProductOpsMarkdown.view.swift
  Tests/AIChatStateRegression/ControlledTransport.swift
  Tests/AIChatUIRegression/FixtureApp.swift
]
sources.each { |path| target.add_file_references([project.main_group.new_file(File.join(root, path))]) }
%w[
  MyHarness/Resources/mermaid.html
  MyHarness/Resources/mermaid-renderer.js
  MyHarness/Resources/mermaid.min.js
].each do |path|
  reference = project.main_group.new_file(File.join(root, path))
  target.resources_build_phase.add_file_reference(reference)
end
target.build_configurations.each do |config|
  config.build_settings.merge!({
    'PRODUCT_BUNDLE_IDENTIFIER' => 'com.kou888.myharness.chat-ui-regression',
    'GENERATE_INFOPLIST_FILE' => 'YES', 'SWIFT_VERSION' => '5.0',
    'INFOPLIST_KEY_UILaunchScreen_Generation' => 'YES',
    'INFOPLIST_KEY_UIApplicationSceneManifest_Generation' => 'YES',
    'TARGETED_DEVICE_FAMILY' => '1', 'CODE_SIGN_IDENTITY' => '-',
    'CODE_SIGNING_ALLOWED' => 'YES'
  })
end
project.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(target)
scheme.set_launch_target(target)
scheme.save_as(project.path, 'ChatUIRegression', true)
puts project.path
