Pod::Spec.new do |s|
  s.name             = 'ishim_native_callkit'
  s.version          = '1.0.0'
  s.summary          = 'Native iOS CallKit + PushKit handler for I-SHIM'
  s.description      = <<-DESC
Native iOS CallKit and PushKit integration for I-SHIM app.
WhatsApp-style incoming call handling with native UI.
                       DESC
  s.homepage         = 'https://github.com/user/ishim_native_callkit'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'I-SHIM' => 'dev@ishim.app' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '13.0'
  s.swift_version    = '5.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
