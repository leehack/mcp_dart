import 'dart:convert';
import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:mcp_dart_cli/src/update_command.dart';
import 'package:mcp_dart_cli/src/version.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pub_updater/pub_updater.dart';
import 'package:test/test.dart';

class MockLogger extends Mock implements Logger {}

class MockPubUpdater extends Mock implements PubUpdater {}

class MockProgress extends Mock implements Progress {}

void main() {
  group('UpdateCommand', () {
    late Logger logger;
    late PubUpdater pubUpdater;
    late UpdateCommand command;
    late Progress progress;

    setUp(() {
      logger = MockLogger();
      pubUpdater = MockPubUpdater();
      progress = MockProgress();
      command = UpdateCommand(logger: logger, pubUpdater: pubUpdater);

      when(() => logger.progress(any())).thenReturn(progress);
      when(() => pubUpdater.getLatestVersion(any()))
          .thenAnswer((_) async => packageVersion);
      when(() => pubUpdater.update(packageName: any(named: 'packageName')))
          .thenAnswer((_) async => ProcessResult(0, 0, '', ''));
    });

    test('can be instantiated', () {
      expect(command, isA<UpdateCommand>());
    });

    test('handles software error when checking for updates fails', () async {
      when(() => pubUpdater.getLatestVersion(any()))
          .thenThrow(Exception('oops'));

      final result = await command.run();

      expect(result, equals(ExitCode.software.code));
      verify(() => logger.err('Exception: oops')).called(1);
      verify(() => progress.fail()).called(1);
    });

    test('handles software error when update fails', () async {
      when(() => pubUpdater.getLatestVersion(any()))
          .thenAnswer((_) async => '9.9.9');
      when(() => pubUpdater.update(packageName: any(named: 'packageName')))
          .thenThrow(Exception('oops'));

      final result = await command.run();

      expect(result, equals(ExitCode.software.code));
      verify(() => logger.err('Exception: oops')).called(1);
      verify(() => progress.fail()).called(1);
    });

    test('logs message when already at latest version', () async {
      when(() => pubUpdater.getLatestVersion(any()))
          .thenAnswer((_) async => packageVersion);

      final result = await command.run();

      expect(result, equals(ExitCode.success.code));
      verify(() => logger.info('CLI is already at the latest version.'))
          .called(1);
      verifyNever(
          () => pubUpdater.update(packageName: any(named: 'packageName')));
    });

    test('updates to latest version', () async {
      when(() => pubUpdater.isUpToDate(
            packageName: any(named: 'packageName'),
            currentVersion: any(named: 'currentVersion'),
          )).thenAnswer((_) async => false);
      when(() => pubUpdater.getLatestVersion(any()))
          .thenAnswer((_) async => '9.9.9');
      when(() => pubUpdater.update(packageName: any(named: 'packageName')))
          .thenAnswer((_) async => ProcessResult(0, 0, '', ''));

      final result = await command.run();

      expect(result, equals(ExitCode.success.code));
      verify(() => logger.progress('Updating to 9.9.9')).called(1);
      verify(() => pubUpdater.update(packageName: 'mcp_dart_cli')).called(1);
      verify(() => progress.complete('Updated to 9.9.9')).called(1);
    });

    test('detects standalone executable names for current platform', () {
      expect(
        isRunningAsStandaloneExecutable(
          executablePath: '/tmp/$binaryExecutableName',
        ),
        isTrue,
      );
      expect(
        isRunningAsStandaloneExecutable(executablePath: '/tmp/dart'),
        isFalse,
      );
    });

    test('resolves a release asset name for supported host platforms', () {
      expect(
        releaseAssetNameForCurrentPlatform(),
        anyOf(
          equals('mcp_dart-linux-x64'),
          equals('mcp_dart-macos-x64'),
          equals('mcp_dart-macos-arm64'),
          equals('mcp_dart-windows-x64.exe'),
          isNull,
        ),
      );

      expect(
        releaseAssetNameForHost(
          operatingSystem: 'linux',
          architecture: 'x64',
        ),
        equals('mcp_dart-linux-x64'),
      );
      expect(
        releaseAssetNameForHost(
          operatingSystem: 'macos',
          architecture: 'arm64',
        ),
        equals('mcp_dart-macos-arm64'),
      );
      expect(
        releaseAssetNameForHost(
          operatingSystem: 'windows',
          architecture: 'x64',
        ),
        equals('mcp_dart-windows-x64.exe'),
      );
      expect(
        releaseAssetNameForHost(
          operatingSystem: 'linux',
          architecture: 'arm64',
        ),
        isNull,
      );
      expect(
        releaseAssetNameForHost(
          operatingSystem: 'windows',
          architecture: 'arm64',
        ),
        isNull,
      );
    });

    test('describes unsupported standalone hosts by OS and architecture', () {
      expect(
        standaloneHostDescription(
          operatingSystem: 'linux',
          architecture: 'arm64',
        ),
        equals('linux/arm64'),
      );
      expect(
        standaloneHostDescription(
          operatingSystem: 'windows',
          architecture: 'arm64',
        ),
        equals('windows/arm64'),
      );
    });

    test('standalone updater downloads binary and bundled skill', () async {
      final assetName = releaseAssetNameForCurrentPlatform();
      if (assetName == null) {
        markTestSkipped('No standalone asset is published for this platform.');
        return;
      }

      final tempDir = await Directory.systemTemp.createTemp('mcp_update_');
      addTearDown(() => tempDir.delete(recursive: true));
      final server = await _ReleaseFixtureServer.start(assetName);
      addTearDown(server.close);
      final installDir = Directory('${tempDir.path}/bin');
      final updater = GitHubBinaryUpdater(
        logger: logger,
        releasesUri: server.releasesUri,
      );

      final result = await updater.update(
        currentVersion: '0.0.0',
        installDir: installDir.path,
      );

      expect(result, equals(ExitCode.success.code));
      expect(
        await File('${installDir.path}/$binaryExecutableName').readAsString(),
        equals('binary payload'),
      );
      expect(
        await File(
          '${tempDir.path}/share/mcp_dart/skills/mcp-developer/SKILL.md',
        ).readAsString(),
        equals('skill payload'),
      );
    });

    test('standalone updater installs missing skill when already current',
        () async {
      final assetName = releaseAssetNameForCurrentPlatform();
      if (assetName == null) {
        markTestSkipped('No standalone asset is published for this platform.');
        return;
      }

      final tempDir = await Directory.systemTemp.createTemp('mcp_update_');
      addTearDown(() => tempDir.delete(recursive: true));
      final server = await _ReleaseFixtureServer.start(assetName);
      addTearDown(server.close);
      final installDir = Directory('${tempDir.path}/bin');
      final updater = GitHubBinaryUpdater(
        logger: logger,
        releasesUri: server.releasesUri,
      );

      final result = await updater.update(
        currentVersion: '9.9.9',
        installDir: installDir.path,
      );

      expect(result, equals(ExitCode.success.code));
      expect(
        File('${installDir.path}/$binaryExecutableName').existsSync(),
        isFalse,
      );
      expect(
        await File(
          '${tempDir.path}/share/mcp_dart/skills/mcp-developer/SKILL.md',
        ).readAsString(),
        equals('skill payload'),
      );
    });
  });
}

class _ReleaseFixtureServer {
  _ReleaseFixtureServer._(this._server, this._assetName);

  final HttpServer _server;
  final String _assetName;

  Uri get releasesUri => Uri.parse('http://${_server.address.host}:'
      '${_server.port}/repos/leehack/mcp_dart/releases?per_page=50');

  static Future<_ReleaseFixtureServer> start(String assetName) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fixture = _ReleaseFixtureServer._(server, assetName);
    server.listen(fixture._handle);
    return fixture;
  }

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    final origin = 'http://${_server.address.host}:${_server.port}';
    if (request.uri.path == '/repos/leehack/mcp_dart/releases') {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(<Map<String, dynamic>>[
        <String, dynamic>{
          'tag_name': 'mcp_dart_cli-v10.0.0-dev.1',
          'prerelease': true,
          'assets': <Map<String, dynamic>>[],
        },
        <String, dynamic>{
          'tag_name': 'mcp_dart_cli-v9.9.9',
          'prerelease': false,
          'assets': <Map<String, dynamic>>[
            <String, dynamic>{
              'name': _assetName,
              'browser_download_url': '$origin/assets/$_assetName',
            },
            <String, dynamic>{
              'name': 'mcp-developer.SKILL.md',
              'browser_download_url': '$origin/assets/mcp-developer.SKILL.md',
            },
          ],
        },
      ]));
    } else if (request.uri.path == '/assets/$_assetName') {
      request.response.write('binary payload');
    } else if (request.uri.path == '/assets/mcp-developer.SKILL.md') {
      request.response.write('skill payload');
    } else {
      request.response.statusCode = HttpStatus.notFound;
      request.response.write('missing');
    }
    await request.response.close();
  }
}
