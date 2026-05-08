require 'yaml'

pubspec = YAML.load_file(File.join(__dir__, '..', 'pubspec.yaml'))

Pod::Spec.new do |s|
  s.name             = 'synheart_core'
  s.version          = pubspec['version']
  s.summary          = 'Synheart Core SDK - native runtime for Flutter'
  s.description      = 'Provides the Synheart native runtime static library for iOS. '\
                        'ONNX Runtime is linked separately via the onnxruntime-c pod '\
                        'to avoid duplicate symbol errors from merged C++ archives.'
  s.homepage         = pubspec['homepage'] || 'https://github.com/synheart-ai/synheart-core-flutter'
  s.license          = { :type => 'Apache-2.0' }
  s.author           = { 'SynHeart AI' => 'eng@synheart.ai' }
  s.source           = { :path => '.' }
  s.platform         = :ios, '15.0'

  s.source_files     = 'Classes/**/*'
  s.swift_version    = '5.0'

  # Force-load the native static library to preserve synheart_core_* symbols
  # for Dart FFI's dlsym (DynamicLibrary.process on iOS).
  #
  # The native archive is built without bundled ONNX Runtime C++ code, so
  # it is safe to force-load. ONNX Runtime is provided by the
  # onnxruntime-c pod below.
  lib_path = '"${PODS_ROOT}/../../synheart/vendor/runtime/ios/SynheartCoreRuntime.xcframework/ios-arm64/libsynheart_core_runtime.a"'

  s.user_target_xcconfig = {
    'OTHER_LDFLAGS' => "$(inherited) -force_load #{lib_path}",
    'DEAD_CODE_STRIPPING' => 'NO',
    # Preserve synheart_core_* globals through Archive's strip so Dart FFI's
    # DynamicLibrary.process()/dlsym can still resolve them in TestFlight builds.
    'STRIP_STYLE' => 'non-global',
  }

  s.dependency 'Flutter'
  # ONNX Runtime C API — linked separately from the native archive to avoid
  # duplicate symbols from merged static libraries (protobuf, abseil, re2
  # share C++ template instantiations across compilation units).
  s.dependency 'onnxruntime-c', '>= 1.20.0'
end
