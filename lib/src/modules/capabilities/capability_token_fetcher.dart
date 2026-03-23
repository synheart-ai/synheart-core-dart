import 'capability_token.dart';

/// Interface for obtaining capability tokens.
///
/// Implementations may fetch from a remote server, read from cache, etc.
/// The default implementation is [RemoteCapabilityTokenFetcher].
abstract class CapabilityTokenFetcher {
  /// Fetch a capability token.
  ///
  /// Throws on network, auth, or server errors.
  Future<CapabilityToken> fetch();
}
