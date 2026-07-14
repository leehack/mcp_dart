import 'dart:math';

import 'package:test/test.dart';

import '../../example/authentication/github_oauth_example.dart';

void main() {
  group('GitHub OAuth example', () {
    test('uses the callback URL documented by the setup guide', () {
      const config = GitHubOAuthConfig(
        clientId: 'client-id',
        clientSecret: 'client-secret',
        scopes: [],
      );

      expect(config.callbackUri, Uri.parse('http://localhost:8080/callback'));
    });

    test('generates 256-bit base64url state values without padding', () {
      final state = generateOAuthState(random: Random(42));

      expect(state, hasLength(43));
      expect(state, matches(RegExp(r'^[A-Za-z0-9_-]+$')));
      expect(state, isNot(contains('=')));
    });

    test('generates distinct state values by default', () {
      expect(generateOAuthState(), isNot(generateOAuthState()));
    });

    test('validates state exactly and fails closed for missing values', () {
      expect(isValidOAuthState('expected', 'expected'), isTrue);
      expect(isValidOAuthState('Expected', 'expected'), isFalse);
      expect(isValidOAuthState(null, 'expected'), isFalse);
      expect(isValidOAuthState('expected', null), isFalse);
    });

    test('generates a 256-bit verifier and matching S256 challenge', () {
      final verifier = generatePkceCodeVerifier(random: Random(42));
      final challenge = generatePkceS256Challenge(verifier);

      expect(verifier, hasLength(43));
      expect(verifier, matches(RegExp(r'^[A-Za-z0-9_-]+$')));
      expect(challenge, hasLength(43));
      expect(challenge, matches(RegExp(r'^[A-Za-z0-9_-]+$')));
      expect(challenge, isNot(verifier));
    });
  });
}
