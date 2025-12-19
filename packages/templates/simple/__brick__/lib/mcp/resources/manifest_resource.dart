import 'package:mcp_dart/mcp_dart.dart';

import 'base_resource.dart';

/// A simple resource that returns a manifest.
class ManifestResource extends BaseResource {
  @override
  String get name => 'manifest';

  @override
  Uri get uri => Uri.parse('simple://manifest');

  @override
  String get mimeType => 'application/json';

  @override
  String get description => 'A simple manifest resource';

  @override
  ReadResourceResult read(Uri requestUri, RequestHandlerExtra? extra) {
    return ReadResourceResult(
      contents: [
        TextResourceContents(
          uri: requestUri.toString(),
          mimeType: mimeType,
          text: '{"name": "simple-server"}',
        ),
      ],
    );
  }
}
