import 'package:test/test.dart';

import 'conformance_scenario_inventory.dart';

void main() {
  test('parses client and server scenario names without headings', () {
    const output = '''
Client scenarios (test against a client):
  - tools_call [2025-11-25,2026-07-28]
  - auth/metadata-default [2026-07-28]
ignored diagnostic text
  - json-schema-ref-no-deref [2026-07-28]
''';

    expect(
      parseConformanceScenarioNames(output),
      {
        'tools_call',
        'auth/metadata-default',
        'json-schema-ref-no-deref',
      },
    );
  });

  test('does not accept malformed or versionless list lines', () {
    const output = '''
  - no-version
  scenario [2026-07-28]
  -  [2026-07-28]
''';

    expect(parseConformanceScenarioNames(output), isEmpty);
  });
}
