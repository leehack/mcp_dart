import 'dart:io';

const _defaultAllowedHeaders = <String>[
  'Origin',
  'X-Requested-With',
  'Content-Type',
  'Accept',
  'Authorization',
  'MCP-Protocol-Version',
  'MCP-Session-Id',
  'Last-Event-ID',
  'Mcp-Method',
  'Mcp-Name',
];

/// Applies the browser CORS policy shared by the HTTP examples.
///
/// MCP 2026-07-28 may add validated `Mcp-Param-*` routing headers derived from a
/// tool's advertised schema. Echoing token-valid requested header names keeps
/// preflight responses aligned with those dynamic names.
bool setExampleBrowserCorsHeaders(
  HttpRequest request, {
  required Set<String> allowedOrigins,
}) {
  final response = request.response;
  final origin = request.headers.value('Origin');
  response.headers.set(
    HttpHeaders.varyHeader,
    'Origin, Access-Control-Request-Headers',
  );

  if (origin != null && !allowedOrigins.contains(origin)) {
    return false;
  }
  if (origin != null) {
    response.headers
      ..set('Access-Control-Allow-Origin', origin)
      ..set('Access-Control-Allow-Credentials', 'true');
  }

  response.headers
    ..set('Access-Control-Allow-Methods', 'GET, POST, DELETE, OPTIONS')
    ..set('Access-Control-Allow-Headers', _allowedHeaders(request))
    ..set('Access-Control-Expose-Headers', 'MCP-Session-Id')
    ..set('Access-Control-Max-Age', '86400');
  return true;
}

String _allowedHeaders(HttpRequest request) {
  final headers = <String>[..._defaultAllowedHeaders];
  final normalized = headers.map((header) => header.toLowerCase()).toSet();
  final requested = request.headers.value('Access-Control-Request-Headers');
  if (requested == null) {
    return headers.join(', ');
  }

  for (final value in requested.split(',')) {
    final header = value.trim();
    if (header.isEmpty ||
        !header.toLowerCase().startsWith('mcp-param-') ||
        !_isHttpFieldName(header)) {
      continue;
    }
    if (normalized.add(header.toLowerCase())) {
      headers.add(header);
    }
  }
  return headers.join(', ');
}

bool _isHttpFieldName(String value) =>
    value.codeUnits.every(_isHttpFieldNameTokenChar);

bool _isHttpFieldNameTokenChar(int unit) =>
    unit >= 0x30 && unit <= 0x39 ||
    unit >= 0x41 && unit <= 0x5A ||
    unit >= 0x61 && unit <= 0x7A ||
    switch (unit) {
      0x21 ||
      0x23 ||
      0x24 ||
      0x25 ||
      0x26 ||
      0x27 ||
      0x2A ||
      0x2B ||
      0x2D ||
      0x2E ||
      0x5E ||
      0x5F ||
      0x60 ||
      0x7C ||
      0x7E =>
        true,
      _ => false,
    };
