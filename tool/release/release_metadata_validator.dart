import 'dart:convert';
import 'dart:io';

enum ReleasePackage {
  sdk('mcp_dart', 'v'),
  cli('mcp_dart_cli', 'mcp_dart_cli-v');

  const ReleasePackage(this.packageName, this.tagPrefix);

  final String packageName;
  final String tagPrefix;

  static ReleasePackage parse(String value) {
    for (final package in values) {
      if (package.packageName == value) {
        return package;
      }
    }
    throw FormatException('Unknown package: $value');
  }
}

class ReleaseMetadataValidation {
  const ReleaseMetadataValidation({
    required this.package,
    required this.version,
    required this.isPrerelease,
    required this.errors,
  });

  final ReleasePackage package;
  final String version;
  final bool isPrerelease;
  final List<String> errors;

  bool get isValid => errors.isEmpty;
}

class ReleaseMetadataValidator {
  ReleaseMetadataValidator(this.repoRoot);

  final Directory repoRoot;

  ReleaseMetadataValidation validate({
    required ReleasePackage package,
    String? tag,
  }) {
    final errors = <String>[];
    final manifest = _readJson(
      'tool/release/mcp_2026_07_28_release_metadata.json',
      errors,
    );
    final rootPubspec = _readText('pubspec.yaml', errors);
    final cliPubspec = _readText('packages/mcp_dart_cli/pubspec.yaml', errors);

    final sdkVersion = _yamlScalar(rootPubspec, 'version');
    final cliVersion = _yamlScalar(cliPubspec, 'version');
    final version = package == ReleasePackage.sdk ? sdkVersion : cliVersion;
    if (version == null || !_versionPattern.hasMatch(version)) {
      errors.add('${package.packageName} has an invalid or missing version.');
    }
    final effectiveVersion = version ?? '';
    final isPrerelease = effectiveVersion.contains('-');

    final expectedTag = '${package.tagPrefix}$effectiveVersion';
    if (tag != null && tag != expectedTag) {
      errors.add('Tag $tag does not match package metadata ($expectedTag).');
    }

    final sdkStableVersion = manifest['sdkStableVersion'];
    final cliStableVersion = manifest['cliStableVersion'];
    if (sdkStableVersion is! String || cliStableVersion is! String) {
      errors.add('Release metadata must declare stable SDK and CLI versions.');
    } else {
      final expectedBase =
          package == ReleasePackage.sdk ? sdkStableVersion : cliStableVersion;
      if (isPrerelease &&
          effectiveVersion.isNotEmpty &&
          !effectiveVersion.startsWith('$expectedBase-')) {
        errors.add(
          '${package.packageName} prereleases must use the $expectedBase line.',
        );
      }
      if (!isPrerelease &&
          effectiveVersion.isNotEmpty &&
          effectiveVersion != expectedBase) {
        errors.add(
          '${package.packageName} stable release must be $expectedBase; update '
          'the release manifest for a later release line.',
        );
      }
    }

    _validateProtocolConstants(manifest, isPrerelease, errors);
    _validatePinnedInputs(manifest, isPrerelease, errors);
    _validateReleaseDocumentation(manifest, isPrerelease, errors);
    _validatePackageMetadata(
      package: package,
      version: effectiveVersion,
      isPrerelease: isPrerelease,
      sdkVersion: sdkVersion,
      cliVersion: cliVersion,
      rootPubspec: rootPubspec,
      cliPubspec: cliPubspec,
      manifest: manifest,
      errors: errors,
    );
    if (!isPrerelease) {
      _validateStableDocumentation(package, manifest, errors);
    }

    return ReleaseMetadataValidation(
      package: package,
      version: effectiveVersion,
      isPrerelease: isPrerelease,
      errors: List.unmodifiable(errors),
    );
  }

  void _validateReleaseDocumentation(
    Map<String, Object?> manifest,
    bool isPrerelease,
    List<String> errors,
  ) {
    final documentation = manifest['releaseDocumentation'];
    if (documentation is! Map<String, Object?>) {
      errors.add('Release documentation metadata is incomplete.');
      return;
    }
    if (!isPrerelease && documentation['finalReleaseReviewed'] != true) {
      errors.add(
        'Stable release blocked: final release-facing documentation has not '
        'been reviewed and recorded.',
      );
    }
  }

  void _validateProtocolConstants(
    Map<String, Object?> manifest,
    bool isPrerelease,
    List<String> errors,
  ) {
    final protocolVersion = manifest['protocolVersion'];
    final legacyVersion = manifest['legacyInitializationProtocolVersion'];
    if (protocolVersion is! String || legacyVersion is! String) {
      errors
          .add('Release metadata must declare protocol compatibility values.');
      return;
    }

    final source = _readText('lib/src/types/json_rpc.dart', errors);
    final constants = _stringConstants(source);
    final resolvedPreview = _resolveStringConstant(
      'previewProtocolVersion',
      constants,
    );
    final resolvedDefault = _resolveStringConstant(
      'defaultProtocolVersion',
      constants,
    );
    final resolvedStable = _resolveStringConstant(
      'stableProtocolVersion',
      constants,
    );
    final resolvedLatestInitialization = _resolveStringConstant(
      'latestInitializationProtocolVersion',
      constants,
    );
    final resolvedLatestCompatibility = _resolveStringConstant(
      'latestProtocolVersion',
      constants,
    );

    if (resolvedPreview != protocolVersion ||
        resolvedDefault != protocolVersion) {
      errors.add(
        'previewProtocolVersion and defaultProtocolVersion must resolve to '
        '$protocolVersion.',
      );
    }
    if (resolvedLatestInitialization != legacyVersion ||
        resolvedLatestCompatibility != legacyVersion) {
      errors.add(
        'Initialization and deprecated latestProtocolVersion compatibility '
        'constants must remain at $legacyVersion.',
      );
    }
    if (!isPrerelease && resolvedStable != protocolVersion) {
      errors.add(
        'A stable release requires stableProtocolVersion to resolve to '
        '$protocolVersion.',
      );
    }
    if (!_constAliases(
      source,
      'supportedProtocolVersions',
      'legacyProtocolVersions',
    )) {
      errors.add(
        'supportedProtocolVersions must remain an alias of '
        'legacyProtocolVersions for backward compatibility.',
      );
    }
    if (!_listIncludes(source, 'allSupportedProtocolVersions', <String>[
      'defaultProtocolVersion',
      '...legacyProtocolVersions',
    ])) {
      errors.add(
        'allSupportedProtocolVersions must include the default protocol and '
        'all legacy initialization versions.',
      );
    }
    if (!_listStartsWith(
      source,
      'legacyProtocolVersions',
      'latestInitializationProtocolVersion',
    )) {
      errors.add(
        'legacyProtocolVersions must keep latestInitializationProtocolVersion '
        'as its preferred initialization version.',
      );
    }
    if (!_listIncludes(source, 'statelessProtocolVersions', <String>[
      'defaultProtocolVersion',
    ])) {
      errors.add(
        'statelessProtocolVersions must include defaultProtocolVersion.',
      );
    }
  }

  void _validatePinnedInputs(
    Map<String, Object?> manifest,
    bool isPrerelease,
    List<String> errors,
  ) {
    _validatePinnedInput(
      label: 'core specification',
      value: manifest['coreSpecification'],
      pinPath: 'tool/testing/mcp_2026_07_28_spec_ref.txt',
      requireFinalReview: !isPrerelease,
      errors: errors,
    );
    _validatePinnedInput(
      label: 'Tasks extension',
      value: manifest['tasksExtension'],
      pinPath: 'tool/testing/mcp_2026_07_28_tasks_spec_ref.txt',
      requireFinalReview: !isPrerelease,
      errors: errors,
    );
    if (!isPrerelease) {
      final tasks = manifest['tasksExtension'];
      if (tasks is Map<String, Object?>) {
        if (tasks['pinnedContentsReviewed'] != true) {
          errors.add(
            'Stable release blocked: the pinned Tasks checkout contents have '
            'not been audited against the SDK.',
          );
        }
        if (tasks['failedStateErrorShapeReviewed'] != true) {
          errors.add(
            'Stable release blocked: Tasks failed-state error prose and schema '
            'have not been reconciled with the SDK JsonRpcErrorData shape.',
          );
        }
        if (tasks['timingFieldIntegerSemanticsReviewed'] != true) {
          errors.add(
            'Stable release blocked: Tasks ttlMs and pollIntervalMs integer '
            'prose has not been reconciled with the number schema and SDK '
            'integer representation.',
          );
        }
      }
    }

    if (!isPrerelease) {
      final coreWorkflow = _readText('.github/workflows/test_core.yml', errors);
      _validateStableCoreAuditCommand(
        workflow: coreWorkflow,
        toolPath: 'tool/spec_example_audit.dart',
        expectedArgument: '.dart_tool/mcp-spec/schema/2026-07-28/examples',
        errors: errors,
      );
      _validateStableCoreAuditCommand(
        workflow: coreWorkflow,
        toolPath: 'tool/spec_document_inventory_audit.dart',
        expectedArgument: '.dart_tool/mcp-spec/docs/specification/2026-07-28',
        errors: errors,
      );
    }

    final capability = manifest['missingRequiredClientCapability'];
    if (capability is! Map<String, Object?>) {
      errors.add('Missing capability error-code release metadata.');
    } else {
      final declaredCode = capability['code'];
      final errorSource = _readText('lib/src/types/json_rpc.dart', errors);
      final match = RegExp(
        r'^\s*missingRequiredClientCapability\s*\(\s*(-?\d+)\s*\)\s*,',
        multiLine: true,
      ).firstMatch(_stripDartComments(errorSource));
      final implementationCode = int.tryParse(match?.group(1) ?? '');
      if (declaredCode is! int || implementationCode != declaredCode) {
        errors.add(
          'The release manifest capability error code must match the SDK '
          'implementation.',
        );
      }
      if (!isPrerelease && capability['finalTextsAgree'] != true) {
        errors.add(
          'Stable release blocked: final core and Tasks texts must agree on '
          'MissingRequiredClientCapability.',
        );
      }
    }

    final subscriptionTermination = manifest['subscriptionTermination'];
    if (subscriptionTermination is! Map<String, Object?>) {
      errors.add('Subscription termination release metadata is incomplete.');
    } else if (!isPrerelease &&
        subscriptionTermination['finalTextsAgree'] != true) {
      errors.add(
        'Stable release blocked: final cancellation and subscription texts '
        'must agree on server-initiated subscription termination.',
      );
    }

    final conformance = manifest['officialConformance'];
    if (conformance is! Map<String, Object?> ||
        conformance['version'] is! String ||
        (conformance['version'] as String).isEmpty) {
      errors.add('Official conformance release metadata is incomplete.');
    } else {
      final version = conformance['version'] as String;
      const conformanceWrappers = <String>[
        'test/conformance/run_2025_server_conformance.dart',
        'test/conformance/run_2026_07_28_server_conformance.dart',
        'test/conformance/run_2026_07_28_client_conformance.dart',
      ];
      final expectedPackage = '@modelcontextprotocol/conformance@$version';
      for (final path in conformanceWrappers) {
        final source = _readText(path, errors);
        final constants = _stringConstants(source);
        if (_resolveStringConstant('_defaultConformancePackage', constants) !=
            expectedPackage) {
          errors.add(
            '$path does not set _defaultConformancePackage to the conformance '
            'version declared in release metadata ($version).',
          );
        }
      }
      final coreWorkflow = _readText('.github/workflows/test_core.yml', errors);
      final activeWorkflowVersions = _activeNpxConformanceVersions(
        coreWorkflow,
      );
      if (activeWorkflowVersions.isEmpty ||
          activeWorkflowVersions.any((candidate) => candidate != version)) {
        errors.add(
          '.github/workflows/test_core.yml does not actively run only the '
          'conformance version declared in release metadata ($version).',
        );
      }
      if (!isPrerelease && conformance['finalReleaseReviewed'] != true) {
        errors.add(
          'Stable release blocked: the final official conformance package '
          'has not been reviewed and recorded.',
        );
      }
    }

    _validateInteropFixtures(manifest, isPrerelease, errors);
  }

  void _validateStableCoreAuditCommand({
    required String workflow,
    required String toolPath,
    required String expectedArgument,
    required List<String> errors,
  }) {
    final arguments = _activeDartRunArguments(workflow, toolPath);
    if (!arguments.contains(expectedArgument) ||
        arguments.any((argument) => argument != expectedArgument)) {
      errors.add(
        'Stable release blocked: Core CI must actively run dart run $toolPath '
        'with exactly $expectedArgument; comments and draft arguments do not '
        'satisfy this gate.',
      );
    }
  }

  void _validateInteropFixtures(
    Map<String, Object?> manifest,
    bool isPrerelease,
    List<String> errors,
  ) {
    final interop = manifest['publishedInteropFixtures'];
    if (interop is! Map<String, Object?>) {
      errors.add('Published interoperability release metadata is incomplete.');
      return;
    }
    final typescriptVersion = interop['typescript'];
    final pythonMcpVersion = interop['pythonMcp'];
    final pythonTypesVersion = interop['pythonMcpTypes'];
    if (typescriptVersion is! String ||
        pythonMcpVersion is! String ||
        pythonTypesVersion is! String) {
      errors.add('Published interoperability versions must be strings.');
      return;
    }

    final typescriptPackage = _readJson(
      'test/interop/ts_2026_07_28/package.json',
      errors,
    );
    final dependencies = typescriptPackage['dependencies'];
    if (dependencies is! Map<String, Object?> ||
        dependencies['@modelcontextprotocol/client'] != typescriptVersion ||
        dependencies['@modelcontextprotocol/server'] != typescriptVersion) {
      errors.add(
        'Published TypeScript interop dependencies must match release '
        'metadata ($typescriptVersion).',
      );
    }

    final pythonRequirements = _readText(
      'test/interop/python_2026_07_28/requirements.txt',
      errors,
    );
    final pythonMcpPins = _exactRequirementVersions(
      pythonRequirements,
      'mcp',
    );
    final pythonTypesPins = _exactRequirementVersions(
      pythonRequirements,
      'mcp-types',
    );
    if (pythonMcpPins.length != 1 ||
        pythonMcpPins.single != pythonMcpVersion ||
        pythonTypesPins.length != 1 ||
        pythonTypesPins.single != pythonTypesVersion) {
      errors.add(
        'Published Python interop dependencies must match release metadata.',
      );
    }

    if (!isPrerelease) {
      if (interop['finalReleaseReviewed'] != true) {
        errors.add(
          'Stable release blocked: final published TypeScript and Python '
          'interoperability fixtures have not been reviewed.',
        );
      }
      const gapSurfaces = <String>[
        '.github/workflows/interop_2026_07_28.yml',
        'doc/interoperability.md',
        'doc/mcp-2026-07-28-release-runbook.md',
        'test/interop/python_2026_07_28/README.md',
        'test/interop/ts_2026_07_28/README.md',
      ];
      for (final path in gapSurfaces) {
        final source = _readText(path, errors);
        if (source.contains('--expect-published-ts-client-gap') ||
            source.contains('--expect-published-python-client-gap')) {
          errors.add(
            'Stable release blocked: $path still expects a known published '
            '2026-07-28 client gap.',
          );
        }
      }
    }
  }

  void _validatePinnedInput({
    required String label,
    required Object? value,
    required String pinPath,
    required bool requireFinalReview,
    required List<String> errors,
  }) {
    if (value is! Map<String, Object?>) {
      errors.add('Missing $label release metadata.');
      return;
    }
    final ref = value['ref'];
    final pin = _readText(pinPath, errors).trim();
    if (ref is! String || !_shaPattern.hasMatch(ref) || pin != ref) {
      errors.add(
        'The $label release ref must be a 40-character SHA matching $pinPath.',
      );
    }
    if (requireFinalReview && value['finalReleaseReviewed'] != true) {
      errors.add(
        'Stable release blocked: the final $label ref has not been reviewed.',
      );
    }
  }

  void _validatePackageMetadata({
    required ReleasePackage package,
    required String version,
    required bool isPrerelease,
    required String? sdkVersion,
    required String? cliVersion,
    required String rootPubspec,
    required String cliPubspec,
    required Map<String, Object?> manifest,
    required List<String> errors,
  }) {
    final changelogPath = package == ReleasePackage.sdk
        ? 'CHANGELOG.md'
        : 'packages/mcp_dart_cli/CHANGELOG.md';
    final changelog = _readText(changelogPath, errors);
    final releaseSection =
        version.isEmpty ? null : _releaseSection(changelog, version);
    if (version.isNotEmpty && releaseSection == null) {
      errors.add('$changelogPath has no release heading for $version.');
    } else if (!isPrerelease &&
        releaseSection != null &&
        !_hasSubstantiveReleaseNotes(releaseSection)) {
      errors.add(
        '$changelogPath release section for $version has no substantive '
        'release notes.',
      );
    }

    if (package == ReleasePackage.sdk) {
      final documentation = _yamlScalar(rootPubspec, 'documentation');
      final expectedDocumentation = isPrerelease
          ? 'https://github.com/leehack/mcp_dart/tree/v$version/doc'
          : 'https://github.com/leehack/mcp_dart/tree/main/doc';
      if (documentation != expectedDocumentation) {
        errors.add(
          'SDK documentation metadata must be $expectedDocumentation.',
        );
      }
      return;
    }

    final cliVersionSource = _readText(
      'packages/mcp_dart_cli/lib/src/version.dart',
      errors,
    );
    final constants = _stringConstants(cliVersionSource);
    final packageVersion = _resolveStringConstant('packageVersion', constants);
    final generatedConstraint = _resolveStringConstant(
      'generatedSdkConstraint',
      constants,
    );
    final dependencyConstraint = _yamlIndentedScalar(
      cliPubspec,
      'mcp_dart',
    );
    if (packageVersion != cliVersion) {
      errors.add('CLI packageVersion must match its pubspec version.');
    }
    if (generatedConstraint != dependencyConstraint) {
      errors.add(
        'CLI generatedSdkConstraint must match its mcp_dart dependency.',
      );
    }
    final templatePubspec = _readText(
      'packages/templates/simple/__brick__/pubspec.yaml',
      errors,
    );
    final templateDependencyConstraint = _yamlIndentedScalar(
      templatePubspec,
      'mcp_dart',
    );
    if (templateDependencyConstraint != generatedConstraint) {
      errors.add(
        'CLI generatedSdkConstraint must match the simple template mcp_dart '
        'dependency.',
      );
    }

    final sdkStableVersion = manifest['sdkStableVersion'];
    if (!isPrerelease) {
      if (sdkStableVersion is! String || sdkVersion != sdkStableVersion) {
        errors.add(
          'Stable CLI release requires the coordinated stable SDK metadata.',
        );
      }
      if (generatedConstraint != '^$sdkStableVersion') {
        errors.add(
          'Stable CLI release must generate and depend on ^$sdkStableVersion.',
        );
      }
    }

    final expectedUrl = isPrerelease
        ? 'https://github.com/leehack/mcp_dart/tree/'
            'mcp_dart_cli-v$version/packages/mcp_dart_cli'
        : 'https://github.com/leehack/mcp_dart/tree/main/'
            'packages/mcp_dart_cli';
    if (_yamlScalar(cliPubspec, 'homepage') != expectedUrl ||
        _yamlScalar(cliPubspec, 'documentation') != expectedUrl) {
      errors.add(
        'CLI homepage and documentation metadata must be $expectedUrl.',
      );
    }
    const expectedTemplateUrl = r'https://github.com/leehack/mcp_dart/tree/'
        r'mcp_dart_cli-v$packageVersion/packages/templates/simple';
    if (_stringLiteralConstant(cliVersionSource, 'defaultTemplateUrl') !=
        expectedTemplateUrl) {
      errors.add(
        'CLI defaultTemplateUrl must use the immutable package release tag.',
      );
    }
  }

  String? _releaseSection(String changelog, String version) {
    final searchable = _stripMarkdownCommentsAndFences(changelog);
    final heading = RegExp(
      '^##[ \\t]+${RegExp.escape(version)}[ \\t]*\$',
      multiLine: true,
    ).firstMatch(searchable);
    if (heading == null) {
      return null;
    }

    final remainder = searchable.substring(heading.end);
    final nextHeading = RegExp(
      r'^##[ \t]+\S.*$',
      multiLine: true,
    ).firstMatch(remainder);
    final end = nextHeading == null
        ? searchable.length
        : heading.end + nextHeading.start;
    return searchable.substring(heading.end, end);
  }

  bool _hasSubstantiveReleaseNotes(String section) {
    final withoutComments = section.replaceAll(
      RegExp(r'<!--[\s\S]*?-->'),
      '',
    );
    const placeholders = <String>{
      'coming soon',
      'n/a',
      'none',
      'tbd',
      'todo',
      'unreleased',
    };
    for (final line in withoutComments.split('\n')) {
      var content = line.trim();
      if (content.isEmpty ||
          RegExp(r'^#{1,6}(?:[ \t]|$)').hasMatch(content) ||
          RegExp(r'^[-*_]{3,}$').hasMatch(content)) {
        continue;
      }
      content = content
          .replaceFirst(RegExp(r'^(?:[-*+]|\d+[.)])[ \t]+'), '')
          .replaceFirst(RegExp(r'^>[ \t]*'), '')
          .replaceAll(RegExp(r'[`*_~]'), '')
          .trim();
      final normalized =
          content.replaceFirst(RegExp(r'[.!?]+$'), '').trim().toLowerCase();
      if (normalized.isNotEmpty && !placeholders.contains(normalized)) {
        return true;
      }
    }
    return false;
  }

  void _validateStableDocumentation(
    ReleasePackage package,
    Map<String, Object?> manifest,
    List<String> errors,
  ) {
    final sdkVersion = manifest['sdkStableVersion'];
    final cliVersion = manifest['cliStableVersion'];
    if (sdkVersion is! String || cliVersion is! String) {
      return;
    }

    final paths = <String>{'README.md', 'llms.txt'};
    if (package == ReleasePackage.sdk) {
      paths
        ..addAll(_markdownFilesUnder('doc'))
        ..addAll(_markdownFilesUnder('example'))
        ..addAll(_dartFilesUnder('lib'));
    } else {
      paths
        ..addAll(_markdownFilesUnder('packages/mcp_dart_cli'))
        ..addAll(_markdownFilesUnder('packages/templates'))
        ..addAll(_dartFilesUnder('packages/mcp_dart_cli/lib'))
        ..add(
          'packages/mcp_dart_cli/test/fixtures/'
          'dart_mcp_project/pubspec.yaml',
        );
    }
    final forbiddenMarkers = <String>[
      '$sdkVersion-dev',
      if (package == ReleasePackage.cli) '$cliVersion-dev',
      '$sdkVersion preview',
      'mcp 2026-07-28 preview',
      'sdk preview:',
      'cli preview:',
      'release candidate for the mcp 2026-07-28 specification',
      'locked release-candidate',
      'pinned release-candidate specification',
      'the protocol is still a release candidate',
      'stableprotocolversion is 2025-11-25',
      'use stableprotocolversion for the official 2025-11-25',
      'modelcontextprotocol.io/specification/draft/',
      'for preview gates',
      'used by the sdk preview',
      'preferred by default in this sdk preview',
      'in the 2.3.0 preview',
      'specification is still a release candidate',
      'this preview prefers it by default',
    ];
    for (final path in paths.toList()..sort()) {
      final source = _readText(path, errors);
      final normalizedSource = source.replaceAll('`', '').toLowerCase();
      String? marker;
      for (final candidate in forbiddenMarkers) {
        if (normalizedSource.contains(candidate.toLowerCase())) {
          marker = candidate;
          break;
        }
      }
      if (marker != null) {
        errors.add(
          'Stable ${package.packageName} release documentation still contains '
          'stale release marker "$marker" in $path.',
        );
      }
    }
  }

  List<String> _markdownFilesUnder(String relativeRoot) {
    return _releaseFacingFilesUnder(
      relativeRoot,
      extension: '.md',
      excludedPaths: const {'doc/mcp-2026-07-28-release-runbook.md'},
      excludeChangelogs: true,
    );
  }

  List<String> _dartFilesUnder(String relativeRoot) {
    return _releaseFacingFilesUnder(relativeRoot, extension: '.dart');
  }

  List<String> _releaseFacingFilesUnder(
    String relativeRoot, {
    required String extension,
    Set<String> excludedPaths = const <String>{},
    bool excludeChangelogs = false,
  }) {
    final directory = Directory(_path(relativeRoot));
    if (!directory.existsSync()) {
      return const <String>[];
    }
    final rootPrefix = '${repoRoot.absolute.path}${Platform.pathSeparator}';
    const excludedSegments = <String>{
      '.dart_tool',
      '.git',
      'build',
      'coverage',
      'node_modules',
    };
    final paths = <String>[];
    for (final entity in directory.listSync(
      recursive: true,
      followLinks: false,
    )) {
      final absolutePath = entity.absolute.path;
      if (entity is! File ||
          !absolutePath.toLowerCase().endsWith(extension) ||
          !absolutePath.startsWith(rootPrefix)) {
        continue;
      }
      final relativePath = absolutePath
          .substring(rootPrefix.length)
          .replaceAll(Platform.pathSeparator, '/');
      final segments = relativePath.split('/');
      if (excludedPaths.contains(relativePath) ||
          segments.any(excludedSegments.contains) ||
          (excludeChangelogs &&
              segments.last.toLowerCase() == 'changelog.md')) {
        continue;
      }
      paths.add(relativePath);
    }
    paths.sort();
    return paths;
  }

  Map<String, Object?> _readJson(String path, List<String> errors) {
    final source = _readText(path, errors);
    if (source.isEmpty) {
      return <String, Object?>{};
    }
    try {
      final value = jsonDecode(source);
      if (value is Map<String, Object?>) {
        return value;
      }
    } on FormatException catch (error) {
      errors.add('$path is not valid JSON: ${error.message}');
      return <String, Object?>{};
    }
    errors.add('$path must contain a JSON object.');
    return <String, Object?>{};
  }

  String _readText(String path, List<String> errors) {
    final file = File(_path(path));
    if (!file.existsSync()) {
      errors.add('Missing release input: $path.');
      return '';
    }
    return file.readAsStringSync();
  }

  String _path(String relativePath) {
    return '${repoRoot.path}${Platform.pathSeparator}'
        '${relativePath.replaceAll('/', Platform.pathSeparator)}';
  }
}

const _versionPatternSource =
    r'^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$';
final RegExp _versionPattern = RegExp(_versionPatternSource);
final RegExp _shaPattern = RegExp(r'^[0-9a-f]{40}$');

String? _yamlScalar(String source, String key) {
  final match = RegExp(
    '^${RegExp.escape(key)}:[ \\t]*(.+?)[ \\t]*\$',
    multiLine: true,
  ).firstMatch(source);
  return _unquote(match?.group(1));
}

String? _yamlIndentedScalar(String source, String key) {
  final match = RegExp(
    '^[ \\t]+${RegExp.escape(key)}:[ \\t]*(.+?)[ \\t]*\$',
    multiLine: true,
  ).firstMatch(source);
  return _unquote(match?.group(1));
}

String? _unquote(String? value) {
  if (value == null) {
    return null;
  }
  final trimmed = value.trim();
  if (trimmed.length >= 2 &&
      ((trimmed.startsWith("'") && trimmed.endsWith("'")) ||
          (trimmed.startsWith('"') && trimmed.endsWith('"')))) {
    return trimmed.substring(1, trimmed.length - 1);
  }
  return trimmed;
}

Map<String, String> _stringConstants(String source) {
  final result = <String, String>{};
  final uncommented = _stripDartComments(source);
  final pattern = RegExp(
    r'''const(?:\s+String)?\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*'''
    r'''("[^"]*"|'[^']*'|[A-Za-z_][A-Za-z0-9_]*)\s*;''',
  );
  for (final match in pattern.allMatches(uncommented)) {
    result[match.group(1)!] = match.group(2)!;
  }
  return result;
}

String? _resolveStringConstant(
  String name,
  Map<String, String> constants, [
  Set<String>? seen,
]) {
  final expression = constants[name];
  if (expression == null) {
    return null;
  }
  if ((expression.startsWith('"') && expression.endsWith('"')) ||
      (expression.startsWith("'") && expression.endsWith("'"))) {
    return expression.substring(1, expression.length - 1);
  }
  final visited = seen ?? <String>{};
  if (!visited.add(name)) {
    return null;
  }
  return _resolveStringConstant(expression, constants, visited);
}

String? _stringLiteralConstant(String source, String name) {
  final uncommented = _stripDartComments(source);
  final declaration = RegExp(
    'const(?:\\s+String)?\\s+${RegExp.escape(name)}\\s*=\\s*'
    '''((?:(?:"[^"\\r\\n]*"|'[^'\\r\\n]*')\\s*)+);''',
  ).firstMatch(uncommented);
  final body = declaration?.group(1);
  if (body == null) {
    return null;
  }
  final result = StringBuffer();
  final fragments = RegExp(
    "\"[^\"\\r\\n]*\"|'[^'\\r\\n]*'",
  ).allMatches(body);
  for (final fragment in fragments) {
    final value = fragment.group(0)!.trim();
    result.write(value.substring(1, value.length - 1));
  }
  return result.toString();
}

bool _constAliases(String source, String name, String target) {
  final uncommented = _stripDartComments(source);
  return RegExp(
    'const(?:\\s+[A-Za-z0-9_<>?, ]+)?\\s+'
    '${RegExp.escape(name)}\\s*=\\s*${RegExp.escape(target)}\\s*;',
  ).hasMatch(uncommented);
}

bool _listIncludes(String source, String name, List<String> values) {
  final uncommented = _stripDartComments(source);
  final match = RegExp(
    'const\\s+${RegExp.escape(name)}\\s*=\\s*\\[([\\s\\S]*?)\\];',
  ).firstMatch(uncommented);
  final body = match?.group(1);
  return body != null && values.every(body.contains);
}

bool _listStartsWith(String source, String name, String value) {
  final uncommented = _stripDartComments(source);
  final match = RegExp(
    'const\\s+${RegExp.escape(name)}\\s*=\\s*\\[\\s*'
    '${RegExp.escape(value)}(?:\\s*,|\\s*\\])',
  ).firstMatch(uncommented);
  return match != null;
}

List<String> _activeDartRunArguments(String workflow, String toolPath) {
  final arguments = <String>[];
  final command = RegExp(
    '(?:^|\\n|;|&&|\\|\\|)[ \\t]*dart[ \\t]+run[ \\t]+'
    '${_portableCommandPathPattern(toolPath)}[ \\t\\r\\n]+'
    r'''("[^"\r\n]*"|'[^'\r\n]*'|[^\s;&|]+)''',
  );
  for (final script in _yamlRunScripts(workflow)) {
    final uncommented = _stripShellComments(script);
    for (final match in command.allMatches(uncommented)) {
      arguments.add(
        (_unquote(match.group(1)) ?? '').replaceAll(r'\', '/'),
      );
    }
  }
  return arguments;
}

String _portableCommandPathPattern(String path) =>
    path.split('/').map(RegExp.escape).join(r'[/\\]');

List<String> _activeNpxConformanceVersions(String workflow) {
  final versions = <String>[];
  final command = RegExp(
    r'''(?:^|\n|;|&&|\|\|)[ \t]*npx(?:[ \t]+-[^\s;&|]+)*[ \t]+'''
    r'''(?:"|')?@modelcontextprotocol/conformance@([^"'\s;&|]+)'''
    r'''(?:"|')?''',
  );
  for (final script in _yamlRunScripts(workflow)) {
    final uncommented = _stripShellComments(script);
    for (final match in command.allMatches(uncommented)) {
      versions.add(match.group(1)!);
    }
  }
  return versions;
}

List<String> _exactRequirementVersions(String source, String packageName) {
  final pins = <String>[];
  final requirement = RegExp(
    '^${RegExp.escape(packageName)}[ \\t]*==[ \\t]*([^\\s;#]+)[ \\t]*\$',
    caseSensitive: false,
  );
  for (final line in source.split('\n')) {
    final active = line.split('#').first.trim();
    final match = requirement.firstMatch(active);
    if (match != null) {
      pins.add(match.group(1)!);
    }
  }
  return pins;
}

List<String> _yamlRunScripts(String source) {
  final scripts = <String>[];
  final lines = const LineSplitter().convert(source);
  final runKey = RegExp(r'^([ ]*)run:[ \t]*(.*)$');
  final blockIndicator = RegExp(r'^[>|][+-]?(?:[ \t]+#.*)?$');

  for (var index = 0; index < lines.length; index += 1) {
    final match = runKey.firstMatch(lines[index]);
    if (match == null) {
      continue;
    }
    final value = match.group(2)!.trim();
    if (!blockIndicator.hasMatch(value)) {
      scripts.add(_unquote(value) ?? '');
      continue;
    }

    final parentIndent = match.group(1)!.length;
    final block = <String>[];
    var next = index + 1;
    while (next < lines.length) {
      final line = lines[next];
      if (line.trim().isEmpty) {
        block.add('');
        next += 1;
        continue;
      }
      final indent = line.length - line.trimLeft().length;
      if (indent <= parentIndent) {
        break;
      }
      block.add(line);
      next += 1;
    }
    scripts.add(block.join('\n'));
    index = next - 1;
  }
  return scripts;
}

String _stripShellComments(String source) {
  final result = StringBuffer();
  var inSingleQuote = false;
  var inDoubleQuote = false;
  var escaped = false;

  for (var index = 0; index < source.length; index += 1) {
    final character = source[index];
    if (escaped) {
      result.write(character);
      escaped = false;
      continue;
    }
    if (character == r'\' && !inSingleQuote) {
      result.write(character);
      escaped = true;
      continue;
    }
    if (character == "'" && !inDoubleQuote) {
      inSingleQuote = !inSingleQuote;
      result.write(character);
      continue;
    }
    if (character == '"' && !inSingleQuote) {
      inDoubleQuote = !inDoubleQuote;
      result.write(character);
      continue;
    }
    final startsComment = character == '#' &&
        !inSingleQuote &&
        !inDoubleQuote &&
        (index == 0 || source[index - 1].trim().isEmpty);
    if (!startsComment) {
      result.write(character);
      continue;
    }
    while (index + 1 < source.length && source[index + 1] != '\n') {
      index += 1;
    }
  }
  return result.toString();
}

String _stripMarkdownCommentsAndFences(String source) {
  final withoutComments = source.replaceAll(
    RegExp(r'<!--[\s\S]*?-->'),
    '',
  );
  final result = StringBuffer();
  String? fenceCharacter;
  var minimumFenceLength = 0;
  final fence = RegExp(r'^[ \t]*(`{3,}|~{3,})');

  for (final line in withoutComments.split('\n')) {
    final fenceMatch = fence.firstMatch(line);
    final marker = fenceMatch?.group(1);
    if (fenceCharacter == null) {
      if (marker == null) {
        result.writeln(line);
      } else {
        fenceCharacter = marker[0];
        minimumFenceLength = marker.length;
        result.writeln();
      }
      continue;
    }
    if (marker != null &&
        marker[0] == fenceCharacter &&
        marker.length >= minimumFenceLength &&
        line.substring(fenceMatch!.end).trim().isEmpty) {
      fenceCharacter = null;
      minimumFenceLength = 0;
    }
    result.writeln();
  }
  return result.toString();
}

String _stripDartComments(String source) {
  final result = StringBuffer();
  var state = _DartScanState.code;
  var escaped = false;
  var blockDepth = 0;

  bool startsWithAt(String value, int index) =>
      index + value.length <= source.length &&
      source.substring(index, index + value.length) == value;

  for (var index = 0; index < source.length; index += 1) {
    final character = source[index];
    switch (state) {
      case _DartScanState.lineComment:
        if (character == '\n') {
          state = _DartScanState.code;
          result.write('\n');
        } else {
          result.write(' ');
        }
        continue;
      case _DartScanState.blockComment:
        if (startsWithAt('/*', index)) {
          blockDepth += 1;
          result.write('  ');
          index += 1;
        } else if (startsWithAt('*/', index)) {
          blockDepth -= 1;
          result.write('  ');
          index += 1;
          if (blockDepth == 0) {
            state = _DartScanState.code;
          }
        } else {
          result.write(character == '\n' ? '\n' : ' ');
        }
        continue;
      case _DartScanState.singleQuote:
      case _DartScanState.doubleQuote:
        result.write(character);
        if (escaped) {
          escaped = false;
        } else if (character == r'\') {
          escaped = true;
        } else if ((state == _DartScanState.singleQuote && character == "'") ||
            (state == _DartScanState.doubleQuote && character == '"')) {
          state = _DartScanState.code;
        }
        continue;
      case _DartScanState.tripleSingleQuote:
      case _DartScanState.tripleDoubleQuote:
        final delimiter =
            state == _DartScanState.tripleSingleQuote ? "'''" : '"""';
        if (!escaped && startsWithAt(delimiter, index)) {
          result.write(delimiter);
          index += 2;
          state = _DartScanState.code;
          continue;
        }
        result.write(character);
        if (escaped) {
          escaped = false;
        } else if (character == r'\') {
          escaped = true;
        }
        continue;
      case _DartScanState.code:
        if (startsWithAt('//', index)) {
          state = _DartScanState.lineComment;
          result.write('  ');
          index += 1;
        } else if (startsWithAt('/*', index)) {
          state = _DartScanState.blockComment;
          blockDepth = 1;
          result.write('  ');
          index += 1;
        } else if (startsWithAt("'''", index)) {
          state = _DartScanState.tripleSingleQuote;
          result.write("'''");
          index += 2;
        } else if (startsWithAt('"""', index)) {
          state = _DartScanState.tripleDoubleQuote;
          result.write('"""');
          index += 2;
        } else if (character == "'") {
          state = _DartScanState.singleQuote;
          escaped = false;
          result.write(character);
        } else if (character == '"') {
          state = _DartScanState.doubleQuote;
          escaped = false;
          result.write(character);
        } else {
          result.write(character);
        }
        continue;
    }
  }
  return result.toString();
}

enum _DartScanState {
  code,
  lineComment,
  blockComment,
  singleQuote,
  doubleQuote,
  tripleSingleQuote,
  tripleDoubleQuote,
}
