import 'package:mcp_dart/src/shared/uri_template.dart';
import 'package:test/test.dart';

void main() {
  group('UriTemplateExpander - Basic Functionality', () {
    test('isTemplate detects template expressions', () {
      expect(UriTemplateExpander.isTemplate('file:///{path}'), isTrue);
      expect(UriTemplateExpander.isTemplate('/search{?q}'), isTrue);
      expect(UriTemplateExpander.isTemplate('plain/url'), isFalse);
      expect(UriTemplateExpander.isTemplate('no-braces'), isFalse);
    });

    test('creates expander from template string', () {
      final expander = UriTemplateExpander('file:///{path}');
      expect(expander.template, equals('file:///{path}'));
      expect(expander.toString(), equals('file:///{path}'));
    });

    test('basic variable expansion', () {
      final expander = UriTemplateExpander('file:///{path}');
      final result = expander.expand({'path': 'test.txt'});
      expect(result, equals('file:///test.txt'));
    });

    test('multiple variables with reserved expansion', () {
      // Use reserved expansion {+path} to avoid encoding /
      final expander = UriTemplateExpander('https://{host}{+path}');
      final result =
          expander.expand({'host': 'example.com', 'path': '/api/v1'});
      expect(result, equals('https://example.com/api/v1'));
    });

    test('missing variables are skipped', () {
      final expander = UriTemplateExpander('/api/{version}/{resource}');
      final result = expander.expand({'version': 'v1'});
      expect(result, equals('/api/v1/'));
    });

    test('null variables are skipped', () {
      final expander = UriTemplateExpander('/api/{version}');
      final result = expander.expand({'version': null});
      expect(result, equals('/api/'));
    });

    test('empty template returns empty string', () {
      final expander = UriTemplateExpander('');
      final result = expander.expand({});
      expect(result, equals(''));
    });

    test('template with no expressions', () {
      final expander = UriTemplateExpander('/static/path');
      final result = expander.expand({});
      expect(result, equals('/static/path'));
    });
  });

  group('UriTemplateExpander - Query Operators', () {
    test('query operator (?) basic usage', () {
      final expander = UriTemplateExpander('/search{?q}');
      final result = expander.expand({'q': 'dart'});
      expect(result, equals('/search?q=dart'));
    });

    test('query operator with multiple parameters', () {
      final expander = UriTemplateExpander('/search{?q,lang,page}');
      final result = expander.expand({'q': 'dart', 'lang': 'en', 'page': '1'});
      expect(result, equals('/search?q=dart&lang=en&page=1'));
    });

    test('query operator with missing parameters', () {
      final expander = UriTemplateExpander('/search{?q,lang}');
      final result = expander.expand({'q': 'dart'});
      expect(result, equals('/search?q=dart'));
    });

    test('query continuation operator (&)', () {
      final expander = UriTemplateExpander('/search?fixed=1{&q,lang}');
      final result = expander.expand({'q': 'dart', 'lang': 'en'});
      expect(result, equals('/search?fixed=1&q=dart&lang=en'));
    });

    test('query operator with empty value', () {
      final expander = UriTemplateExpander('/search{?q}');
      final result = expander.expand({'q': ''});
      // RFC 6570: empty values omit the '=' sign
      expect(result, equals('/search?q'));
    });
  });

  group('UriTemplateExpander - Path Operators', () {
    test('path operator (/) basic usage', () {
      final expander = UriTemplateExpander('/api{/version,resource}');
      final result = expander.expand({'version': 'v1', 'resource': 'users'});
      expect(result, equals('/api/v1/users'));
    });

    test('fragment operator (#)', () {
      final expander = UriTemplateExpander('/page{#section}');
      final result = expander.expand({'section': 'intro'});
      expect(result, equals('/page#intro'));
    });

    test('dot operator (.) for extensions', () {
      final expander = UriTemplateExpander('/file{.format}');
      final result = expander.expand({'format': 'json'});
      expect(result, equals('/file.json'));
    });

    test('semicolon operator (;) for parameters', () {
      final expander = UriTemplateExpander('/data{;x,y}');
      final result = expander.expand({'x': '10', 'y': '20'});
      expect(result, equals('/data;x=10;y=20'));
    });

    test('reserved expansion (+)', () {
      final expander = UriTemplateExpander('/path{+var}');
      final result = expander.expand({'var': 'a/b'});
      expect(result, equals('/patha/b'));
    });
  });

  group('UriTemplateExpander - List Values', () {
    test('list with explode modifier', () {
      final expander = UriTemplateExpander('/items{?list*}');
      final result = expander.expand({
        'list': ['a', 'b', 'c']
      });
      expect(result, equals('/items?list=a&list=b&list=c'));
    });

    test('list without explode modifier', () {
      final expander = UriTemplateExpander('/items{?list}');
      final result = expander.expand({
        'list': ['a', 'b', 'c']
      });
      expect(result, equals('/items?list=a,b,c'));
    });

    test('empty list is skipped', () {
      final expander = UriTemplateExpander('/items{?list}');
      final result = expander.expand({'list': []});
      expect(result, equals('/items'));
    });

    test('list with null values are filtered', () {
      final expander = UriTemplateExpander('/items{?list}');
      final result = expander.expand({
        'list': ['a', null, 'b']
      });
      expect(result, equals('/items?list=a,b'));
    });
  });

  group('UriTemplateExpander - Map Values', () {
    test('map with explode modifier', () {
      final expander = UriTemplateExpander('/data{?params*}');
      final result = expander.expand({
        'params': {'x': '1', 'y': '2'}
      });
      // Map iteration order may vary
      expect(result, anyOf(equals('/data?x=1&y=2'), equals('/data?y=2&x=1')));
    });

    test('map without explode modifier', () {
      final expander = UriTemplateExpander('/data{?params}');
      final result = expander.expand({
        'params': {'x': '1', 'y': '2'}
      });
      // Key-value pairs in comma-separated format
      expect(result, contains('/data?params='));
      expect(result, contains('x'));
      expect(result, contains('1'));
    });

    test('empty map is skipped', () {
      final expander = UriTemplateExpander('/data{?params}');
      final result = expander.expand({'params': {}});
      expect(result, equals('/data'));
    });

    test('map with null values are filtered', () {
      final expander = UriTemplateExpander('/data{?params}');
      final result = expander.expand({
        'params': {'x': '1', 'y': null}
      });
      expect(result, equals('/data?params=x,1'));
    });
  });

  group('UriTemplateExpander - Prefix Modifier', () {
    test('prefix modifier limits string length', () {
      final expander = UriTemplateExpander('/search{?q:3}');
      final result = expander.expand({'q': 'hello'});
      expect(result, equals('/search?q=hel'));
    });

    test('prefix modifier longer than value', () {
      final expander = UriTemplateExpander('/search{?q:10}');
      final result = expander.expand({'q': 'hi'});
      expect(result, equals('/search?q=hi'));
    });
  });

  group('UriTemplateExpander - Encoding', () {
    test('encodes special characters in values', () {
      final expander = UriTemplateExpander('/search{?q}');
      final result = expander.expand({'q': 'hello world'});
      expect(result, equals('/search?q=hello%20world'));
    });

    test('encodes reserved characters', () {
      final expander = UriTemplateExpander('/path{/segment}');
      final result = expander.expand({'segment': 'a&b'});
      expect(result, equals('/path/a%26b'));
    });

    test('reserved expansion allows reserved characters', () {
      final expander = UriTemplateExpander('/path{+var}');
      final result = expander.expand({'var': 'a/b?c'});
      expect(result, equals('/patha/b?c'));
    });

    test('unreserved characters are not encoded', () {
      final expander = UriTemplateExpander('/path{/segment}');
      final result = expander.expand({'segment': 'abc123-._~'});
      expect(result, equals('/path/abc123-._~'));
    });
  });

  group('UriTemplateExpander - Match Function', () {
    test('matches simple template', () {
      final expander = UriTemplateExpander('/api/{version}/{resource}');
      final result = expander.match('/api/v1/users');
      expect(result, equals({'version': 'v1', 'resource': 'users'}));
    });

    test('matches query parameters', () {
      final expander = UriTemplateExpander('/search{?q}');
      final result = expander.match('/search?q=dart');
      expect(result, equals({'q': 'dart'}));
    });

    test('returns null for non-matching URI', () {
      final expander = UriTemplateExpander('/api/{version}');
      final result = expander.match('/wrong/path');
      expect(result, isNull);
    });

    test('decodes matched values', () {
      final expander = UriTemplateExpander('/search{?q}');
      final result = expander.match('/search?q=hello%20world');
      expect(result, equals({'q': 'hello world'}));
    });

    test('handles match with invalid regex', () {
      final expander = UriTemplateExpander('/path/{var}');
      // Test with a URI that creates regex issues
      final result = expander.match('/path/[invalid');
      // Should either return null or valid result
      expect(result, anyOf(isNull, isA<Map>()));
    });
  });

  group('UriTemplateExpander - Error Handling', () {
    test('throws on unclosed expression', () {
      expect(
        () => UriTemplateExpander('/path/{unclosed'),
        throwsA(isA<ArgumentError>()
            .having((e) => e.message, 'message', contains('Unclosed'))),
      );
    });

    test('throws on empty expression', () {
      expect(
        () => UriTemplateExpander('/path/{}'),
        throwsA(isA<ArgumentError>()
            .having((e) => e.message, 'message', contains('Empty'))),
      );
    });

    test('throws on template too long', () {
      final longTemplate = 'a' * (maxTemplateLength + 1);
      expect(
        () => UriTemplateExpander(longTemplate),
        throwsA(isA<ArgumentError>().having(
            (e) => e.message, 'message', contains('exceeds maximum length'))),
      );
    });

    test('throws on variable name too long', () {
      final longVar = 'x' * (maxVariableLength + 1);
      expect(
        () => UriTemplateExpander('/path/{$longVar}'),
        throwsA(isA<ArgumentError>().having(
            (e) => e.message, 'message', contains('exceeds maximum length'))),
      );
    });

    test('throws on too many expressions', () {
      final manyExpressions =
          List.generate(maxTemplateExpressions + 1, (i) => '{x$i}').join('/');
      expect(
        () => UriTemplateExpander(manyExpressions),
        throwsA(isA<ArgumentError>().having(
            (e) => e.message, 'message', contains('too many expressions'))),
      );
    });

    test('throws on variable value too long during expansion', () {
      final expander = UriTemplateExpander('/path/{var}');
      final longValue = 'x' * (maxVariableLength + 1);
      expect(
        () => expander.expand({'var': longValue}),
        throwsA(isA<ArgumentError>().having(
            (e) => e.message, 'message', contains('exceeds maximum length'))),
      );
    });
  });

  group('UriTemplateExpander - Complex Scenarios', () {
    test('mixed literal and expressions', () {
      final expander =
          UriTemplateExpander('https://api.example.com/v1/{resource}{?limit}');
      final result = expander.expand({'resource': 'users', 'limit': '10'});
      expect(result, equals('https://api.example.com/v1/users?limit=10'));
    });

    test('multiple expressions of different types', () {
      final expander = UriTemplateExpander('/api{/version}{?query,page}');
      final result =
          expander.expand({'version': 'v2', 'query': 'test', 'page': '2'});
      expect(result, equals('/api/v2?query=test&page=2'));
    });

    test('real-world resource template example', () {
      final expander = UriTemplateExpander('file:///{directory}/{file}.{ext}');
      final result = expander.expand({
        'directory': 'documents',
        'file': 'report',
        'ext': 'pdf',
      });
      expect(result, equals('file:///documents/report.pdf'));
    });

    test('handles consecutive expressions', () {
      final expander = UriTemplateExpander('/path/{a}{b}{c}');
      final result = expander.expand({'a': '1', 'b': '2', 'c': '3'});
      expect(result, equals('/path/123'));
    });

    test('all variables missing returns only literals', () {
      final expander = UriTemplateExpander('/api/{version}/data');
      final result = expander.expand({});
      expect(result, equals('/api//data'));
    });
  });

  group('UriTemplateExpander - RFC 6570 Examples', () {
    test('RFC 6570 simple expansion', () {
      final expander = UriTemplateExpander('{var}');
      expect(expander.expand({'var': 'value'}), equals('value'));
    });

    test('RFC 6570 reserved expansion', () {
      final expander = UriTemplateExpander('{+var}');
      expect(expander.expand({'var': 'value'}), equals('value'));
    });

    test('RFC 6570 fragment expansion', () {
      final expander = UriTemplateExpander('{#var}');
      expect(expander.expand({'var': 'value'}), equals('#value'));
    });

    test('RFC 6570 path segments', () {
      final expander = UriTemplateExpander('{/var}');
      expect(expander.expand({'var': 'value'}), equals('/value'));
    });

    test('RFC 6570 path parameters', () {
      final expander = UriTemplateExpander('{;var}');
      expect(expander.expand({'var': 'value'}), equals(';var=value'));
    });

    test('RFC 6570 query parameters', () {
      final expander = UriTemplateExpander('{?var}');
      expect(expander.expand({'var': 'value'}), equals('?var=value'));
    });

    test('RFC 6570 query continuation', () {
      final expander = UriTemplateExpander('{&var}');
      expect(expander.expand({'var': 'value'}), equals('&var=value'));
    });
  });
}
