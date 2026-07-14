import 'json_schema_suite_runner.dart';

// Keep these counts and identities synchronized with the pinned revision in
// json_schema_test_suite_ref.txt. Exact manifests prevent policy exclusions
// from silently broadening.
const _config = JsonSchemaSuiteConfig(
  dialect: 'Draft 7',
  usage: 'dart run tool/testing/run_json_schema_draft7_suite.dart '
      '<JSON-Schema-Test-Suite/tests/draft7>',
  expectedFileCount: 37,
  expectedGroupCount: 257,
  expectedAssertionCount: 904,
  expectedExternalReferenceGroups: {
    'refRemote.json :: remote ref',
    'refRemote.json :: fragment within remote ref',
    'refRemote.json :: ref within remote ref',
    'refRemote.json :: base URI change',
    'refRemote.json :: base URI change - change folder',
    'refRemote.json :: base URI change - change folder in subschema',
    'refRemote.json :: root ref in remote ref',
    'refRemote.json :: remote ref with ref to definitions',
    'refRemote.json :: Location-independent identifier in remote ref',
    r'refRemote.json :: retrieved nested refs resolve relative to their URI not $id',
    r'refRemote.json :: $ref to $ref finds location-independent $id',
  },
  expectedUnsupportedDialectGroups: {},
  expectedInvalidSchemaGroups: {},
  adaptSchema: _declareDraft7,
);

Object _declareDraft7(Object? schema) {
  if (schema is Map) {
    return <String, dynamic>{
      ...Map<String, dynamic>.from(schema),
      r'$schema': 'http://json-schema.org/draft-07/schema#',
    };
  }
  return <String, dynamic>{
    r'$schema': 'http://json-schema.org/draft-07/schema#',
    'allOf': [schema],
  };
}

/// Runs the pinned mandatory JSON Schema Draft 7 corpus.
void main(List<String> args) => runJsonSchemaSuite(args, _config);
