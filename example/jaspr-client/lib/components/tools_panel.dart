/// Tools panel component.
///
/// Displays available MCP tools and allows calling them.
library;

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:mcp_dart/mcp_dart.dart';

/// A panel displaying available tools with call buttons.
class ToolsPanel extends StatefulComponent {
  final List<Tool> tools;
  final bool isConnected;
  final Map<String, double>? toolProgress;
  final Future<void> Function(String name, Map<String, dynamic> args) onCallTool;

  const ToolsPanel({
    required this.tools,
    required this.isConnected,
    required this.onCallTool,
    this.toolProgress,
    super.key,
  });

  @override
  State<ToolsPanel> createState() => _ToolsPanelState();
}

class _ToolsPanelState extends State<ToolsPanel> {
  String? _callingTool;
  final Map<String, Map<String, dynamic>> _toolArguments = {};

  Future<void> _handleCallTool(Tool tool) async {
    if (_callingTool != null) return;

    setState(() => _callingTool = tool.name);

    try {
      final args = _toolArguments[tool.name] ?? {};
      await component.onCallTool(tool.name, args);
    } finally {
      setState(() => _callingTool = null);
    }
  }

  @override
  Component build(BuildContext context) {
    return section(classes: 'panel tools-panel', [
      h2([Component.text('Available Tools')]),
      if (!component.isConnected)
        div(classes: 'empty-state', [
          p([Component.text('Connect to a server to see available tools.')]),
        ])
      else if (component.tools.isEmpty)
        div(classes: 'empty-state', [
          p([Component.text('No tools available on this server.')]),
        ])
      else
        div(classes: 'tools-list', [
          for (final tool in component.tools) _buildToolCard(tool),
        ]),
    ]);
  }

  Component _buildToolCard(Tool tool) {
    final isCalling = _callingTool == tool.name;
    final progress = component.toolProgress?[tool.name];

    return div(key: Key(tool.name), classes: 'tool-card', [
      div(classes: 'tool-header', [
        h3([Component.text(tool.name)]),
        button(
          classes: 'btn btn-small ${isCalling ? "btn-loading" : "btn-accent"}',
          attributes: {if (isCalling) 'disabled': 'true'},
          events: {'click': (_) => _handleCallTool(tool)},
          [Component.text(isCalling ? 'Calling...' : 'Call')],
        ),
      ]),
      if (tool.description != null) p(classes: 'tool-description', [Component.text(tool.description!)]),
      if (progress != null)
        div(classes: 'progress-bar-container', [
          div(
            classes: 'progress-bar-fill',
            attributes: {'style': 'width: ${(progress * 100).clamp(0, 100)}%'},
            [],
          ),
        ]),
      _buildToolForm(tool),
    ]);
  }

  Component _buildToolForm(Tool tool) {
    final schema = tool.inputSchema;

    // Cast to JsonObject to access properties if possible
    if (schema is! JsonObject || (schema.properties?.isEmpty ?? true)) {
      return div(classes: 'tool-args', [
        p(classes: 'text-muted', [Component.text('No arguments required')]),
      ]);
    }

    final properties = schema.properties!;

    return div(classes: 'tool-args', [
      for (final entry in properties.entries) _buildArgumentInput(tool.name, entry.key, entry.value),
    ]);
  }

  Component _buildArgumentInput(String toolName, String argName, JsonSchema argSchema) {
    // Ensure map exists
    if (!_toolArguments.containsKey(toolName)) {
      _toolArguments[toolName] = {};
    }

    final currentArgs = _toolArguments[toolName]!;
    final value = currentArgs[argName];

    // Auto-fill default value if not set
    if (value == null && argSchema.defaultValue != null) {
      currentArgs[argName] = argSchema.defaultValue;
    }

    InputType inputType = InputType.text;
    if (argSchema is JsonInteger || argSchema is JsonNumber) {
      inputType = InputType.number;
    } else if (argSchema is JsonBoolean) {
      inputType = InputType.checkbox;
    }

    return div(classes: 'form-group', [
      label(
        attributes: {'for': 'tool-$toolName-arg-$argName'},
        [Component.text(argName)],
      ),
      input(
        id: 'tool-$toolName-arg-$argName',
        type: inputType,
        value: inputType != InputType.checkbox ? value?.toString() ?? '' : null,
        attributes: {
          if (inputType == InputType.checkbox && (value == true)) 'checked': 'true',
          if (argSchema.description != null) 'placeholder': argSchema.description!,
        },
        events: {
          inputType == InputType.checkbox ? 'change' : 'input': (e) {
            setState(() {
              if (inputType == InputType.number) {
                final val = (e.target as dynamic).value;
                if (val == null || val.toString().isEmpty) {
                  currentArgs.remove(argName);
                } else {
                  if (argSchema is JsonInteger) {
                    currentArgs[argName] = int.tryParse(val.toString());
                  } else {
                    currentArgs[argName] = num.tryParse(val.toString());
                  }
                }
              } else if (inputType == InputType.checkbox) {
                final checked = (e.target as dynamic).checked;
                currentArgs[argName] = checked;
              } else {
                currentArgs[argName] = (e.target as dynamic).value;
              }
            });
          },
        },
      ),
    ]);
  }
}
