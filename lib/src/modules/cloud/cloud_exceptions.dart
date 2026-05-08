class CloudConnectorException implements Exception {
  final String message;
  CloudConnectorException(this.message);
  @override
  String toString() => 'CloudConnectorException: $message';
}

class ConsentRequiredError extends CloudConnectorException {
  ConsentRequiredError(super.message);
}

class InvalidSignatureError extends CloudConnectorException {
  InvalidSignatureError() : super('request signature validation failed');
}

class RateLimitExceededError extends CloudConnectorException {
  final int retryAfter;
  RateLimitExceededError(this.retryAfter)
    : super('Rate limit exceeded, retry after $retryAfter seconds');
}

class SchemaValidationError extends CloudConnectorException {
  SchemaValidationError() : super('HSI 1.1 schema validation failed');
}

class NetworkError extends CloudConnectorException {
  NetworkError(super.message);
}

class TokenExpiredError extends CloudConnectorException {
  TokenExpiredError(super.message);
}
