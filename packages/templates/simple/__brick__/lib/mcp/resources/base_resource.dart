/// Base class for MCP resources with modular registration.
///
/// Each resource implementation should extend this class and provide:
/// - [name]: Human-readable name for the resource
/// - [uri]: Unique URI identifier for the resource
/// - [description]: Optional description of the resource content
/// - [mimeType]: Optional MIME type of the resource content
/// - [read]: Implementation to read the resource content
library;

import 'dart:async';

import 'package:mcp_dart/mcp_dart.dart';

/// Base class for all MCP resources.
abstract class BaseResource {
  /// Human-readable name for this resource.
  String get name;

  /// Unique URI for this resource.
  ///
  /// This should be a valid URI that uniquely identifies the resource.
  /// Example: 'simple://manifest'
  Uri get uri;

  /// Optional description of what this resource provides.
  String? get description => null;

  /// Optional MIME type of the resource content.
  ///
  /// Examples: 'application/json', 'text/plain'
  String? get mimeType => null;

  /// Read the resource content.
  ///
  /// [requestUri] is the URI used to request the resource (may include query params).
  /// Returns a [ReadResourceResult] with the resource contents.
  FutureOr<ReadResourceResult> read(Uri requestUri, RequestHandlerExtra? extra);
}

/// Extension to register resources with an MCP server.
extension ResourceRegistration on McpServer {
  /// Register a [BaseResource] with this server.
  void registerBaseResource(BaseResource resource) {
    ResourceMetadata? metadata;
    if (resource.description != null || resource.mimeType != null) {
      metadata = (
        description: resource.description,
        mimeType: resource.mimeType,
      );
    }

    registerResource(
      resource.name,
      resource.uri.toString(),
      metadata,
      (uri, extra) => resource.read(uri, extra),
    );
  }
}
