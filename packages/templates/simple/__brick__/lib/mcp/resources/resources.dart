/// MCP resources for the server.
library;

import 'base_resource.dart';
import 'manifest_resource.dart';

export 'base_resource.dart';
export 'manifest_resource.dart';

/// Creates all available resources.
List<BaseResource> createAllResources() => [
      ManifestResource(),
    ];
