#!/usr/bin/env ruby
# 本番のPDF閲覧ソースを使う独立したSimulator検証用アプリを生成する。
# Its bundle/data/transport are separate from MyHarness; never installs over user data.
require 'xcodeproj'
require 'tmpdir'

root = File.expand_path('..', __dir__)
directory = Dir.mktmpdir('myharness-book-ui-')
project = Xcodeproj::Project.new(File.join(directory, 'BookUIRegression.xcodeproj'))
target = project.new_target(:application, 'BookUIRegression', :ios, '17.0')
sources = %w[
  MyHarness/domain/books/Book.swift
  MyHarness/domain/books/BookPageLayout.swift
  MyHarness/infra/display/AppInterfaceOrientationController.swift
  MyHarness/view/BookReader.view.swift
  MyHarness/view/PDFBook.view.swift
  Tests/BookReaderUIRegression/FixtureApp.swift
]
sources.each { |path| target.add_file_references([project.main_group.new_file(File.join(root, path))]) }
target.build_configurations.each do |config|
  config.build_settings.merge!({
    'PRODUCT_BUNDLE_IDENTIFIER' => 'com.kou888.myharness.book-ui-regression',
    'GENERATE_INFOPLIST_FILE' => 'YES', 'SWIFT_VERSION' => '5.0',
    'INFOPLIST_KEY_UILaunchScreen_Generation' => 'YES',
    'INFOPLIST_KEY_UIApplicationSceneManifest_Generation' => 'YES',
    'TARGETED_DEVICE_FAMILY' => '1,2', 'CODE_SIGN_IDENTITY' => '-',
    'CODE_SIGNING_ALLOWED' => 'YES'
  })
end
project.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(target)
scheme.set_launch_target(target)
scheme.save_as(project.path, 'BookUIRegression', true)
puts project.path
