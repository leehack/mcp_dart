/// Resources panel component.
library;

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:mcp_dart/mcp_dart.dart';

class ResourcesPanel extends StatelessComponent {
  final List<Resource> resources;
  final Function(String uri) onReadResource;
  final String? readingResourceUri;
  final String? resourceContent;

  const ResourcesPanel({
    required this.resources,
    required this.onReadResource,
    this.readingResourceUri,
    this.resourceContent,
    super.key,
  });

  @override
  Component build(BuildContext context) {
    return section(classes: 'panel resources-panel', [
      h2([Component.text('Resources')]),
      if (resources.isEmpty)
        div(classes: 'empty-state', [
          p([Component.text('No resources available.')]),
        ])
      else
        div(classes: 'resources-list', [
          for (final resource in resources) _buildResourceItem(resource),
        ]),
      if (resourceContent != null)
        div(
          classes: 'output-panel',
          attributes: {'style': 'margin-top: 1rem'},
          [
            h3([Component.text('Content: $readingResourceUri')]),
            div(classes: 'output-console', [
              pre([
                code([Component.text(resourceContent!)]),
              ]),
            ]),
          ],
        ),
    ]);
  }

  Component _buildResourceItem(Resource resource) {
    final isReading = readingResourceUri == resource.uri;
    return div(classes: 'tool-card', [
      div(classes: 'tool-header', [
        h3([Component.text(resource.name)]),
        button(
          classes: 'btn btn-small ${isReading ? "btn-loading" : "btn-secondary"}',
          onClick: () => onReadResource(resource.uri),
          [Component.text(isReading ? 'Reading...' : 'Read')],
        ),
      ]),
      div([
        span(classes: 'tool-args', [Component.text(resource.uri)]),
        if (resource.mimeType != null)
          span(
            classes: 'tool-args',
            attributes: {'style': 'margin-left: 0.5rem'},
            [Component.text(resource.mimeType!)],
          ),
      ]),
      if (resource.description != null) p(classes: 'tool-description', [Component.text(resource.description!)]),
    ]);
  }
}
