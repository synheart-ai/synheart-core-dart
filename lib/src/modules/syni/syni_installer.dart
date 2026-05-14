import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'syni_install_state.dart';
import 'syni_persona.dart';

/// Identifies a downloadable inference model.
///
/// V1 supports a single curated set of GGUF models hosted on Hugging Face.
/// Production builds should validate [sha256] against a release manifest
/// signed by Synheart's release key (TODO post-V1).
class SyniModelSpec {
  const SyniModelSpec({
    required this.id,
    required this.filename,
    required this.downloadUrl,
    required this.sha256,
    required this.approxBytes,
  });

  /// Stable identifier (e.g. `gemma-2b-it-Q4_K_M`). Used as the local
  /// filename root inside the syni cache directory.
  final String id;

  /// Filename used on disk (typically `<id>.gguf`).
  final String filename;

  /// HTTPS URL the runtime downloads from. MUST be https.
  final String downloadUrl;

  /// Lowercase hex SHA-256 of the downloaded artifact. Verification fails
  /// the install if mismatched.
  final String sha256;

  /// Approximate file size in bytes — for UI progress + capability gating.
  final int approxBytes;
}

/// V1 model catalog. Replace with a server-signed manifest fetched from
/// `synheart-cloud` once that exists.
class SyniModels {
  SyniModels._();

  /// Gemma 2B Instruct, Q4_K_M quantization. ~1.5 GB. Good balance for
  /// phone-class devices.
  static const SyniModelSpec gemma2bInstructQ4 = SyniModelSpec(
    id: 'gemma-2b-it-Q4_K_M',
    filename: 'gemma-2b-it-Q4_K_M.gguf',
    downloadUrl:
        'https://huggingface.co/google/gemma-2b-it-GGUF/resolve/main/gemma-2b-it-Q4_K_M.gguf',
    // TODO(SYNI-V2): pin real SHA-256 once we ship a release manifest.
    sha256: '',
    approxBytes: 1_500_000_000,
  );
}

/// Downloads + verifies a model and materializes a persona. Emits progress
/// via the supplied callback. Returns the final on-disk model path.
class SyniInstaller {
  SyniInstaller();

  /// Where downloaded models live on the local filesystem.
  ///
  /// V1 uses the app's documents directory. V2 should move to the core
  /// runtime's encrypted cache directory so models inherit the same
  /// at-rest encryption as artifacts.
  Future<Directory> _modelsDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/synheart_syni_models');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// Returns the path to the model file. Downloads if not already on disk.
  /// Calls [onProgress] with bytes-downloaded fraction.
  Future<String> ensureModel(
    SyniModelSpec spec, {
    required void Function(SyniInstallStage, double) onProgress,
  }) async {
    final dir = await _modelsDir();
    final path = '${dir.path}/${spec.filename}';
    final file = File(path);

    if (!file.existsSync()) {
      onProgress(SyniInstallStage.downloadingModel, 0.0);
      await _download(spec.downloadUrl, file, onProgress: (p) {
        onProgress(SyniInstallStage.downloadingModel, p);
      });
    }

    if (spec.sha256.isNotEmpty) {
      onProgress(SyniInstallStage.verifyingModel, 0.0);
      final actual = await _sha256(file);
      onProgress(SyniInstallStage.verifyingModel, 1.0);
      if (actual.toLowerCase() != spec.sha256.toLowerCase()) {
        // Discard a possibly-corrupted file so the next attempt re-downloads.
        try {
          file.deleteSync();
        } catch (_) {}
        throw SyniInstallException(
          'model SHA-256 mismatch: expected ${spec.sha256}, got $actual',
        );
      }
    }

    return path;
  }

  /// V1 persona materialization: look up a built-in persona by ID. V2 will
  /// load from `syni-core-spec` bundled assets and cache the materialized
  /// per-user form synced from Syni Cloud.
  SyniPersona materializePersona(String personaId) {
    final p = SyniPersonas.byId(personaId);
    if (p == null) {
      throw SyniInstallException('unknown persona: $personaId');
    }
    return p;
  }

  // -------------------------------------------------------------------------
  // Internals
  // -------------------------------------------------------------------------

  Future<void> _download(
    String url,
    File outFile, {
    required void Function(double) onProgress,
  }) async {
    final req = http.Request('GET', Uri.parse(url));
    final streamed = await http.Client().send(req);
    if (streamed.statusCode != 200) {
      throw SyniInstallException(
        'model download HTTP ${streamed.statusCode} for $url',
      );
    }
    final total = streamed.contentLength ?? 0;
    final sink = outFile.openWrite();
    var received = 0;
    try {
      await for (final chunk in streamed.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress(received / total);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    onProgress(1.0);
  }

  Future<String> _sha256(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }
}

class SyniInstallException implements Exception {
  SyniInstallException(this.message);
  final String message;

  @override
  String toString() => 'SyniInstallException: $message';
}
