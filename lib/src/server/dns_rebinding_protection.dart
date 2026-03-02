import 'dart:io';

/// Default host allowlist used by DNS rebinding protection.
const Set<String> defaultDnsRebindingAllowedHosts = {
  'localhost',
  '127.0.0.1',
  '::1',
};

/// Validates request host/origin headers against configured allowlists.
bool isRequestAllowedByDnsRebindingProtection(
  HttpRequest request, {
  required Set<String>? allowedHosts,
  required Set<String>? allowedOrigins,
  Set<String> defaultAllowedHosts = defaultDnsRebindingAllowedHosts,
}) {
  final hostHeader = request.headers.value(HttpHeaders.hostHeader);
  if (hostHeader == null || hostHeader.trim().isEmpty) {
    return false;
  }

  final allowedHostSet = _normalizedAllowedHosts(
    allowedHosts: allowedHosts,
    defaultAllowedHosts: defaultAllowedHosts,
  );
  if (!_isHostAllowed(hostHeader, allowedHostSet)) {
    return false;
  }

  final originHeader = request.headers.value('origin');
  if (originHeader == null || originHeader.trim().isEmpty) {
    return true;
  }

  if (originHeader.trim().toLowerCase() == 'null') {
    return false;
  }

  final configuredOrigins = _normalizedAllowedOrigins(allowedOrigins);
  if (configuredOrigins != null) {
    final normalizedOrigin = normalizeDnsOrigin(originHeader);
    return normalizedOrigin != null &&
        configuredOrigins.contains(normalizedOrigin);
  }

  final originUri = Uri.tryParse(originHeader);
  if (originUri == null || originUri.host.isEmpty) {
    return false;
  }

  final originHost = normalizeDnsHost(originUri.host);
  return allowedHostSet.contains(originHost);
}

/// Normalizes a host value to lower-case host only (strips scheme/port/brackets).
String normalizeDnsHost(String hostOrOrigin) {
  final lower = hostOrOrigin.trim().toLowerCase();

  if (lower.contains('://')) {
    final parsedUri = Uri.tryParse(lower);
    if (parsedUri != null && parsedUri.host.isNotEmpty) {
      return normalizeDnsHost(parsedUri.host);
    }
  }

  if (lower.startsWith('[')) {
    final end = lower.indexOf(']');
    if (end > 1) {
      return lower.substring(1, end);
    }
  }

  final firstColon = lower.indexOf(':');
  final lastColon = lower.lastIndexOf(':');
  if (firstColon != -1 && firstColon == lastColon) {
    return lower.substring(0, firstColon);
  }

  return lower;
}

/// Normalizes an origin to `scheme://host[:port]`.
String? normalizeDnsOrigin(String origin) {
  final parsedUri = Uri.tryParse(origin.trim());
  if (parsedUri == null || parsedUri.scheme.isEmpty || parsedUri.host.isEmpty) {
    return null;
  }

  final normalizedHost = normalizeDnsHost(parsedUri.host);
  final portPart = parsedUri.hasPort ? ':${parsedUri.port}' : '';
  return '${parsedUri.scheme.toLowerCase()}://$normalizedHost$portPart';
}

Set<String> _normalizedAllowedHosts({
  required Set<String>? allowedHosts,
  required Set<String> defaultAllowedHosts,
}) {
  final configuredHosts = allowedHosts;
  if (configuredHosts != null && configuredHosts.isNotEmpty) {
    return configuredHosts.map(normalizeDnsHost).toSet();
  }

  return defaultAllowedHosts.map(normalizeDnsHost).toSet();
}

Set<String>? _normalizedAllowedOrigins(Set<String>? allowedOrigins) {
  final configuredOrigins = allowedOrigins;
  if (configuredOrigins == null || configuredOrigins.isEmpty) {
    return null;
  }

  return configuredOrigins.map(normalizeDnsOrigin).whereType<String>().toSet();
}

bool _isHostAllowed(String hostHeader, Set<String> allowedHosts) {
  final rawHost = hostHeader.trim().toLowerCase();
  final normalizedHost = normalizeDnsHost(rawHost);

  if (allowedHosts.contains(rawHost)) {
    return true;
  }

  return allowedHosts.contains(normalizedHost);
}
