import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mcp_dart_cli/src/version.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:pub_updater/pub_updater.dart';

const _repository = 'leehack/mcp_dart';
const _cliTagPrefix = 'mcp_dart_cli-v';
const _skillAssetName = 'mcp-developer.SKILL.md';

/// {@template update_command}
/// A command which updates the CLI.
/// {@endtemplate}
class UpdateCommand extends Command<int> {
  /// {@macro update_command}
  UpdateCommand({
    required Logger logger,
    PubUpdater? pubUpdater,
    GitHubBinaryUpdater? binaryUpdater,
  })  : _logger = logger,
        _pubUpdater = pubUpdater ?? PubUpdater(),
        _binaryUpdater = binaryUpdater ?? GitHubBinaryUpdater(logger: logger) {
    argParser.addOption(
      'install-dir',
      help:
          'Directory to install the standalone binary into. Defaults to the current binary directory for compiled executables.',
    );
  }

  final Logger _logger;
  final PubUpdater _pubUpdater;
  final GitHubBinaryUpdater _binaryUpdater;

  @override
  String get description => 'Update the CLI.';

  @override
  String get name => 'update';

  @override
  Future<int> run() async {
    if (isRunningAsStandaloneExecutable()) {
      return _binaryUpdater.update(
        currentVersion: packageVersion,
        installDir: argResults?['install-dir'] as String?,
      );
    }

    final updateCheckProgress = _logger.progress('Checking for updates');
    late final String latestVersion;
    try {
      latestVersion = await _pubUpdater.getLatestVersion('mcp_dart_cli');
    } catch (error) {
      updateCheckProgress.fail();
      _logger.err('$error');
      return ExitCode.software.code;
    }
    updateCheckProgress.complete('Checked for updates');

    final isUpToDate = packageVersion == latestVersion;
    if (isUpToDate) {
      _logger.info('CLI is already at the latest version.');
      return ExitCode.success.code;
    }

    final updateProgress = _logger.progress('Updating to $latestVersion');
    try {
      await _pubUpdater.update(packageName: 'mcp_dart_cli');
    } catch (error) {
      updateProgress.fail();
      _logger.err('$error');
      return ExitCode.software.code;
    }
    updateProgress.complete('Updated to $latestVersion');

    return ExitCode.success.code;
  }
}

/// Updates standalone GitHub release binaries.
class GitHubBinaryUpdater {
  /// Creates an updater for standalone binaries.
  GitHubBinaryUpdater({
    required Logger logger,
    HttpClient? httpClient,
    Uri? releasesUri,
  })  : _logger = logger,
        _httpClient = httpClient ?? HttpClient(),
        _releasesUri = releasesUri ??
            Uri.https(
              'api.github.com',
              '/repos/$_repository/releases',
              {'per_page': '50'},
            );

  final Logger _logger;
  final HttpClient _httpClient;
  final Uri _releasesUri;

  /// Updates the current standalone binary from the latest CLI GitHub release.
  Future<int> update({
    required String currentVersion,
    String? installDir,
  }) async {
    final platformAsset = releaseAssetNameForCurrentPlatform();
    if (platformAsset == null) {
      _logger.err(
        'Standalone binary updates are not available for ${Platform.operatingSystem}/${Platform.version}.',
      );
      return ExitCode.unavailable.code;
    }

    final checkProgress = _logger.progress('Checking GitHub releases');
    late final _ReleaseAsset asset;
    late final _ReleaseAsset? skillAsset;
    late final String latestVersion;
    try {
      final release = await _findLatestCliRelease();
      latestVersion = release.tag.substring(_cliTagPrefix.length);
      skillAsset = release.assetNamedOrNull(_skillAssetName);
      if (latestVersion == currentVersion) {
        checkProgress.complete('Checked GitHub releases');
        final targetSkill = _targetSkillFile(installDir);
        if (skillAsset != null && !targetSkill.existsSync()) {
          final skillProgress = _logger.progress('Installing bundled skill');
          try {
            await _downloadAsset(
              skillAsset.browserDownloadUrl,
              targetSkill,
            );
            skillProgress.complete('Installed bundled skill');
          } catch (error) {
            skillProgress.fail();
            _logger.err('$error');
            return ExitCode.software.code;
          }
        }
        _logger.info('CLI is already at the latest version.');
        return ExitCode.success.code;
      }
      asset = release.assetNamed(platformAsset);
    } catch (error) {
      checkProgress.fail();
      _logger.err('$error');
      return ExitCode.software.code;
    }
    checkProgress.complete('Checked GitHub releases');

    final target = _targetBinaryFile(installDir);
    if (Platform.isWindows &&
        p.equals(
          p.normalize(target.absolute.path),
          p.normalize(File(Platform.resolvedExecutable).absolute.path),
        )) {
      _logger.err(
        'Windows cannot replace the running executable in place. '
        'Run update with --install-dir pointing at a non-running install copy.',
      );
      return ExitCode.unavailable.code;
    }

    final updateProgress = _logger.progress('Updating to $latestVersion');
    try {
      await _downloadAsset(
        asset.browserDownloadUrl,
        target,
        executable: !Platform.isWindows,
      );
      if (skillAsset != null) {
        await _downloadAsset(
          skillAsset.browserDownloadUrl,
          _targetSkillFile(installDir),
        );
      }
      updateProgress.complete('Updated to $latestVersion');
      _logger.info('Installed ${target.path}');
      return ExitCode.success.code;
    } catch (error) {
      updateProgress.fail();
      _logger.err('$error');
      return ExitCode.software.code;
    }
  }

  Future<_CliRelease> _findLatestCliRelease() async {
    final releasesJson = await _getJson(_releasesUri);
    if (releasesJson is! List) {
      throw const FormatException('GitHub releases response was not a list.');
    }

    for (final releaseJson in releasesJson) {
      if (releaseJson is! Map<String, dynamic>) continue;
      final tag = releaseJson['tag_name'];
      final prerelease = releaseJson['prerelease'];
      if (tag is! String ||
          !tag.startsWith(_cliTagPrefix) ||
          prerelease == true) {
        continue;
      }

      final assetsJson = releaseJson['assets'];
      if (assetsJson is! List) {
        throw FormatException('GitHub release $tag did not include assets.');
      }
      final assets = assetsJson
          .whereType<Map<String, dynamic>>()
          .map(_ReleaseAsset.fromJson)
          .toList();
      return _CliRelease(tag: tag, assets: assets);
    }

    throw StateError('No stable $_cliTagPrefix GitHub release was found.');
  }

  Future<Object?> _getJson(Uri uri) async {
    final request = await _httpClient.getUrl(uri);
    request.headers
      ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
      ..set(HttpHeaders.userAgentHeader, 'mcp_dart_cli/$packageVersion');
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'GitHub API returned ${response.statusCode}: $body',
        uri: uri,
      );
    }
    return jsonDecode(body);
  }

  Future<void> _downloadAsset(
    Uri uri,
    File target, {
    bool executable = false,
  }) async {
    final request = await _httpClient.getUrl(uri);
    request.headers.set(
      HttpHeaders.userAgentHeader,
      'mcp_dart_cli/$packageVersion',
    );
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = await response.transform(utf8.decoder).join();
      throw HttpException(
        'Failed to download ${uri.pathSegments.last}: ${response.statusCode}: $body',
        uri: uri,
      );
    }

    target.parent.createSync(recursive: true);
    final tempFile = File('${target.path}.download');
    final sink = tempFile.openWrite();
    try {
      await response.pipe(sink);
    } finally {
      await sink.close();
    }

    if (executable) {
      final chmod = await Process.run('chmod', ['755', tempFile.path]);
      if (chmod.exitCode != 0) {
        throw ProcessException(
          'chmod',
          ['755', tempFile.path],
          '${chmod.stderr}',
          chmod.exitCode,
        );
      }
    }

    if (target.existsSync()) {
      final backup = File('${target.path}.bak');
      if (backup.existsSync()) {
        backup.deleteSync();
      }
      target.renameSync(backup.path);
      try {
        tempFile.renameSync(target.path);
        backup.deleteSync();
      } catch (_) {
        if (backup.existsSync() && !target.existsSync()) {
          backup.renameSync(target.path);
        }
        rethrow;
      }
    } else {
      tempFile.renameSync(target.path);
    }
  }

  File _targetBinaryFile(String? installDir) {
    if (installDir == null) {
      return File(Platform.resolvedExecutable);
    }
    return File(p.join(installDir, binaryExecutableName));
  }

  File _targetSkillFile(String? installDir) {
    final binaryDir =
        installDir ?? File(Platform.resolvedExecutable).parent.path;
    return File(
      p.normalize(
        p.join(
          binaryDir,
          '..',
          'share',
          'mcp_dart',
          'skills',
          'mcp-developer',
          'SKILL.md',
        ),
      ),
    );
  }
}

class _CliRelease {
  const _CliRelease({required this.tag, required this.assets});

  final String tag;
  final List<_ReleaseAsset> assets;

  _ReleaseAsset assetNamed(String name) {
    for (final asset in assets) {
      if (asset.name == name) return asset;
    }
    throw StateError('Release $tag does not include asset $name.');
  }

  _ReleaseAsset? assetNamedOrNull(String name) {
    for (final asset in assets) {
      if (asset.name == name) return asset;
    }
    return null;
  }
}

class _ReleaseAsset {
  const _ReleaseAsset({
    required this.name,
    required this.browserDownloadUrl,
  });

  factory _ReleaseAsset.fromJson(Map<String, dynamic> json) {
    final name = json['name'];
    final url = json['browser_download_url'];
    if (name is! String || url is! String) {
      throw const FormatException(
        'GitHub release asset is missing name or URL.',
      );
    }
    return _ReleaseAsset(name: name, browserDownloadUrl: Uri.parse(url));
  }

  final String name;
  final Uri browserDownloadUrl;
}

/// Returns true when the process is a compiled `mcp_dart` executable.
bool isRunningAsStandaloneExecutable({String? executablePath}) {
  final name = p.basename(executablePath ?? Platform.resolvedExecutable);
  return name == binaryExecutableName;
}

/// Name of the executable installed for this platform.
String get binaryExecutableName =>
    Platform.isWindows ? 'mcp_dart.exe' : 'mcp_dart';

/// GitHub release asset name for this host platform.
String? releaseAssetNameForCurrentPlatform() {
  final arch = _normalizedArchitecture();
  if (arch == null) return null;

  return releaseAssetNameForHost(
    operatingSystem: Platform.operatingSystem,
    architecture: arch,
  );
}

/// GitHub release asset name for a supported host tuple.
@visibleForTesting
String? releaseAssetNameForHost({
  required String operatingSystem,
  required String architecture,
}) =>
    switch ('$operatingSystem-$architecture') {
      'linux-x64' => 'mcp_dart-linux-x64',
      'macos-x64' => 'mcp_dart-macos-x64',
      'macos-arm64' => 'mcp_dart-macos-arm64',
      'windows-x64' => 'mcp_dart-windows-x64.exe',
      _ => null,
    };

String? _normalizedArchitecture() {
  final processor = Platform.environment['PROCESSOR_ARCHITECTURE']
      ?.toLowerCase()
      .replaceAll('amd64', 'x64');

  if (processor == 'x64' || processor == 'arm64') return processor;

  final version = Platform.version.toLowerCase();
  final executable = Platform.resolvedExecutable.toLowerCase();
  if (version.contains('arm64') || executable.contains('arm64')) {
    return 'arm64';
  }
  if (version.contains('x64') ||
      version.contains('x86_64') ||
      executable.contains('x64')) {
    return 'x64';
  }
  return null;
}
