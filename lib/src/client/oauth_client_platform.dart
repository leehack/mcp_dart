import 'oauth_client_platform_web.dart'
    if (dart.library.io) 'oauth_client_platform_native.dart';

/// OpenID Connect application type for this Dart runtime.
String get oauthClientApplicationType => platformOAuthClientApplicationType;
