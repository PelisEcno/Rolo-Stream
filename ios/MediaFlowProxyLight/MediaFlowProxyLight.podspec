Pod::Spec.new do |s|
  s.name             = 'MediaFlowProxyLight'
  s.version          = '3.0.0'
  s.summary          = 'MediaFlow Proxy Light (Rust) para iOS'
  s.description      = 'Servidor proxy local para extracción de streams'
  s.homepage         = 'https://github.com/PelisEcno/mediaflow-proxy-light'
  s.license          = { :type => 'MIT' }
  s.author           = { 'PelisEcno' => 'you@example.com' }
  s.platform         = :ios, '13.0'
  s.source           = { :path => '.' }
  
  s.vendored_frameworks = 'MediaFlowProxyLight.xcframework'
  
  s.frameworks = 'Foundation', 'Security'
  s.libraries = 'c++', 'z', 'resolv'
  
  s.pod_target_xcconfig = {
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386'
  }
end