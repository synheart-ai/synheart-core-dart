require 'yaml'

pubspec = YAML.load_file(File.join(__dir__, '..', 'pubspec.yaml'))

Pod::Spec.new do |s|
  s.name             = 'synheart_core'
  s.version          = pubspec['version']
  s.summary          = 'Synheart Core SDK - native runtime for Flutter'
  s.description      = 'Provides the Synheart native runtime as a dynamic '\
                        'framework that Dart FFI opens at runtime. ONNX '\
                        'Runtime is linked separately via the onnxruntime-c '\
                        'pod; the Rust cdylib was built with '\
                        '`-undefined dynamic_lookup` so ONNX symbols resolve '\
                        'against the onnxruntime-c framework when iOS loads '\
                        'them side-by-side.'
  s.homepage         = pubspec['homepage'] || 'https://github.com/synheart-ai/synheart-core-flutter'
  s.license          = { :type => 'Apache-2.0' }
  s.author           = { 'SynHeart AI' => 'eng@synheart.ai' }
  s.source           = { :path => '.' }
  s.platform         = :ios, '15.0'

  s.source_files     = 'Classes/**/*'
  s.swift_version    = '5.0'

  # ── Native runtime distribution ─────────────────────────────────────
  #
  # The runtime is proprietary and shipped via the `synheart` CLI.
  # `synheart install runtime` downloads the right variant + version
  # from the private artifact registry and writes it to
  # `<app>/synheart/vendor/runtime/ios/SynheartCoreRuntime.xcframework`.
  #
  # The runtime is a DYNAMIC framework (cdylib wrapped in .framework).
  # We had to switch off the previous force-loaded static .a because
  # syni-flutter ships its own Rust static lib alongside this one, and
  # both .a's bundle identical Rust stdlib copies — producing ~2300
  # link-time duplicate-symbol errors. As a dynamic framework, each
  # Rust lib gets its own runtime at app load, no static overlap.
  #
  # CocoaPods's `vendored_frameworks` needs the framework to live next
  # to the podspec. We don't ship it in plugin source (the runtime is
  # versioned + variant-switched via the CLI, not pinned per plugin
  # release), so this `prepare_command` symlinks the CLI-installed
  # framework into the pod install dir at `pod install` time.
  s.prepare_command = <<-CMD
    set -e
    # Resolve the consumer app root. Two strategies, in order:
    #   1. SYNHEART_APP_ROOT env var — set by the consumer's Podfile,
    #      reliable in monorepo dev where the plugin source lives in
    #      a sibling directory (so walk-up doesn't reach the app).
    #   2. Walk-up from this pod's install dir — works when CocoaPods
    #      symlinks the dev pod into <app>/ios/Pods/.symlinks/.
    APP_ROOT="${SYNHEART_APP_ROOT:-}"
    if [ -z "$APP_ROOT" ]; then
      cursor="$(pwd)"
      for _ in 1 2 3 4 5 6 7 8 9 10; do
        cursor="$(cd "$cursor/.." && pwd)"
        if [ -d "$cursor/synheart/vendor/runtime/ios" ]; then
          APP_ROOT="$cursor"
          break
        fi
      done
    fi
    if [ -z "$APP_ROOT" ]; then
      echo "synheart_core: could not locate <app>/synheart/vendor/runtime/ios/"
      echo "  Set SYNHEART_APP_ROOT in your Podfile:"
      echo "    ENV['SYNHEART_APP_ROOT'] = File.expand_path('..', __dir__)"
      echo "  And run: synheart install runtime"
      exit 1
    fi
    SRC="$APP_ROOT/synheart/vendor/runtime/ios/SynheartCoreRuntime.xcframework"
    if [ ! -d "$SRC" ]; then
      echo "synheart_core: framework not found at $SRC"
      echo "  Run: synheart install runtime"
      exit 1
    fi
    rm -rf SynheartCoreRuntime.xcframework
    ln -s "$SRC" SynheartCoreRuntime.xcframework
  CMD

  s.vendored_frameworks = 'SynheartCoreRuntime.xcframework'

  s.user_target_xcconfig = {
    # Preserve synheart_core_* globals through Archive's strip so
    # Dart FFI's DynamicLibrary.open()/dlsym can still resolve them
    # in TestFlight builds. The framework's own exports are public;
    # this guards against host-app strip phases.
    'STRIP_STYLE' => 'non-global',

    # Force-load ONNX Runtime into the consumer app binary.
    #
    # SynheartCoreRuntime is a cdylib built with `-undefined
    # dynamic_lookup` for ONNX symbols (stable/lab tiers), so
    # `OrtGetApiBase` must resolve against a symbol already present in
    # the process. onnxruntime-c ships ONNX as a *static* archive;
    # nothing in the host app references it directly, so without this
    # the linker dead-strips the whole archive — `OrtGetApiBase` binds
    # to null and the runtime crashes on first ONNX use. Force-loading
    # lands (and exports) the symbols in the host executable.
    #
    # The path points at the pod's xcframework source slice — it exists
    # on disk after `pod install`, before linking, so it is a valid
    # link input (the build-dir copy is a script-phase output the
    # build system rejects). The slice is SDK-specific.
    'SYNHEART_ONNX_SLICE[sdk=iphoneos*]' => 'ios-arm64',
    'SYNHEART_ONNX_SLICE[sdk=iphonesimulator*]' => 'ios-arm64_x86_64-simulator',
    'OTHER_LDFLAGS' => '$(inherited) -force_load "$(PODS_ROOT)/onnxruntime-c/onnxruntime.xcframework/$(SYNHEART_ONNX_SLICE)/onnxruntime.framework/onnxruntime"',
  }

  s.dependency 'Flutter'
  # ONNX Runtime C API — provided as a separate dynamic framework in
  # the consumer app; loaded by iOS alongside SynheartCoreRuntime so
  # the cdylib's undefined ONNX symbols resolve at runtime.
  s.dependency 'onnxruntime-c', '>= 1.20.0'
end
