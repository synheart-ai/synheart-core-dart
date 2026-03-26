package ai.synheart.wear.watch

import io.flutter.embedding.android.FlutterFragmentActivity

// Must extend FlutterFragmentActivity (not FlutterActivity) so the health package
// can register the Health Connect permission launcher on Android.
class MainActivity : FlutterFragmentActivity()
