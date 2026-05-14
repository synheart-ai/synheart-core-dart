import 'dart:async';
import 'dart:convert';

import 'package:rxdart/rxdart.dart';
import 'package:syni/runtime.dart' as syni;

import '../../models/hsi_state.dart';
import 'syni_install_state.dart';
import 'syni_installer.dart';
import 'syni_persona.dart';

/// Public Syni client exposed to consumer apps as `Synheart.syni`.
///
/// Lifecycle:
/// 1. Construct (Synheart facade does this lazily once `consent.syni == true`).
/// 2. Caller invokes [install] — downloads + verifies the model, materializes
///    the persona, loads the engine on the runtime worker isolate.
/// 3. Caller invokes [chat] with messages. HSI is auto-attached from the
///    current `Synheart.currentHSIState` unless explicitly overridden.
/// 4. Caller invokes [uninstall] to free resources (rare; usually only on
///    consent revocation).
///
/// All inference runs on `package:syni`'s worker isolate — calls never block
/// the UI thread.
class SyniModule {
  SyniModule({SyniInstaller? installer, HSIState? Function()? hsiSnapshot})
      : _installer = installer ?? SyniInstaller(),
        _hsiSnapshot = hsiSnapshot ?? (() => null);

  final SyniInstaller _installer;
  final HSIState? Function() _hsiSnapshot;

  final syni.SyniRuntime _runtime = syni.SyniRuntime();
  final BehaviorSubject<SyniInstallState> _state =
      BehaviorSubject<SyniInstallState>.seeded(const SyniNotInstalled());

  SyniPersona? _persona;

  /// Stream of installation lifecycle events.
  Stream<SyniInstallState> get installState => _state.stream;

  /// Current installation state.
  SyniInstallState get currentState => _state.value;

  /// True iff [currentState] is [SyniInstalled].
  bool get isInstalled => _state.value is SyniInstalled;

  // -------------------------------------------------------------------------
  // Install / uninstall
  // -------------------------------------------------------------------------

  /// Install Syni: download model, verify, materialize persona, load engine.
  ///
  /// Idempotent — calling when already installed with the same persona/model
  /// is a no-op. Calling with a different persona reloads the engine.
  ///
  /// Throws [SyniInstallException] on any failure; emits [SyniInstallFailed]
  /// on the state stream before throwing.
  Future<void> install({
    required String personaId,
    required SyniModelSpec model,
  }) async {
    if (currentState is SyniInstalling) {
      throw StateError('install already in progress');
    }
    try {
      void emit(SyniInstallStage stage, double progress) {
        _state.add(SyniInstalling(stage: stage, progress: progress));
      }

      emit(SyniInstallStage.preflight, 0.0);

      final modelPath = await _installer.ensureModel(model, onProgress: emit);

      emit(SyniInstallStage.materializingPersona, 0.0);
      _persona = _installer.materializePersona(personaId);
      emit(SyniInstallStage.materializingPersona, 1.0);

      emit(SyniInstallStage.loadingEngine, 0.0);
      await _runtime.initialize();
      await _runtime.loadModel(modelPath);
      final version = await _runtime.getVersion() ?? 'unknown';
      emit(SyniInstallStage.loadingEngine, 1.0);

      _state.add(SyniInstalled(
        personaId: personaId,
        modelPath: modelPath,
        runtimeVersion: version,
      ));
    } catch (e) {
      _state.add(SyniInstallFailed(reason: e.toString(), cause: e));
      rethrow;
    }
  }

  /// Free the engine + worker isolate. Does not delete the downloaded model
  /// or persona cache — re-installing reuses them. To wipe local state too,
  /// the SDK consumer should additionally invoke storage cleanup.
  Future<void> uninstall() async {
    await _runtime.dispose();
    _persona = null;
    _state.add(const SyniNotInstalled());
  }

  // -------------------------------------------------------------------------
  // Chat
  // -------------------------------------------------------------------------

  /// Run a single chat turn against the loaded persona.
  ///
  /// [hsi] override is for testing / advanced cases. By default the module
  /// pulls the most recent HSI snapshot from the Synheart facade.
  Future<SyniChatResponse> chat(
    String message, {
    HSIState? hsi,
    int seed = 0,
  }) async {
    final installed = currentState;
    if (installed is! SyniInstalled) {
      throw StateError(
        'Syni is not installed. Call install() first.',
      );
    }
    final persona = _persona;
    if (persona == null) {
      throw StateError('persona missing (internal)');
    }

    // HSIState exposes the original payload as `rawJson`; decode for
    // transport over the FFI request which expects a Map.
    final hsiState = hsi ?? _hsiSnapshot();
    final hsiPayload = hsiState == null
        ? null
        : jsonDecode(hsiState.rawJson) as Map<String, dynamic>;

    final request = syni.SyniRuntimeRequest(
      instruction: _formatInstruction(persona, message),
      hsi: hsiPayload,
      schema: persona.responseSchemaId,
    );

    final raw = await _runtime.run(
      request,
      preset: _presetForSchema(persona.responseSchemaId),
      seed: seed,
    );

    return SyniChatResponse(
      personaId: persona.id,
      runtimeVersion: installed.runtimeVersion,
      rawJson: raw.rawJson,
      data: raw.data,
    );
  }

  /// Streaming counterpart to [chat]. Emits each generated token chunk as
  /// it arrives, then completes with the full validated response.
  ///
  /// Same preconditions as [chat] — Syni must be installed. Errors during
  /// generation are forwarded as stream errors.
  ///
  /// Typical UI pattern:
  /// ```dart
  /// final buf = StringBuffer();
  /// Synheart.syni!.chatStream(text).listen(
  ///   (event) {
  ///     if (event is SyniChatDelta) buf.write(event.text);
  ///     else if (event is SyniChatFinal) renderFinal(event.response);
  ///   },
  ///   onError: (e) => showError(e),
  /// );
  /// ```
  Stream<SyniChatEvent> chatStream(
    String message, {
    HSIState? hsi,
    int seed = 0,
  }) async* {
    final installed = currentState;
    if (installed is! SyniInstalled) {
      throw StateError('Syni is not installed. Call install() first.');
    }
    final persona = _persona;
    if (persona == null) {
      throw StateError('persona missing (internal)');
    }

    final hsiState = hsi ?? _hsiSnapshot();
    final hsiPayload = hsiState == null
        ? null
        : jsonDecode(hsiState.rawJson) as Map<String, dynamic>;

    final request = syni.SyniRuntimeRequest(
      instruction: _formatInstruction(persona, message),
      hsi: hsiPayload,
      schema: persona.responseSchemaId,
    );

    final stream = _runtime.runStream(
      request,
      preset: _presetForSchema(persona.responseSchemaId),
      seed: seed,
    );

    await for (final chunk in stream) {
      if (chunk is syni.SyniRuntimeStreamDelta) {
        yield SyniChatDelta(chunk.text);
      } else if (chunk is syni.SyniRuntimeStreamFinal) {
        // Re-decode for the typed response object that mirrors `chat()`.
        final decoded = jsonDecode(chunk.rawJson);
        yield SyniChatFinal(SyniChatResponse(
          personaId: persona.id,
          runtimeVersion: installed.runtimeVersion,
          rawJson: chunk.rawJson,
          data: decoded,
        ));
      }
    }
  }

  // -------------------------------------------------------------------------
  // Internals
  // -------------------------------------------------------------------------

  /// V1: prepend system prompt inline. V2: have the runtime do this via
  /// persona resolution rather than baking it into the instruction string.
  String _formatInstruction(SyniPersona persona, String userMessage) {
    return '${persona.systemPrompt}\n\nUser: $userMessage';
  }

  syni.SyniPreset _presetForSchema(String schemaId) {
    switch (schemaId) {
      case 'suggestions':
        return syni.SyniPreset.keyboard;
      case 'coach_response':
        return syni.SyniPreset.coach;
      case 'chat_response':
      default:
        return syni.SyniPreset.chat;
    }
  }

  /// For testing / shutdown. Closes the state stream and disposes the
  /// underlying runtime.
  Future<void> dispose() async {
    await _runtime.dispose();
    await _state.close();
  }
}

/// Response from [SyniModule.chat].
class SyniChatResponse {
  const SyniChatResponse({
    required this.personaId,
    required this.runtimeVersion,
    required this.rawJson,
    required this.data,
  });

  /// The persona that produced this response.
  final String personaId;

  /// Runtime semver reported by `libsyni_ffi`.
  final String runtimeVersion;

  /// Raw JSON string returned by the runtime, validated against the
  /// persona's `responseSchemaId`.
  final String rawJson;

  /// Parsed top-level map / list. Shape depends on the persona's schema.
  final dynamic data;
}

// ---------------------------------------------------------------------------
// Streaming events — emitted by [SyniModule.chatStream].
// ---------------------------------------------------------------------------

/// One event in a streaming chat response. Discriminated union over
/// incremental deltas and the final structured response.
sealed class SyniChatEvent {
  const SyniChatEvent();
}

/// An incremental token chunk emitted during generation.
class SyniChatDelta extends SyniChatEvent {
  const SyniChatDelta(this.text);
  final String text;

  @override
  String toString() => 'SyniChatDelta(${text.length} chars)';
}

/// The final schema-validated response. Always emitted exactly once at the
/// end of a successful stream.
class SyniChatFinal extends SyniChatEvent {
  const SyniChatFinal(this.response);
  final SyniChatResponse response;

  @override
  String toString() => 'SyniChatFinal(persona: ${response.personaId})';
}
