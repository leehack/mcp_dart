import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

void main() {
  test('deprecated latest protocol version remains a stable alias', () {
    // ignore: deprecated_member_use_from_same_package
    expect(latestProtocolVersion, stableProtocolVersion);
  });
}
