import Flutter

/// Minimal Flutter plugin that exists solely to trigger CocoaPods linking
/// of the synheart-core-runtime static library via the podspec's
/// vendored_frameworks + force_load.
///
/// All actual FFI calls go through Dart's DynamicLibrary.process().
public class SynheartCorePlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        // No channels needed — FFI handles everything.
    }
}
