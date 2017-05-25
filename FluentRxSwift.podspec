Pod::Spec.new do |spec|
  spec.name         = 'FluentRxSwift'
  spec.version      = '1.0.0'
  spec.license      = { :type => 'MIT' }
  spec.homepage     = 'https://github.com/thanhtrdang/FluentRxSwift'
  spec.authors      = { 'Thanh Dang' => 'thanhtrdang@gmail.com' }
  spec.summary      = 'Fluent RxSwift API'
  spec.source       = { :git => 'https://github.com/thanhtrdang/FluentRxSwift.git', :tag => spec.version.to_s }

  spec.ios.deployment_target = '8.0'

  spec.source_files = 'Source/*.swift'
  
  spec.frameworks  = 'Foundation'
  spec.dependency 'RxSwift', '~> 3.4.1'
  spec.dependency 'RxCocoa', '~> 3.4.1'
  
end