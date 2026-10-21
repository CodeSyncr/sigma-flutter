Pod::Spec.new do |s|
  s.name             = 'sigma'
  s.version          = '1.0.0'
  s.summary          = "Sigma's native spreadsheet editor in Flutter apps."
  s.description      = "Sigma's native spreadsheet editor in Flutter apps, through the NimbusSigma iOS SDK."
  s.homepage         = 'https://github.com/CodeSyncr/sigma-flutter'
  s.license          = { :type => 'Commercial', :file => '../LICENSE' }
  s.author           = { 'CodeSyncr' => 'yashkumar12125@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'sigma/Sources/sigma/**/*.swift'
  s.resource_bundles = { 'sigma_privacy' => ['sigma/Sources/sigma/PrivacyInfo.xcprivacy'] }
  s.dependency 'Flutter'
  # The native iOS SDK (github.com/CodeSyncr/sigma-ios). It is not on the
  # CocoaPods trunk: the app's Podfile names it with its git tag (see README).
  s.dependency 'NimbusSigma', '~> 2.1.1'
  s.platform = :ios, '16.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.10'
end
