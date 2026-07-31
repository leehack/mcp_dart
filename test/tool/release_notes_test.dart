import 'package:test/test.dart';

import '../../tool/release/release_notes.dart';

void main() {
  test('extracts one exact section and preserves nested Markdown', () {
    final notes = extractReleaseNotes(
      changelog: '''
## 2.4.0

Release summary.

### Added

- A nested item.

  ```dart
  final heading = '## not a release';
  ```

> Compatibility note.

## 2.3.0

- Older notes.
''',
      version: '2.4.0',
    );

    expect(notes, '''
Release summary.

### Added

- A nested item.

  ```dart
  final heading = '## not a release';
  ```

> Compatibility note.
''');
  });

  test('ignores target and boundary headings in comments and fences', () {
    final notes = extractReleaseNotes(
      changelog: '''
<!--
## 2.4.0

- Comment decoy with a surrogate pair: 🧪.
-->

```markdown
## 2.4.0
```

## 2.4.0

- Actual notes.

<!-- ## 2.3.0 -->

~~~markdown
## 2.2.0
~~~

### Still current

- More notes.

## 2.1.0

- Older notes.
''',
      version: '2.4.0',
    );

    expect(notes, contains('- Actual notes.'));
    expect(notes, contains('<!-- ## 2.3.0 -->'));
    expect(notes, contains('## 2.2.0'));
    expect(notes, contains('### Still current'));
    expect(notes, contains('- More notes.'));
    expect(notes, isNot(contains('- Older notes.')));
  });

  test('does not let comment markers in fences hide later boundaries', () {
    final notes = extractReleaseNotes(
      changelog: '''
## 2.4.0

```html
<!-- This literal is intentionally unterminated.
```

- Current notes.

## 2.3.0

- Older notes.
''',
      version: '2.4.0',
    );

    expect(notes, contains('<!-- This literal is intentionally unterminated.'));
    expect(notes, contains('- Current notes.'));
    expect(notes, isNot(contains('- Older notes.')));
  });

  test('does not treat comment markers in inline code as comments', () {
    final notes = extractReleaseNotes(
      changelog: '''
## 2.4.0

- Supports the literal marker `<!--`.

## 2.3.0

- Older notes.
''',
      version: '2.4.0',
    );

    expect(notes, contains('`<!--`'));
    expect(notes, isNot(contains('- Older notes.')));
  });

  test('supports prerelease versions with punctuation', () {
    expect(
      extractReleaseNotes(
        changelog: '''
## 2.4.0-dev.12

- Preview notes.
''',
        version: '2.4.0-dev.12',
      ),
      '- Preview notes.\n',
    );
  });

  test('rejects a missing exact heading', () {
    expect(
      () => extractReleaseNotes(
        changelog: '## 2.4.0-dev.1\n\n- Preview notes.\n',
        version: '2.4.0',
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('no release heading'),
        ),
      ),
    );
  });

  test('rejects duplicate visible exact headings', () {
    expect(
      () => extractReleaseNotes(
        changelog: '''
## 2.4.0

- First copy.

## 2.4.0

- Second copy.
''',
        version: '2.4.0',
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('multiple release headings'),
        ),
      ),
    );
  });

  test('rejects heading-only, placeholder-only, and fenced-only notes', () {
    for (final body in <String>[
      '### Changed\n\nTBD',
      '- coming soon.',
      '- TODO:',
      '```text\nAn implementation example.\n```',
      '<!-- Real notes were not promoted. -->',
    ]) {
      expect(
        () => extractReleaseNotes(
          changelog: '## 2.4.0\n\n$body\n',
          version: '2.4.0',
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('no substantive release notes'),
          ),
        ),
        reason: body,
      );
    }
  });

  test('normalizes only boundary blank lines and the final newline', () {
    final notes = extractReleaseNotes(
      changelog: '## 0.2.0\r\n\r\n'
          '    Indented release detail.\r\n'
          '\r\n\r\n'
          '## 0.1.9\r\n'
          '- Older notes.',
      version: '0.2.0',
    );

    expect(notes, '    Indented release detail.\n');
  });
}
