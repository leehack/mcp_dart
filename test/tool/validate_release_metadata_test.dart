import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../tool/release/release_metadata_validator.dart';

void main() {
  final repoRoot = Directory.current.absolute;

  test('accepts coordinated SDK and CLI prerelease metadata', () {
    final validator = ReleaseMetadataValidator(repoRoot);

    final sdk = validator.validate(
      package: ReleasePackage.sdk,
      tag: 'v2.3.0-dev.2',
    );
    final cli = validator.validate(
      package: ReleasePackage.cli,
      tag: 'mcp_dart_cli-v0.2.0-dev.2',
    );

    expect(sdk.errors, isEmpty);
    expect(cli.errors, isEmpty);
    expect(sdk.isPrerelease, isTrue);
    expect(cli.isPrerelease, isTrue);
  });

  test('rejects a tag that does not match package metadata', () {
    final result = ReleaseMetadataValidator(repoRoot).validate(
      package: ReleasePackage.sdk,
      tag: 'v2.3.0',
    );

    expect(
      result.errors,
      contains(contains('does not match package metadata')),
    );
  });

  test('blocks stable publishing until final inputs are acknowledged', () {
    final fixture = _stableFixture(repoRoot, finalInputsReviewed: false);
    addTearDown(() => fixture.deleteSync(recursive: true));

    final result = ReleaseMetadataValidator(fixture).validate(
      package: ReleasePackage.sdk,
      tag: 'v2.3.0',
    );

    expect(result.isPrerelease, isFalse);
    expect(
      result.errors,
      contains(contains('final core specification ref has not been reviewed')),
    );
    expect(
      result.errors,
      contains(contains('final core and Tasks texts must agree')),
    );
    expect(
      result.errors,
      contains(contains('pinned Tasks checkout contents')),
    );
    expect(
      result.errors,
      contains(contains('Tasks failed-state error prose and schema')),
    );
    expect(
      result.errors,
      contains(contains('Tasks ttlMs and pollIntervalMs integer prose')),
    );
    expect(
      result.errors,
      contains(contains('server-initiated subscription termination')),
    );
    expect(
      result.errors,
      contains(contains('release-facing documentation has not been reviewed')),
    );
    expect(
      result.errors,
      contains(contains('interoperability fixtures have not been reviewed')),
    );
  });

  test('accepts stable SDK metadata after every day-of gate is recorded', () {
    final fixture = _stableFixture(repoRoot, finalInputsReviewed: true);
    addTearDown(() => fixture.deleteSync(recursive: true));

    final result = ReleaseMetadataValidator(fixture).validate(
      package: ReleasePackage.sdk,
      tag: 'v2.3.0',
    );

    expect(result.errors, isEmpty);
    expect(result.isPrerelease, isFalse);
  });

  test('rejects a published-client gap allowance on any release surface', () {
    final fixture = _stableFixture(repoRoot, finalInputsReviewed: true);
    addTearDown(() => fixture.deleteSync(recursive: true));
    final interoperability = File(
      '${fixture.path}/doc/interoperability.md',
    );
    interoperability.writeAsStringSync(
      '${interoperability.readAsStringSync()}\n'
      'dart run tool/testing/run_python_2026_07_28_interop.dart '
      '--expect-published-python-client-gap\n',
    );

    final result = ReleaseMetadataValidator(fixture).validate(
      package: ReleasePackage.sdk,
      tag: 'v2.3.0',
    );

    expect(
      result.errors,
      contains(
        allOf(
          contains('known published 2026-07-28 client gap'),
          contains('doc/interoperability.md'),
        ),
      ),
    );
  });

  test('dated Core audit comments cannot hide active draft arguments', () {
    final fixture = _stableFixture(repoRoot, finalInputsReviewed: true);
    addTearDown(() => fixture.deleteSync(recursive: true));
    final workflow = File(
      '${fixture.path}/.github/workflows/test_core.yml',
    );
    final draftWorkflow = workflow
        .readAsStringSync()
        .replaceFirst(
          '.dart_tool/mcp-spec/schema/2026-07-28/examples',
          '.dart_tool/mcp-spec/schema/draft/examples',
        )
        .replaceFirst(
          '.dart_tool/mcp-spec/docs/specification/2026-07-28',
          '.dart_tool/mcp-spec/docs/specification/draft',
        );
    workflow.writeAsStringSync(
      '$draftWorkflow\n'
      '# .dart_tool/mcp-spec/schema/2026-07-28/examples\n'
      '# .dart_tool/mcp-spec/docs/specification/2026-07-28\n',
    );

    final result = ReleaseMetadataValidator(fixture).validate(
      package: ReleasePackage.sdk,
      tag: 'v2.3.0',
    );

    expect(
      result.errors,
      contains(contains('tool/spec_example_audit.dart')),
    );
    expect(
      result.errors,
      contains(contains('tool/spec_document_inventory_audit.dart')),
    );
  });

  test('rejects an active draft audit beside the required dated audit', () {
    final fixture = _stableFixture(repoRoot, finalInputsReviewed: true);
    addTearDown(() => fixture.deleteSync(recursive: true));
    final workflow = File(
      '${fixture.path}/.github/workflows/test_core.yml',
    );
    workflow.writeAsStringSync(
      workflow.readAsStringSync().replaceFirst(
            '.dart_tool/mcp-spec/schema/2026-07-28/examples',
            '.dart_tool/mcp-spec/schema/2026-07-28/examples;\n'
                '          dart run tool/spec_example_audit.dart\n'
                '          .dart_tool/mcp-spec/schema/draft/examples',
          ),
    );

    final result = ReleaseMetadataValidator(fixture).validate(
      package: ReleasePackage.sdk,
      tag: 'v2.3.0',
    );

    expect(
      result.errors,
      contains(contains('tool/spec_example_audit.dart')),
    );
  });

  test('accepts coordinated stable CLI metadata after the SDK promotion', () {
    final fixture = _stableFixture(
      repoRoot,
      finalInputsReviewed: true,
      prepareStableCli: true,
    );
    addTearDown(() => fixture.deleteSync(recursive: true));

    final result = ReleaseMetadataValidator(fixture).validate(
      package: ReleasePackage.cli,
      tag: 'mcp_dart_cli-v0.2.0',
    );

    expect(result.errors, isEmpty);
    expect(result.isPrerelease, isFalse);
  });

  test('rejects stale prerelease instructions in the published CLI example',
      () {
    final fixture = _stableFixture(
      repoRoot,
      finalInputsReviewed: true,
      prepareStableCli: true,
    );
    addTearDown(() => fixture.deleteSync(recursive: true));
    final example = File(
      '${fixture.path}/packages/mcp_dart_cli/example/example.md',
    );
    example.writeAsStringSync(
      '${example.readAsStringSync()}\n'
      'dart pub global activate mcp_dart_cli 0.2.0-dev.2\n',
    );

    final result = ReleaseMetadataValidator(fixture).validate(
      package: ReleasePackage.cli,
      tag: 'mcp_dart_cli-v0.2.0',
    );

    expect(
      result.errors,
      contains(
        allOf(
          contains('stale release marker'),
          contains('packages/mcp_dart_cli/example/example.md'),
        ),
      ),
    );
  });

  test('rejects a stale preview claim after documentation acknowledgement', () {
    final fixture = _stableFixture(repoRoot, finalInputsReviewed: true);
    addTearDown(() => fixture.deleteSync(recursive: true));
    final readme = File('${fixture.path}/README.md');
    readme.writeAsStringSync(
      '${readme.readAsStringSync()}\nThe 2.3.0 preview is ready.\n',
    );

    final result = ReleaseMetadataValidator(fixture).validate(
      package: ReleasePackage.sdk,
      tag: 'v2.3.0',
    );

    expect(
      result.errors,
      contains(contains('stale release marker')),
    );
  });

  test('rejects a stale preview-gate claim in the legacy coverage matrix', () {
    final fixture = _stableFixture(repoRoot, finalInputsReviewed: true);
    addTearDown(() => fixture.deleteSync(recursive: true));
    final coverage = File(
      '${fixture.path}/doc/spec-coverage-2025-11-25.md',
    );
    coverage.writeAsStringSync(
      '${coverage.readAsStringSync()}\n'
      'See the modern matrix for preview gates.\n',
    );

    final result = ReleaseMetadataValidator(fixture).validate(
      package: ReleasePackage.sdk,
      tag: 'v2.3.0',
    );

    expect(
      result.errors,
      contains(
        allOf(
          contains('stale release marker'),
          contains('doc/spec-coverage-2025-11-25.md'),
        ),
      ),
    );
  });

  test('rejects a commented conformance wrapper version decoy', () {
    final fixture = _stableFixture(repoRoot, finalInputsReviewed: true);
    addTearDown(() => fixture.deleteSync(recursive: true));
    final wrapper = File(
      '${fixture.path}/test/conformance/run_2025_server_conformance.dart',
    );
    final staleWrapper = wrapper.readAsStringSync().replaceFirst(
          'conformance@0.2.0-alpha.9',
          'conformance@0.2.0-alpha.8',
        );
    wrapper.writeAsStringSync(
      '$staleWrapper\n'
      '// @modelcontextprotocol/conformance@0.2.0-alpha.9\n',
    );

    final result = ReleaseMetadataValidator(fixture).validate(
      package: ReleasePackage.sdk,
      tag: 'v2.3.0',
    );

    expect(
      result.errors,
      contains(contains('run_2025_server_conformance.dart')),
    );
  });

  test('rejects a commented Core CI conformance version decoy', () {
    final fixture = _stableFixture(repoRoot, finalInputsReviewed: true);
    addTearDown(() => fixture.deleteSync(recursive: true));
    final workflow = File(
      '${fixture.path}/.github/workflows/test_core.yml',
    );
    final staleWorkflow = workflow.readAsStringSync().replaceFirst(
          'conformance@0.2.0-alpha.9',
          'conformance@0.2.0-alpha.8',
        );
    workflow.writeAsStringSync(
      '$staleWorkflow\n'
      '# npx -y @modelcontextprotocol/conformance@0.2.0-alpha.9 client\n',
    );

    final result = ReleaseMetadataValidator(fixture).validate(
      package: ReleasePackage.sdk,
      tag: 'v2.3.0',
    );

    expect(
      result.errors,
      contains(contains('.github/workflows/test_core.yml does not actively')),
    );
  });

  test('rejects a commented protocol constant decoy', () {
    final fixture = _stableFixture(repoRoot, finalInputsReviewed: true);
    addTearDown(() => fixture.deleteSync(recursive: true));
    final constants = File(
      '${fixture.path}/lib/src/types/json_rpc.dart',
    );
    constants.writeAsStringSync(
      constants.readAsStringSync().replaceFirst(
            'const stableProtocolVersion = previewProtocolVersion;',
            'const stableProtocolVersion = latestInitializationProtocolVersion;\n'
                '// const stableProtocolVersion = previewProtocolVersion;',
          ),
    );

    final result = ReleaseMetadataValidator(fixture).validate(
      package: ReleasePackage.sdk,
      tag: 'v2.3.0',
    );

    expect(
      result.errors,
      contains(contains('stableProtocolVersion')),
    );
  });

  test('rejects commented published Python dependency decoys', () {
    final fixture = _stableFixture(repoRoot, finalInputsReviewed: true);
    addTearDown(() => fixture.deleteSync(recursive: true));
    final requirements = File(
      '${fixture.path}/test/interop/python_2026_07_28/requirements.txt',
    );
    requirements.writeAsStringSync('''
mcp==2.0.0b1
mcp-types==2.0.0b1
# mcp==2.0.0b2
# mcp-types==2.0.0b2
''');

    final result = ReleaseMetadataValidator(fixture).validate(
      package: ReleasePackage.sdk,
      tag: 'v2.3.0',
    );

    expect(
      result.errors,
      contains(contains('Published Python interop dependencies')),
    );
  });

  test('rejects a commented capability error-code decoy', () {
    final fixture = _stableFixture(repoRoot, finalInputsReviewed: true);
    addTearDown(() => fixture.deleteSync(recursive: true));
    final errors = File('${fixture.path}/lib/src/types/json_rpc.dart');
    errors.writeAsStringSync(
      errors.readAsStringSync().replaceFirst(
            'missingRequiredClientCapability(-32021),',
            '// missingRequiredClientCapability(-32021),\n'
                '  missingRequiredClientCapability(-32022),',
          ),
    );

    final result = ReleaseMetadataValidator(fixture).validate(
      package: ReleasePackage.sdk,
      tag: 'v2.3.0',
    );

    expect(
      result.errors,
      contains(contains('capability error code must match')),
    );
  });

  test('rejects a stable changelog heading hidden in an HTML comment', () {
    final fixture = _stableFixture(repoRoot, finalInputsReviewed: true);
    addTearDown(() => fixture.deleteSync(recursive: true));
    File('${fixture.path}/CHANGELOG.md').writeAsStringSync('''
<!--
## 2.3.0

- Commented release notes.
-->

## Unreleased

- The actual release notes are still unreleased.
''');

    final result = ReleaseMetadataValidator(fixture).validate(
      package: ReleasePackage.sdk,
      tag: 'v2.3.0',
    );

    expect(
      result.errors,
      contains(contains('has no release heading for 2.3.0')),
    );
  });

  test('rejects a stable changelog heading hidden in a code fence', () {
    final fixture = _stableFixture(repoRoot, finalInputsReviewed: true);
    addTearDown(() => fixture.deleteSync(recursive: true));
    File('${fixture.path}/CHANGELOG.md').writeAsStringSync('''
```markdown
## 2.3.0

- Example release notes.
```

## Unreleased

- The actual release notes are still unreleased.
''');

    final result = ReleaseMetadataValidator(fixture).validate(
      package: ReleasePackage.sdk,
      tag: 'v2.3.0',
    );

    expect(
      result.errors,
      contains(contains('has no release heading for 2.3.0')),
    );
  });

  test('scans newly added release-facing Markdown deterministically', () {
    final fixture = _stableFixture(repoRoot, finalInputsReviewed: true);
    addTearDown(() => fixture.deleteSync(recursive: true));
    File('${fixture.path}/doc/new-release-guide.md').writeAsStringSync(
      'The MCP 2026-07-28 preview is ready.\n',
    );

    final result = ReleaseMetadataValidator(fixture).validate(
      package: ReleasePackage.sdk,
      tag: 'v2.3.0',
    );

    expect(
      result.errors,
      contains(
        allOf(
          contains('stale release marker'),
          contains('doc/new-release-guide.md'),
        ),
      ),
    );
  });

  test('rejects a stale generated-project SDK dependency', () {
    final fixture = _stableFixture(
      repoRoot,
      finalInputsReviewed: true,
      prepareStableCli: true,
    );
    addTearDown(() => fixture.deleteSync(recursive: true));
    final template = File(
      '${fixture.path}/packages/templates/simple/__brick__/pubspec.yaml',
    );
    template.writeAsStringSync(
      template.readAsStringSync().replaceFirst(
            'mcp_dart: ^2.3.0',
            'mcp_dart: ^2.3.0-dev.2',
          ),
    );

    final result = ReleaseMetadataValidator(fixture).validate(
      package: ReleasePackage.cli,
      tag: 'mcp_dart_cli-v0.2.0',
    );

    expect(
      result.errors,
      contains(contains('simple template mcp_dart dependency')),
    );
  });

  test('rejects a commented CLI template URL decoy', () {
    final fixture = _stableFixture(
      repoRoot,
      finalInputsReviewed: true,
      prepareStableCli: true,
    );
    addTearDown(() => fixture.deleteSync(recursive: true));
    final versionSource = File(
      '${fixture.path}/packages/mcp_dart_cli/lib/src/version.dart',
    );
    final staleVersionSource = versionSource.readAsStringSync().replaceFirst(
          "'mcp_dart_cli-v\$packageVersion/packages/templates/simple'",
          "'packages/templates/simple'",
        );
    versionSource.writeAsStringSync(
      '$staleVersionSource\n'
      '// mcp_dart_cli-v\$packageVersion/packages/templates/simple\n',
    );

    final result = ReleaseMetadataValidator(fixture).validate(
      package: ReleasePackage.cli,
      tag: 'mcp_dart_cli-v0.2.0',
    );

    expect(
      result.errors,
      contains(contains('defaultTemplateUrl')),
    );
  });

  test('rejects stable SDK metadata with an empty release section', () {
    final fixture = _stableFixture(repoRoot, finalInputsReviewed: true);
    addTearDown(() => fixture.deleteSync(recursive: true));
    File('${fixture.path}/CHANGELOG.md').writeAsStringSync('''
## 2.3.0

<!-- Notes were not promoted. -->

### Changed

TBD

## Unreleased

- The actual release notes are still here.
''');

    final result = ReleaseMetadataValidator(fixture).validate(
      package: ReleasePackage.sdk,
      tag: 'v2.3.0',
    );

    expect(
      result.errors,
      contains(contains('has no substantive release notes')),
    );
  });

  test('rejects stable CLI metadata with an empty release section', () {
    final fixture = _stableFixture(
      repoRoot,
      finalInputsReviewed: true,
      prepareStableCli: true,
    );
    addTearDown(() => fixture.deleteSync(recursive: true));
    File('${fixture.path}/packages/mcp_dart_cli/CHANGELOG.md')
        .writeAsStringSync('''
## 0.2.0

### Changed

TODO

## Unreleased

- The actual CLI release notes are still here.
''');

    final result = ReleaseMetadataValidator(fixture).validate(
      package: ReleasePackage.cli,
      tag: 'mcp_dart_cli-v0.2.0',
    );

    expect(
      result.errors,
      contains(contains('has no substantive release notes')),
    );
  });
}

Directory _stableFixture(
  Directory repoRoot, {
  required bool finalInputsReviewed,
  bool prepareStableCli = false,
}) {
  final fixture = Directory.systemTemp.createTempSync(
    'mcp_dart_release_metadata_',
  );
  const paths = <String>[
    '.github/workflows/test_core.yml',
    '.github/workflows/interop_2026_07_28.yml',
    'CHANGELOG.md',
    'README.md',
    'doc/client-guide.md',
    'doc/getting-started.md',
    'doc/interoperability.md',
    'doc/mcp-2026-07-28-release-runbook.md',
    'doc/mcp-2026-07-28.md',
    'doc/quick-reference.md',
    'doc/server-guide.md',
    'doc/spec-coverage-2025-11-25.md',
    'doc/spec-coverage-2026-07-28.md',
    'example/example.md',
    'lib/src/types/json_rpc.dart',
    'llms.txt',
    'packages/mcp_dart_cli/CHANGELOG.md',
    'packages/mcp_dart_cli/README.md',
    'packages/mcp_dart_cli/example/example.md',
    'packages/mcp_dart_cli/lib/src/version.dart',
    'packages/mcp_dart_cli/pubspec.yaml',
    'packages/mcp_dart_cli/test/fixtures/dart_mcp_project/pubspec.yaml',
    'packages/templates/simple/__brick__/pubspec.yaml',
    'pubspec.yaml',
    'test/conformance/run_2025_server_conformance.dart',
    'test/conformance/run_2026_07_28_client_conformance.dart',
    'test/conformance/run_2026_07_28_server_conformance.dart',
    'test/interop/python_2026_07_28/requirements.txt',
    'test/interop/python_2026_07_28/README.md',
    'test/interop/ts_2026_07_28/package.json',
    'test/interop/ts_2026_07_28/README.md',
    'tool/release/mcp_2026_07_28_release_metadata.json',
    'tool/testing/mcp_2026_07_28_spec_ref.txt',
    'tool/testing/mcp_2026_07_28_tasks_spec_ref.txt',
  ];
  for (final path in paths) {
    final source = File('${repoRoot.path}/$path');
    final target = File('${fixture.path}/$path');
    target.parent.createSync(recursive: true);
    source.copySync(target.path);
  }

  final pubspec = File('${fixture.path}/pubspec.yaml');
  pubspec.writeAsStringSync(
    pubspec
        .readAsStringSync()
        .replaceFirst('version: 2.3.0-dev.2', 'version: 2.3.0')
        .replaceFirst(
          'documentation: https://github.com/leehack/mcp_dart/tree/'
              'v2.3.0-dev.2/doc',
          'documentation: https://github.com/leehack/mcp_dart/tree/main/doc',
        ),
  );

  final changelog = File('${fixture.path}/CHANGELOG.md');
  changelog.writeAsStringSync(
    changelog.readAsStringSync().replaceFirst(
          '## Unreleased',
          '## 2.3.0',
        ),
  );

  final constants = File('${fixture.path}/lib/src/types/json_rpc.dart');
  constants.writeAsStringSync(
    constants.readAsStringSync().replaceFirst(
          'const stableProtocolVersion = latestInitializationProtocolVersion;',
          'const stableProtocolVersion = previewProtocolVersion;',
        ),
  );

  const sdkReleaseDocs = <String>[
    'README.md',
    'doc/client-guide.md',
    'doc/getting-started.md',
    'doc/mcp-2026-07-28.md',
    'doc/quick-reference.md',
    'doc/server-guide.md',
    'doc/spec-coverage-2025-11-25.md',
    'doc/spec-coverage-2026-07-28.md',
    'example/example.md',
    'llms.txt',
  ];
  for (final path in sdkReleaseDocs) {
    final file = File('${fixture.path}/$path');
    file.writeAsStringSync(
      file
          .readAsStringSync()
          .replaceAll('2.3.0-dev.2', '2.3.0')
          .replaceAll('2.3.0 preview', '2.3.0')
          .replaceAll('MCP 2026-07-28 preview', 'MCP 2026-07-28')
          .replaceAll('MCP `2026-07-28` preview', 'MCP `2026-07-28`')
          .replaceAll('SDK preview:', 'SDK release:')
          .replaceAll('CLI preview:', 'CLI release:')
          .replaceAll('for preview gates', 'for release gates')
          .replaceAll(
            'release candidate for the MCP 2026-07-28 specification',
            'final MCP 2026-07-28 specification',
          )
          .replaceAll('locked release-candidate', 'final')
          .replaceAll(
            'pinned release-candidate specification',
            'pinned final specification',
          )
          .replaceAll(
            'The protocol is still a release candidate',
            'The protocol is final',
          )
          .replaceAll(
            '`stableProtocolVersion` is `2025-11-25`',
            '`stableProtocolVersion` is `2026-07-28`',
          )
          .replaceAll(
            'Use `stableProtocolVersion` for the official `2025-11-25`',
            'Use `stableProtocolVersion` for the official `2026-07-28`',
          )
          .replaceAll(
            'modelcontextprotocol.io/specification/draft/',
            'modelcontextprotocol.io/specification/2026-07-28/',
          ),
    );
  }

  final coreWorkflow = File(
    '${fixture.path}/.github/workflows/test_core.yml',
  );
  coreWorkflow.writeAsStringSync(
    coreWorkflow
        .readAsStringSync()
        .replaceAll(
          '.dart_tool/mcp-spec/schema/draft/examples',
          '.dart_tool/mcp-spec/schema/2026-07-28/examples',
        )
        .replaceAll(
          '.dart_tool/mcp-spec/docs/specification/draft',
          '.dart_tool/mcp-spec/docs/specification/2026-07-28',
        ),
  );

  const interopGapSurfaces = <String>[
    '.github/workflows/interop_2026_07_28.yml',
    'doc/interoperability.md',
    'doc/mcp-2026-07-28-release-runbook.md',
    'test/interop/python_2026_07_28/README.md',
    'test/interop/ts_2026_07_28/README.md',
  ];
  for (final path in interopGapSurfaces) {
    final file = File('${fixture.path}/$path');
    file.writeAsStringSync(
      file
          .readAsStringSync()
          .replaceAll('--expect-published-python-client-gap', '')
          .replaceAll('--expect-published-ts-client-gap', ''),
    );
  }

  if (prepareStableCli) {
    const cliReleaseDocs = <String>[
      'README.md',
      'llms.txt',
      'packages/mcp_dart_cli/README.md',
      'packages/mcp_dart_cli/example/example.md',
      'packages/mcp_dart_cli/test/fixtures/dart_mcp_project/pubspec.yaml',
    ];
    for (final path in cliReleaseDocs) {
      final file = File('${fixture.path}/$path');
      file.writeAsStringSync(
        file
            .readAsStringSync()
            .replaceAll('2.3.0-dev.2', '2.3.0')
            .replaceAll('0.2.0-dev.2', '0.2.0')
            .replaceAll('2.3.0 preview', '2.3.0')
            .replaceAll('MCP 2026-07-28 preview', 'MCP 2026-07-28')
            .replaceAll('MCP `2026-07-28` preview', 'MCP `2026-07-28`')
            .replaceAll('SDK preview:', 'SDK release:')
            .replaceAll('CLI preview:', 'CLI release:'),
      );
    }
    final cliPubspec = File(
      '${fixture.path}/packages/mcp_dart_cli/pubspec.yaml',
    );
    cliPubspec.writeAsStringSync(
      cliPubspec
          .readAsStringSync()
          .replaceFirst('version: 0.2.0-dev.2', 'version: 0.2.0')
          .replaceAll(
            'https://github.com/leehack/mcp_dart/tree/'
                'mcp_dart_cli-v0.2.0-dev.2/packages/mcp_dart_cli',
            'https://github.com/leehack/mcp_dart/tree/main/'
                'packages/mcp_dart_cli',
          )
          .replaceFirst('mcp_dart: ^2.3.0-dev.2', 'mcp_dart: ^2.3.0'),
    );
    final cliChangelog = File(
      '${fixture.path}/packages/mcp_dart_cli/CHANGELOG.md',
    );
    cliChangelog.writeAsStringSync(
      cliChangelog.readAsStringSync().replaceFirst(
            '## Unreleased',
            '## 0.2.0',
          ),
    );
    final cliVersionSource = File(
      '${fixture.path}/packages/mcp_dart_cli/lib/src/version.dart',
    );
    cliVersionSource.writeAsStringSync(
      cliVersionSource
          .readAsStringSync()
          .replaceFirst(
            "const packageVersion = '0.2.0-dev.2';",
            "const packageVersion = '0.2.0';",
          )
          .replaceFirst(
            "const generatedSdkConstraint = '^2.3.0-dev.2';",
            "const generatedSdkConstraint = '^2.3.0';",
          ),
    );
    final templatePubspec = File(
      '${fixture.path}/packages/templates/simple/__brick__/pubspec.yaml',
    );
    templatePubspec.writeAsStringSync(
      templatePubspec.readAsStringSync().replaceFirst(
            'mcp_dart: ^2.3.0-dev.2',
            'mcp_dart: ^2.3.0',
          ),
    );
  }

  if (finalInputsReviewed) {
    final metadataFile = File(
      '${fixture.path}/tool/release/mcp_2026_07_28_release_metadata.json',
    );
    final metadata =
        jsonDecode(metadataFile.readAsStringSync()) as Map<String, dynamic>;
    (metadata['coreSpecification']
        as Map<String, dynamic>)['finalReleaseReviewed'] = true;
    (metadata['tasksExtension']
        as Map<String, dynamic>)['finalReleaseReviewed'] = true;
    (metadata['tasksExtension']
        as Map<String, dynamic>)['pinnedContentsReviewed'] = true;
    (metadata['tasksExtension']
        as Map<String, dynamic>)['failedStateErrorShapeReviewed'] = true;
    (metadata['tasksExtension']
        as Map<String, dynamic>)['timingFieldIntegerSemanticsReviewed'] = true;
    (metadata['missingRequiredClientCapability']
        as Map<String, dynamic>)['finalTextsAgree'] = true;
    (metadata['subscriptionTermination']
        as Map<String, dynamic>)['finalTextsAgree'] = true;
    (metadata['releaseDocumentation']
        as Map<String, dynamic>)['finalReleaseReviewed'] = true;
    (metadata['officialConformance']
        as Map<String, dynamic>)['finalReleaseReviewed'] = true;
    (metadata['publishedInteropFixtures']
        as Map<String, dynamic>)['finalReleaseReviewed'] = true;
    metadataFile.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(metadata),
    );
  }

  return fixture;
}
