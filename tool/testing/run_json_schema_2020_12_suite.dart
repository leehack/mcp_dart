import 'json_schema_suite_runner.dart';

// Keep these counts and identities synchronized with the pinned revision in
// json_schema_test_suite_ref.txt. Exact manifests prevent policy exclusions
// from silently broadening.
const _config = JsonSchemaSuiteConfig(
  dialect: '2020-12',
  usage: 'dart run tool/testing/run_json_schema_2020_12_suite.dart '
      '<JSON-Schema-Test-Suite/tests/draft2020-12>',
  expectedFileCount: 46,
  expectedGroupCount: 383,
  expectedAssertionCount: 1242,
  expectedExternalReferenceGroups: {
    r'dynamicRef.json :: $ref and $dynamicAnchor are independent of order - $defs first',
    r'dynamicRef.json :: $ref and $dynamicAnchor are independent of order - $ref first',
    r'dynamicRef.json :: $ref to $dynamicRef finds detached $dynamicAnchor',
    'dynamicRef.json :: strict-tree schema, guards against misspelled properties',
    'dynamicRef.json :: tests for implementation dynamic anchor and reference link',
    r'ref.json :: order of evaluation: $id and $ref on nested schema',
    r'refRemote.json :: $ref to $ref finds detached $anchor',
    'refRemote.json :: Location-independent identifier in remote ref',
    'refRemote.json :: anchor within remote ref',
    'refRemote.json :: base URI change',
    'refRemote.json :: base URI change - change folder',
    'refRemote.json :: base URI change - change folder in subschema',
    'refRemote.json :: fragment within remote ref',
    'refRemote.json :: ref within remote ref',
    r'refRemote.json :: remote HTTP ref with different $id',
    r'refRemote.json :: remote HTTP ref with different URN $id',
    'refRemote.json :: remote HTTP ref with nested absolute ref',
    'refRemote.json :: remote ref',
    'refRemote.json :: remote ref with ref to defs',
    r'refRemote.json :: retrieved nested refs resolve relative to their URI not $id',
    'refRemote.json :: root ref in remote ref',
  },
  expectedUnsupportedDialectGroups: {
    'vocabulary.json :: ignore unrecognized optional vocabulary',
    'vocabulary.json :: schema that uses custom metaschema with with no validation vocabulary',
  },
  expectedInvalidSchemaGroups: {
    'enum.json :: empty enum': 'enum must be a non-empty array',
  },
  adaptSchema: _identitySchema,
);

Object? _identitySchema(Object? schema) => schema;

/// Runs the pinned mandatory JSON Schema Draft 2020-12 corpus.
void main(List<String> args) => runJsonSchemaSuite(args, _config);
