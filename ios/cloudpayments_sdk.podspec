#
# The CloudPayments iOS SDK is not published to the CocoaPods trunk, so the
# `Cloudpayments` dependency below can only be resolved if the *app's* Podfile
# points at the source repository. Add this to `ios/Podfile`:
#
#   pod 'Cloudpayments', :git => 'https://gitpub.cloudpayments.ru/integrations/sdk/cloudpayments-ios.git', :tag => '2.1.6'
#   pod 'CloudpaymentsNetworking', :git => 'https://gitpub.cloudpayments.ru/integrations/sdk/cloudpayments-ios.git', :tag => '2.1.6'
#
# See the package README for the full integration steps.
#
Pod::Spec.new do |s|
  s.name             = 'cloudpayments_sdk'
  s.version          = '0.2.0'
  s.summary          = 'CloudPayments for Flutter — cryptograms and 3-D Secure through the official iOS SDK.'
  s.description      = <<-DESC
Flutter bindings for the official CloudPayments iOS SDK: card cryptogram
generation and the 3-D Secure WebView flow.
                       DESC
  s.homepage         = 'https://github.com/cloudpayments-community/cloudpayments_sdk'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'cloudpayments_sdk contributors' => 'noreply@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'

  s.dependency 'Flutter'
  # Constrained on purpose: this plugin calls 2.x-only signatures
  # (makeCardCryptogramPacket with publicKey/keyVersion). Without the
  # constraint an app that pinned the archived 1.3.3 tag would resolve
  # cleanly and then fail with a bare "extra argument 'keyVersion' in call".
  s.dependency 'Cloudpayments', '~> 2.1'

  # The CloudPayments SDK requires iOS 15.0.
  s.platform = :ios, '15.0'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386'
  }
  s.swift_version = '5.0'
end
