platform :ios, '17.0'

install! 'cocoapods', deterministic_uuids: true

target 'MyHarness' do
  pod 'MobileVLCKit', '3.6.0'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |configuration|
      configuration.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
    end
  end
end
