import 'dart:async';

import 'package:syni/agent.dart' as agent;

import '../../models/hsi_state.dart';
import 'syni_context_builder.dart';

/// Public Syni client, exposed to consumer apps as `Synheart.syni`.
///
/// **Thin by design.** `SyniModule` owns only what is genuinely the host
/// SDK's job:
/// - the [SyniContextBuilder] — projecting *this SDK's* HSI (live state +
///   stored session history) into the runtime's conditioning contract, and
/// - bridging that context into each chat call.
///
/// All Syni *orchestration* — model catalog, download/verify, install
/// lifecycle, persona binding, runtime/chat wiring — lives in `package:syni`
/// ([agent.SyniAgent]). The four-authority gate (consent / capability /
/// activation / session) lives in the `Synheart` facade. This keeps the
/// generic HSI SDK free of LLM-orchestration concerns.
class SyniModule {
  SyniModule({
    agent.SyniAgent? syniAgent,
    agent.SyniCloudConfig? cloudConfig,
    SyniContextBuilder? contextBuilder,
    HSIState? Function()? hsiSnapshot,
  })  : _agent = syniAgent ?? agent.SyniAgent(cloudConfig: cloudConfig),
        _contextBuilder =
            contextBuilder ?? SyniContextBuilder(liveState: hsiSnapshot);

  final agent.SyniAgent _agent;
  final SyniContextBuilder _contextBuilder;

  /// Whether a cloud client is configured (cloud chat is reachable).
  bool get hasCloud => _agent.hasCloud;

  // --- Install lifecycle (delegated to the agent) --------------------------

  /// Stream of installation lifecycle events.
  Stream<agent.SyniInstallState> get installState => _agent.installState;

  /// Current installation state.
  agent.SyniInstallState get currentState => _agent.currentState;

  /// True iff Syni is installed and ready for chat.
  bool get isInstalled => _agent.isInstalled;

  /// Install Syni: download + verify the model, load the engine, bind the
  /// supplied [persona]. See [agent.SyniAgent.install].
  Future<void> install({
    required agent.SyniPersona persona,
    required agent.SyniModelSpec model,
  }) =>
      _agent.install(persona: persona, model: model);

  /// Cold-start restore — if the model is already on disk, bind [persona]
  /// and load the engine without re-downloading. See
  /// [agent.SyniAgent.restoreInstallIfReady].
  Future<bool> restoreInstallIfReady({
    required agent.SyniPersona persona,
    required agent.SyniModelSpec model,
  }) =>
      _agent.restoreInstallIfReady(persona: persona, model: model);

  /// Free the engine + worker isolate (keeps the downloaded model on disk).
  Future<void> uninstall() => _agent.uninstall();

  // --- Chat (host SDK's job: build HSI context, then delegate) -------------

  /// Run a single chat turn. The [SyniContextBuilder] gathers this SDK's
  /// live HSI + stored session history and the result is passed to the
  /// agent as conditioning context. [mode] picks local vs cloud — see
  /// [agent.SyniExecutionMode].
  Future<agent.SyniChatResponse> chat(
    String message, {
    int seed = 0,
    agent.SyniExecutionMode mode = agent.SyniExecutionMode.localFirst,
  }) async {
    final hsiContext = await _contextBuilder.build(message: message);
    return _agent.chat(message,
        hsiContext: hsiContext, seed: seed, mode: mode);
  }

  /// Streaming counterpart to [chat].
  Stream<agent.SyniChatEvent> chatStream(
    String message, {
    int seed = 0,
    agent.SyniExecutionMode mode = agent.SyniExecutionMode.localFirst,
  }) async* {
    final hsiContext = await _contextBuilder.build(message: message);
    yield* _agent.chatStream(message,
        hsiContext: hsiContext, seed: seed, mode: mode);
  }

  /// For testing / shutdown.
  Future<void> dispose() => _agent.dispose();
}
