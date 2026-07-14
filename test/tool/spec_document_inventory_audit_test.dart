import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('spec_document_inventory_audit', () {
    late Directory root;
    late Directory docsRoot;
    late File manifestFile;

    setUp(() {
      root = Directory.systemTemp.createTempSync(
        'mcp_spec_document_inventory_audit_test_',
      );
      docsRoot = Directory(p.join(root.path, 'draft'))..createSync();
      manifestFile = File(p.join(root.path, 'manifest.json'));
    });

    tearDown(() {
      if (root.existsSync()) {
        root.deleteSync(recursive: true);
      }
    });

    test('accepts an exact inventory with scope and existing evidence',
        () async {
      final document = _writeDocument(docsRoot, 'basic/index.mdx');
      _writeManifest(manifestFile, {
        'basic/index.mdx': _entry(document),
      });

      final result = await _runAudit(docsRoot, manifestFile);

      expect(result.exitCode, 0, reason: _processOutput(result));
      expect(
        result.stdout,
        contains(
          'documents=1 inventoried=1 missing=0 stale=0 invalid=0',
        ),
      );
    });

    test('fails when the official docs add an uninventoried document',
        () async {
      final document = _writeDocument(docsRoot, 'basic/index.mdx');
      _writeDocument(docsRoot, 'server/future.mdx');
      _writeManifest(manifestFile, {
        'basic/index.mdx': _entry(document),
      });

      final result = await _runAudit(docsRoot, manifestFile);

      expect(result.exitCode, 1, reason: _processOutput(result));
      expect(result.stdout, contains('missing inventory entries:'));
      expect(result.stdout, contains('server/future.mdx'));
    });

    test('fails when an inventoried document is removed upstream', () async {
      final document = _writeDocument(docsRoot, 'basic/index.mdx');
      _writeManifest(manifestFile, {
        'basic/index.mdx': _entry(document),
        'server/removed.mdx': _entry(),
      });

      final result = await _runAudit(docsRoot, manifestFile);

      expect(result.exitCode, 1, reason: _processOutput(result));
      expect(result.stdout, contains('stale inventory entries:'));
      expect(result.stdout, contains('server/removed.mdx'));
    });

    test('fails when scope or repository evidence is invalid', () async {
      final document = _writeDocument(docsRoot, 'basic/index.mdx');
      _writeManifest(manifestFile, {
        'basic/index.mdx': {
          'scope': ' ',
          'sha256': _documentHash(document),
          'evidence': ['test/does_not_exist.dart'],
        },
      });

      final result = await _runAudit(docsRoot, manifestFile);

      expect(result.exitCode, 1, reason: _processOutput(result));
      expect(result.stdout, contains('scope must be a non-empty string'));
      expect(result.stdout, contains('evidence path does not exist'));
    });

    test('fails when inventoried document content changes', () async {
      final document = _writeDocument(docsRoot, 'basic/index.mdx');
      _writeManifest(manifestFile, {
        'basic/index.mdx': _entry(document),
      });
      document.writeAsStringSync('# Changed specification\n');

      final result = await _runAudit(docsRoot, manifestFile);

      expect(result.exitCode, 1, reason: _processOutput(result));
      expect(result.stdout, contains('sha256 mismatch'));
      expect(result.stdout, contains('basic/index.mdx'));
    });

    test('normalizes line endings before hashing documents', () async {
      final document = _writeDocument(
        docsRoot,
        'basic/index.mdx',
        contents: '# Specification\r\n\r\nText\r\n',
      );
      _writeManifest(manifestFile, {
        'basic/index.mdx': {
          ..._entry(),
          'sha256': sha256
              .convert(utf8.encode('# Specification\n\nText\n'))
              .toString(),
        },
      });

      final result = await _runAudit(docsRoot, manifestFile);

      expect(result.exitCode, 0, reason: _processOutput(result));
      expect(document.readAsStringSync(), contains('\r\n'));
    });
  });
}

Map<String, Object> _entry([File? document]) => {
      'scope': 'Core protocol evidence.',
      'sha256': document == null
          ? '0000000000000000000000000000000000000000000000000000000000000000'
          : _documentHash(document),
      'evidence': ['pubspec.yaml'],
    };

String _documentHash(File document) {
  final normalized = document
      .readAsStringSync()
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n');
  return sha256.convert(utf8.encode(normalized)).toString();
}

File _writeDocument(
  Directory root,
  String relativePath, {
  String contents = '# Specification\n',
}) {
  final file = File(p.join(root.path, relativePath));
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(contents);
  return file;
}

void _writeManifest(
  File file,
  Map<String, Map<String, Object>> documents,
) {
  file.writeAsStringSync(
    jsonEncode({
      'schemaVersion': 2,
      'specRevision': '2026-07-28',
      'documents': documents,
    }),
  );
}

Future<ProcessResult> _runAudit(Directory docsRoot, File manifestFile) {
  return Process.run(
    Platform.resolvedExecutable,
    [
      'run',
      'tool/spec_document_inventory_audit.dart',
      docsRoot.path,
      '--manifest',
      manifestFile.path,
    ],
    workingDirectory: Directory.current.path,
  );
}

String _processOutput(ProcessResult result) {
  return 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}';
}
