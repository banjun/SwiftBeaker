Pod::Spec.new do |s|
  s.name             = 'SwiftBeaker'
  s.version          = '1.0.1'
  s.summary          = 'Swift client generator for API Blueprint'
  s.description      = <<-DESC
  SwiftBeaker is a Swift client generator for API Blueprint.
  the pod depends on runtime dependencies that generated client depends on.
                       DESC
  s.homepage         = 'https://github.com/banjun/SwiftBeaker'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'banjun' => 'banjun@gmail.com' }
  s.source           = { :git => 'https://github.com/banjun/SwiftBeaker.git', :tag => s.version.to_s }
  s.social_media_url = 'https://twitter.com/banjun'
  s.ios.deployment_target = '9.0'
  s.osx.deployment_target = '10.11'
  s.source_files = 'Pod/Classes/**/*.swift'
  s.dependency 'APIKit'
  s.dependency 'URITemplate'
end
