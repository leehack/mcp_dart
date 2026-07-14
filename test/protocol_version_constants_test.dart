import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

void main() {
  test('public protocol version roles remain independent', () {
    expect(previewProtocolVersion, '2026-07-28');
    expect(defaultProtocolVersion, previewProtocolVersion);
    expect(latestInitializationProtocolVersion, '2025-11-25');
    expect(stableProtocolVersion, latestInitializationProtocolVersion);
    expect(
      McpProtocol.legacy.preferredProtocolVersion,
      latestInitializationProtocolVersion,
    );
    expect(legacyProtocolVersions.first, latestInitializationProtocolVersion);

    // ignore: deprecated_member_use_from_same_package
    expect(latestProtocolVersion, stableProtocolVersion);
  });
}
