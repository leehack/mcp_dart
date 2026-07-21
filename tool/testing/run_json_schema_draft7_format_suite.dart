import 'json_schema_suite_runner.dart';

// Keep these counts synchronized with the pinned revision in
// json_schema_test_suite_ref.txt. Draft 7 treats `format` as an assertion, so
// replacing the validator dependency must retain this optional official gate.
const _config = JsonSchemaSuiteConfig(
  dialect: 'Draft 7 optional formats',
  usage: 'dart run tool/testing/run_json_schema_draft7_format_suite.dart '
      '<JSON-Schema-Test-Suite/tests/draft7/optional/format>',
  expectedFileCount: 18,
  expectedGroupCount: 20,
  expectedAssertionCount: 587,
  expectedExternalReferenceGroups: {},
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

/// Runs the pinned optional JSON Schema Draft 7 format corpus.
void main(List<String> args) => runJsonSchemaSuite(args, _config);
