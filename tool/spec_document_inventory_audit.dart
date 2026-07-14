import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

const _defaultManifestPath =
    'tool/testing/mcp_2026_07_28_spec_document_inventory.json';
const _expectedSchemaVersion = 2;
const _expectedSpecRevision = '2026-07-28';

void main(List<String> args) {
  final options = _Options.parse(args);
  if (options == null) {
    stderr.writeln(
      'usage: dart run tool/spec_document_inventory_audit.dart '
      '<specification docs dir> [--manifest <manifest file>]',
    );
    exitCode = 64;
    return;
  }

  final docsRoot = Directory(options.docsRoot);
  if (!docsRoot.existsSync()) {
    stderr.writeln('specification docs directory does not exist: '
        '${docsRoot.path}');
    exitCode = 66;
    return;
  }

  final manifestFile = File(options.manifestPath);
  if (!manifestFile.existsSync()) {
    stderr.writeln('specification document manifest does not exist: '
        '${manifestFile.path}');
    exitCode = 66;
    return;
  }

  try {
    final result = _audit(docsRoot, manifestFile);
    stdout.writeln(
      'documents=${result.documents.length} '
      'inventoried=${result.inventoried.length} '
      'missing=${result.missing.length} '
      'stale=${result.stale.length} '
      'invalid=${result.invalid.length}',
    );

    if (result.missing.isNotEmpty) {
      stdout.writeln('missing inventory entries:');
      for (final path in result.missing) {
        stdout.writeln('  $path');
      }
    }
    if (result.stale.isNotEmpty) {
      stdout.writeln('stale inventory entries:');
      for (final path in result.stale) {
        stdout.writeln('  $path');
      }
    }
    if (result.invalid.isNotEmpty) {
      stdout.writeln('invalid inventory entries:');
      for (final issue in result.invalid) {
        stdout.writeln('  $issue');
      }
    }

    if (!result.passed) {
      exitCode = 1;
    }
  } on FormatException catch (error) {
    stderr.writeln('invalid specification document manifest: ${error.message}');
    exitCode = 65;
  }
}

_AuditResult _audit(Directory docsRoot, File manifestFile) {
  final decoded = jsonDecode(manifestFile.readAsStringSync());
  if (decoded is! Map) {
    throw const FormatException('root must be a JSON object');
  }
  final manifest = Map<String, dynamic>.from(decoded);
  if (manifest['schemaVersion'] != _expectedSchemaVersion) {
    throw const FormatException(
      'schemaVersion must be $_expectedSchemaVersion',
    );
  }
  if (manifest['specRevision'] != _expectedSpecRevision) {
    throw const FormatException(
      'specRevision must be $_expectedSpecRevision',
    );
  }

  final rawDocuments = manifest['documents'];
  if (rawDocuments is! Map) {
    throw const FormatException('documents must be a JSON object');
  }
  final inventory = Map<String, dynamic>.from(rawDocuments);

  final documents = docsRoot
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.mdx'))
      .map(
        (file) =>
            p.relative(file.path, from: docsRoot.path).replaceAll('\\', '/'),
      )
      .toSet();
  final inventoried = inventory.keys.toSet();
  final missing = documents.difference(inventoried).toList()..sort();
  final stale = inventoried.difference(documents).toList()..sort();
  final invalid = <String>[];

  for (final entry in inventory.entries) {
    _validateEntry(docsRoot, entry.key, entry.value, invalid);
  }

  return _AuditResult(
    documents: documents,
    inventoried: inventoried,
    missing: missing,
    stale: stale,
    invalid: invalid,
  );
}

void _validateEntry(
  Directory docsRoot,
  String path,
  Object? value,
  List<String> invalid,
) {
  if (!_isNormalizedRelativePath(path) || !path.endsWith('.mdx')) {
    invalid.add('$path: document path must be a normalized relative .mdx path');
  }
  if (value is! Map) {
    invalid.add('$path: entry must be a JSON object');
    return;
  }

  final entry = Map<String, dynamic>.from(value);
  final scope = entry['scope'];
  if (scope is! String || scope.trim().isEmpty) {
    invalid.add('$path: scope must be a non-empty string');
  }

  final expectedHash = entry['sha256'];
  if (expectedHash is! String ||
      !RegExp(r'^[0-9a-f]{64}$').hasMatch(expectedHash)) {
    invalid.add('$path: sha256 must be a lowercase SHA-256 digest');
  } else {
    final document = File(p.join(docsRoot.path, path));
    if (document.existsSync()) {
      final actualHash = _normalizedDocumentHash(document);
      if (actualHash != expectedHash) {
        invalid.add(
          '$path: sha256 mismatch (expected $expectedHash, got $actualHash)',
        );
      }
    }
  }

  final evidence = entry['evidence'];
  if (evidence is! List || evidence.isEmpty) {
    invalid.add('$path: evidence must be a non-empty array');
    return;
  }

  final seenEvidence = <String>{};
  for (final item in evidence) {
    if (item is! String || item.trim().isEmpty) {
      invalid.add('$path: every evidence item must be a non-empty string');
      continue;
    }
    if (!_isNormalizedRelativePath(item)) {
      invalid
          .add('$path: evidence path must be normalized and relative: $item');
      continue;
    }
    if (!seenEvidence.add(item)) {
      invalid.add('$path: duplicate evidence path: $item');
      continue;
    }
    if (FileSystemEntity.typeSync(item) == FileSystemEntityType.notFound) {
      invalid.add('$path: evidence path does not exist: $item');
    }
  }
}

String _normalizedDocumentHash(File document) {
  final normalized = document
      .readAsStringSync()
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n');
  return sha256.convert(utf8.encode(normalized)).toString();
}

bool _isNormalizedRelativePath(String path) {
  if (path.isEmpty || p.posix.isAbsolute(path) || path.contains('\\')) {
    return false;
  }
  return p.posix.normalize(path) == path &&
      path != '..' &&
      !path.startsWith('../');
}

class _Options {
  final String docsRoot;
  final String manifestPath;

  const _Options({required this.docsRoot, required this.manifestPath});

  static _Options? parse(List<String> args) {
    String? docsRoot;
    var manifestPath = _defaultManifestPath;

    for (var index = 0; index < args.length; index++) {
      final argument = args[index];
      if (argument == '--manifest') {
        if (index + 1 >= args.length) {
          return null;
        }
        manifestPath = args[++index];
        continue;
      }
      if (argument.startsWith('-') || docsRoot != null) {
        return null;
      }
      docsRoot = argument;
    }

    if (docsRoot == null) {
      return null;
    }
    return _Options(docsRoot: docsRoot, manifestPath: manifestPath);
  }
}

class _AuditResult {
  final Set<String> documents;
  final Set<String> inventoried;
  final List<String> missing;
  final List<String> stale;
  final List<String> invalid;

  const _AuditResult({
    required this.documents,
    required this.inventoried,
    required this.missing,
    required this.stale,
    required this.invalid,
  });

  bool get passed => missing.isEmpty && stale.isEmpty && invalid.isEmpty;
}
