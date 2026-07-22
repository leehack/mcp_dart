import 'package:test/test.dart';

import '../../tool/release/release_prep_plan.dart';

void main() {
  test('detects an SDK-only dev release', () {
    final plan = ReleasePrepPlan.detect(
      baseSdkPubspec: _pubspec('mcp_dart', '2.3.0-dev.1'),
      headSdkPubspec: _pubspec('mcp_dart', '2.3.0-dev.2'),
      baseCliPubspec: _pubspec('mcp_dart_cli', '0.2.0-dev.1'),
      headCliPubspec: _pubspec('mcp_dart_cli', '0.2.0-dev.1'),
    );

    expect(plan.packageNames, ['mcp_dart']);
    expect(plan.channel, ReleaseChannel.dev);
    expect(plan.sdkVersion, '2.3.0-dev.2');
  });

  test('detects a coordinated stable release', () {
    final plan = ReleasePrepPlan.detect(
      baseSdkPubspec: _pubspec('mcp_dart', '2.3.0-dev.2'),
      headSdkPubspec: _pubspec('mcp_dart', '2.3.0'),
      baseCliPubspec: _pubspec('mcp_dart_cli', '0.2.0-dev.2'),
      headCliPubspec: _pubspec('mcp_dart_cli', '0.2.0'),
    );

    expect(plan.packageNames, ['mcp_dart', 'mcp_dart_cli']);
    expect(plan.channel, ReleaseChannel.stable);
    expect(plan.packagesJson, '["mcp_dart","mcp_dart_cli"]');
  });

  test('rejects a prep change without a version increase', () {
    expect(
      () => ReleasePrepPlan.detect(
        baseSdkPubspec: _pubspec('mcp_dart', '2.3.0'),
        headSdkPubspec: _pubspec('mcp_dart', '2.3.0'),
        baseCliPubspec: _pubspec('mcp_dart_cli', '0.2.0'),
        headCliPubspec: _pubspec('mcp_dart_cli', '0.2.0'),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects a version downgrade', () {
    expect(
      () => ReleasePrepPlan.detect(
        baseSdkPubspec: _pubspec('mcp_dart', '2.3.0-dev.2'),
        headSdkPubspec: _pubspec('mcp_dart', '2.3.0-dev.1'),
        baseCliPubspec: _pubspec('mcp_dart_cli', '0.2.0-dev.1'),
        headCliPubspec: _pubspec('mcp_dart_cli', '0.2.0-dev.1'),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects mixed stable and dev package releases', () {
    expect(
      () => ReleasePrepPlan.detect(
        baseSdkPubspec: _pubspec('mcp_dart', '2.3.0-dev.2'),
        headSdkPubspec: _pubspec('mcp_dart', '2.3.0'),
        baseCliPubspec: _pubspec('mcp_dart_cli', '0.2.0-dev.2'),
        headCliPubspec: _pubspec('mcp_dart_cli', '0.3.0-dev.1'),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('uses semantic prerelease ordering', () {
    final plan = ReleasePrepPlan.detect(
      baseSdkPubspec: _pubspec('mcp_dart', '2.4.0-dev.9'),
      headSdkPubspec: _pubspec('mcp_dart', '2.4.0-dev.10'),
      baseCliPubspec: _pubspec('mcp_dart_cli', '0.2.0'),
      headCliPubspec: _pubspec('mcp_dart_cli', '0.2.0'),
    );

    expect(plan.sdkVersion, '2.4.0-dev.10');
  });
}

String _pubspec(String name, String version) => '''
name: $name
version: $version
''';
