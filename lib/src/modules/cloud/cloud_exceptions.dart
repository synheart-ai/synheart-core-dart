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
  InvalidSignatureError() : super('HMAC signature validation failed');
}

class RateLimitExceededError extends CloudConnectorException {
  final int retryAfter;
  RateLimitExceededError(this.retryAfter)
      : super('Rate limit exceeded, retry after $retryAfter seconds');
}

class InvalidTenantError extends CloudConnectorException {
  InvalidTenantError() : super('Tenant ID not found or invalid');
}

class SchemaValidationError extends CloudConnectorException {
  SchemaValidationError() : super('HSI 1.0 schema validation failed');
}

class NetworkError extends CloudConnectorException {
  NetworkError(super.message);
}
