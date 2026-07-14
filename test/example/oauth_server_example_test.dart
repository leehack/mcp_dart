import 'package:test/test.dart';

import '../../example/authentication/oauth_server_example.dart';

void main() {
  group('OAuth server example bearer validation', () {
    test('accepts only an exact bearer token', () {
      expect(
        isExpectedBearerToken('Bearer local-secret', 'local-secret'),
        isTrue,
      );
      expect(
        isExpectedBearerToken('bearer local-secret', 'local-secret'),
        isFalse,
      );
      expect(
        isExpectedBearerToken('Bearer local-secret ', 'local-secret'),
        isFalse,
      );
      expect(isExpectedBearerToken('Bearer other', 'local-secret'), isFalse);
    });

    test('fails closed for missing or empty credentials', () {
      expect(isExpectedBearerToken(null, 'local-secret'), isFalse);
      expect(isExpectedBearerToken('Bearer local-secret', ''), isFalse);
      expect(isExpectedBearerToken('', 'local-secret'), isFalse);
    });
  });
}
