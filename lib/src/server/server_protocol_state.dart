final Expando<String> _negotiatedProtocolVersions =
    Expando<String>('mcp_dart.server.negotiatedProtocolVersion');

/// Reads the legacy protocol version negotiated by [server].
///
/// This package-internal state keeps the deprecated low-level server's public
/// interface unchanged while allowing the high-level server facade to preserve
/// version-specific wire behavior.
String? readServerProtocolVersion(Object server) =>
    _negotiatedProtocolVersions[server];

/// Records the legacy protocol [version] negotiated by [server].
void writeServerProtocolVersion(Object server, String? version) {
  _negotiatedProtocolVersions[server] = version;
}
