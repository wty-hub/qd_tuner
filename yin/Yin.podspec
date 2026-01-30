Pod::Spec.new do |s|
  s.name             = 'Yin'
  s.version          = '0.0.1'
  s.summary          = 'Yin pitch detection library'
  s.description      = <<-DESC
This is a local pod for the Yin pitch detection library C sources.
                       DESC
  s.homepage         = 'https://example.com'
  s.license          = { :type => 'MIT', :text => 'LICENSE' }
  s.author           = { 'QD Tuner' => 'email@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = '*.{c,h}'
  s.public_header_files = '*.h'
  
  s.ios.deployment_target = '12.0'
  s.osx.deployment_target = '10.14'
  
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
