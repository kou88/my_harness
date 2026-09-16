#!/usr/bin/env ruby
# Disposable offline host; includes the production sharing screen and state.
require 'xcodeproj'
require 'tmpdir'
root = File.expand_path('..', __dir__)
directory = Dir.mktmpdir('myharness-sharing-ui-')
project = Xcodeproj::Project.new(File.join(directory, 'SharingUIRegression.xcodeproj'))
target = project.new_target(:application, 'SharingUIRegression', :ios, '17.0')
%w[
  MyHarness/domain/ai/AIModels.swift
  MyHarness/domain/ai/AIInferenceModels.swift
  MyHarness/state/AIChatState.state.swift
  MyHarness/view/AISharing.view.swift
  Tests/AIChatStateRegression/ControlledTransport.swift
  Tests/AIChatUIRegression/SharingFixtureApp.swift
].each { |path| target.add_file_references([project.main_group.new_file(File.join(root, path))]) }
target.build_configurations.each do |config|
  config.build_settings.merge!({
    'PRODUCT_BUNDLE_IDENTIFIER' => 'com.kou888.myharness.sharing-ui-regression',
    'GENERATE_INFOPLIST_FILE' => 'YES', 'SWIFT_VERSION' => '5.0',
    'INFOPLIST_KEY_UILaunchScreen_Generation' => 'YES',
    'INFOPLIST_KEY_UIApplicationSceneManifest_Generation' => 'YES',
    'TARGETED_DEVICE_FAMILY' => '1', 'CODE_SIGN_IDENTITY' => '-', 'CODE_SIGNING_ALLOWED' => 'YES'
  })
end
project.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(target)
scheme.set_launch_target(target)
scheme.save_as(project.path, 'SharingUIRegression', true)
puts project.path
