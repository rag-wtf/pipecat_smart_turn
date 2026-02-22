#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#
Pod::Spec.new do |s|
  s.name             = 'pipecat_smart_turn_macos'
  s.version          = '0.0.1'
  s.summary          = 'A macOS implementation of the pipecat_smart_turn plugin.'
  s.description      = <<-DESC
  A macOS implementation of the pipecat_smart_turn plugin.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :type => 'BSD', :file => '../LICENSE' }
  s.author           = { 'Wtf Rag Pipecat Smart Turn' => 'email@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'pipecat_smart_turn_macos/Sources/**/*.swift'
  s.dependency 'FlutterMacOS'
  s.platform = :osx
  s.osx.deployment_target = '10.15'
  s.swift_version = '6.1'
end

