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
  });
}
