#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#
Pod::Spec.new do |s|
  s.name             = 'pipecat_smart_turn_macos'
  s.version          = '0.1.0+1'
  s.summary          = 'A macOS implementation of the pipecat_smart_turn plugin.'
  s.description      = <<-DESC
  A macOS implementation of the pipecat_smart_turn plugin.
                       DESC
  s.homepage         = 'https://rag.wtf'
  s.license          = { :type => 'BSD-2-Clause', :file => '../LICENSE' }
  s.author           = { 'limcheekin' => 'limcheekin@vobject.com' }
  s.source           = { :path => '.' }
  s.source_files = 'pipecat_smart_turn_macos/Sources/**/*.swift'
  s.dependency 'FlutterMacOS'
  s.dependency 'onnxruntime-objc', '1.24.2'
  s.static_framework = true
  s.platform = :osx, '14.0'
  s.osx.deployment_target = '14.0'
  s.swift_version = '5.0'
end

