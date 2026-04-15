require 'yaml'

pubspec = YAML.load_file(File.join(__dir__, '..', 'pubspec.yaml'))

Pod::Spec.new do |s|
  s.name             = 'synheart_core'
  s.version          = pubspec['version']
  s.summary          = 'Synheart Core SDK - native runtime for Flutter'
  s.description      = 'Provides the synheart-core-runtime static library for iOS. '\
                        'Links with -force_load to preserve FFI symbols accessed via dlsym.'
  s.homepage         = pubspec['homepage'] || 'https://github.com/synheart-ai/synheart-core-flutter'
  s.license          = { :type => 'Apache-2.0' }
  s.author           = { 'SynHeart AI' => 'eng@synheart.ai' }
  s.source           = { :path => '.' }
  s.platform         = :ios, '15.0'

  # Minimal Swift file for Flutter plugin registration
  s.source_files     = 'Classes/**/*'
  s.swift_version    = '5.0'

  # Force-load the Rust static library so ALL synheart_core_* symbols are
  # preserved for Dart FFI's dlsym (DynamicLibrary.process on iOS).
  #
  # Path: <consumer-app>/synheart/vendor/runtime/ios/SynheartCoreRuntime.xcframework/
  # Populate via:
  #   synheart install runtime                                      (registry)
  #   synheart runtime install --from <core-runtime>/build/dist/core (local build)
  #   make flutter FLUTTER_PROJECT=<consumer-app>                    (from core-runtime Makefile)
  s.user_target_xcconfig = {
    'OTHER_LDFLAGS' => '$(inherited) -force_load "${PODS_ROOT}/../../synheart/vendor/runtime/ios/SynheartCoreRuntime.xcframework/ios-arm64/libsynheart_core_runtime.a"',
    'DEAD_CODE_STRIPPING' => 'NO',
  }

  s.dependency 'Flutter'
end
