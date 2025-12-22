import 'package:mason_logger/mason_logger.dart';
import 'package:pub_updater/pub_updater.dart';

import 'version.dart';

Future<void> checkForUpdate(Logger logger) async {
  try {
    final pubUpdater = PubUpdater();
    final isUpToDate = await pubUpdater.isUpToDate(
      packageName: 'mcp_dart_cli',
      currentVersion: packageVersion,
    );
    if (!isUpToDate) {
      final latestVersion = await pubUpdater.getLatestVersion('mcp_dart_cli');
      logger.info(
        'New version of mcp_dart_cli available! ($packageVersion -> $latestVersion)\n'
        'Run ${cyan.wrap('dart pub global activate mcp_dart_cli')} to update.',
      );
    }
  } catch (_) {
    // Suppress update check errors
  }
}
