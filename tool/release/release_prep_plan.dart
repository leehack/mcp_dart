import 'dart:convert';

import 'release_link_manager.dart';

enum ReleaseChannel { dev, stable }

class ReleasePackageVersionChange {
  const ReleasePackageVersionChange({
    required this.package,
    required this.before,
    required this.after,
  });

  final ReleasePackage package;
  final String before;
  final String after;
}

class ReleasePrepPlan {
  const ReleasePrepPlan({
    required this.changes,
    required this.channel,
    required this.sdkVersion,
    required this.cliVersion,
  });

  final List<ReleasePackageVersionChange> changes;
  final ReleaseChannel channel;
  final String sdkVersion;
  final String cliVersion;

  List<String> get packageNames =>
      changes.map((change) => change.package.packageName).toList();

  String get packagesJson => jsonEncode(packageNames);

  static ReleasePrepPlan detect({
    required String baseSdkPubspec,
    required String headSdkPubspec,
    required String baseCliPubspec,
    required String headCliPubspec,
  }) {
    final baseSdk = ReleaseVersion.parse(
      _pubspecVersion(baseSdkPubspec, ReleasePackage.sdk),
    );
    final headSdk = ReleaseVersion.parse(
      _pubspecVersion(headSdkPubspec, ReleasePackage.sdk),
    );
    final baseCli = ReleaseVersion.parse(
      _pubspecVersion(baseCliPubspec, ReleasePackage.cli),
    );
    final headCli = ReleaseVersion.parse(
      _pubspecVersion(headCliPubspec, ReleasePackage.cli),
    );
    final changes = <ReleasePackageVersionChange>[];
    if (baseSdk.source != headSdk.source) {
      _requireIncreasing(ReleasePackage.sdk, baseSdk, headSdk);
      changes.add(
        ReleasePackageVersionChange(
          package: ReleasePackage.sdk,
          before: baseSdk.source,
          after: headSdk.source,
        ),
      );
    }
    if (baseCli.source != headCli.source) {
      _requireIncreasing(ReleasePackage.cli, baseCli, headCli);
      changes.add(
        ReleasePackageVersionChange(
          package: ReleasePackage.cli,
          before: baseCli.source,
          after: headCli.source,
        ),
      );
    }
    if (changes.isEmpty) {
      throw const FormatException(
        'A release-prep change must increase at least one package version.',
      );
    }
    final prereleaseStates = changes
        .map((change) => ReleaseVersion.parse(change.after).isPrerelease)
        .toSet();
    if (prereleaseStates.length != 1) {
      throw const FormatException(
        'A coordinated release-prep change cannot mix stable and dev versions.',
      );
    }
    return ReleasePrepPlan(
      changes: List.unmodifiable(changes),
      channel:
          prereleaseStates.single ? ReleaseChannel.dev : ReleaseChannel.stable,
      sdkVersion: headSdk.source,
      cliVersion: headCli.source,
    );
  }

  static void _requireIncreasing(
    ReleasePackage package,
    ReleaseVersion before,
    ReleaseVersion after,
  ) {
    if (after.compareTo(before) <= 0) {
      throw FormatException(
        '${package.packageName} version must increase from '
        '${before.source} to ${after.source}.',
      );
    }
  }
}

String _pubspecVersion(String source, ReleasePackage package) {
  final match = RegExp(
    r'^version:[ \t]*([^ \t\r\n]+)[ \t]*$',
    multiLine: true,
  ).firstMatch(source);
  if (match == null) {
    throw FormatException(
      '${package.packageName} pubspec has no top-level version.',
    );
  }
  return match.group(1)!;
}

/// Canonical package version parsing and ordering for release automation.
class ReleaseVersion implements Comparable<ReleaseVersion> {
  const ReleaseVersion._({
    required this.source,
    required this.major,
    required this.minor,
    required this.patch,
    required this.prerelease,
    required this.build,
  });

  static final _pattern = RegExp(
    r'^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)'
    r'(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?'
    r'(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$',
  );

  final String source;
  final int major;
  final int minor;
  final int patch;
  final List<String> prerelease;
  final List<String> build;

  bool get isPrerelease => prerelease.isNotEmpty;

  static ReleaseVersion parse(String value) {
    final match = _pattern.firstMatch(value);
    if (match == null) {
      throw FormatException('Invalid semantic version: $value.');
    }
    final prereleaseSource = match.group(4);
    final prerelease = prereleaseSource?.split('.') ?? const <String>[];
    final buildSource = match.group(5);
    final build = buildSource?.split('.') ?? const <String>[];
    for (final identifier in prerelease) {
      if (RegExp(r'^[0-9]+$').hasMatch(identifier) &&
          identifier.length > 1 &&
          identifier.startsWith('0')) {
        throw FormatException(
          'Invalid numeric prerelease identifier in $value.',
        );
      }
    }
    return ReleaseVersion._(
      source: value,
      major: int.parse(match.group(1)!),
      minor: int.parse(match.group(2)!),
      patch: int.parse(match.group(3)!),
      prerelease: List.unmodifiable(prerelease),
      build: List.unmodifiable(build),
    );
  }

  @override
  int compareTo(ReleaseVersion other) {
    for (final comparison in [
      major.compareTo(other.major),
      minor.compareTo(other.minor),
      patch.compareTo(other.patch),
    ]) {
      if (comparison != 0) {
        return comparison;
      }
    }
    final prereleaseComparison = switch ((isPrerelease, other.isPrerelease)) {
      (false, false) => 0,
      (false, true) => 1,
      (true, false) => -1,
      (true, true) => _compareIdentifiers(prerelease, other.prerelease),
    };
    if (prereleaseComparison != 0) {
      return prereleaseComparison;
    }
    return _compareIdentifiers(build, other.build);
  }

  static int _compareIdentifiers(List<String> left, List<String> right) {
    final sharedLength =
        left.length < right.length ? left.length : right.length;
    for (var index = 0; index < sharedLength; index += 1) {
      final leftIdentifier = left[index];
      final rightIdentifier = right[index];
      if (leftIdentifier == rightIdentifier) {
        continue;
      }
      final leftNumber = int.tryParse(leftIdentifier);
      final rightNumber = int.tryParse(rightIdentifier);
      if (leftNumber != null && rightNumber != null) {
        return leftNumber.compareTo(rightNumber);
      }
      if (leftNumber != null) {
        return -1;
      }
      if (rightNumber != null) {
        return 1;
      }
      return leftIdentifier.compareTo(rightIdentifier);
    }
    return left.length.compareTo(right.length);
  }
}
