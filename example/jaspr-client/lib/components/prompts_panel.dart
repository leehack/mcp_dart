/// Prompts panel component.
library;

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:mcp_dart/mcp_dart.dart';

class PromptsPanel extends StatefulComponent {
  final List<Prompt> prompts;
  final Function(String name, Map<String, String> args) onGetPrompt;
  final GetPromptResult? promptResult;

  const PromptsPanel({
    required this.prompts,
    required this.onGetPrompt,
    this.promptResult,
    super.key,
  });

  @override
  State<PromptsPanel> createState() => _PromptsPanelState();
}

class _PromptsPanelState extends State<PromptsPanel> {
  Prompt? _selectedPrompt;
  final Map<String, String> _argValues = {};
  bool _isLoading = false;

  void _handleGetPrompt(Prompt prompt) {
    if (prompt.arguments == null || prompt.arguments!.isEmpty) {
      _executeGetPrompt(prompt.name, {});
    } else {
      setState(() {
        _selectedPrompt = prompt;
        _argValues.clear();
      });
    }
  }

  Future<void> _executeGetPrompt(String name, Map<String, String> args) async {
    setState(() => _isLoading = true);
    try {
      await component.onGetPrompt(name, args);
    } finally {
      setState(() {
        _isLoading = false;
        _selectedPrompt = null;
      });
    }
  }

  @override
  Component build(BuildContext context) {
    return section(classes: 'panel prompts-panel', [
      h2([Component.text('Prompts')]),
      if (component.prompts.isEmpty)
        div(classes: 'empty-state', [
          p([Component.text('No prompts available.')]),
        ])
      else
        div(classes: 'prompts-list', [
          for (final prompt in component.prompts) _buildPromptItem(prompt),
        ]),

      if (_selectedPrompt != null) _buildDialog(),

      if (component.promptResult != null)
        div(
          classes: 'prompt-result',
          attributes: {'style': 'margin-top: 1rem'},
          [
            h3([Component.text('Result')]),
            if (component.promptResult!.description != null) p([Component.text(component.promptResult!.description!)]),
            div(classes: 'prompt-console', [
              for (final msg in component.promptResult!.messages)
                div(classes: 'log-entry', [
                  span(classes: 'log-level', [Component.text(msg.role.name)]),
                  span(classes: 'log-message', [Component.text(_contentToString(msg.content))]),
                ]),
            ]),
          ],
        ),
    ]);
  }

  String _contentToString(Content content) {
    if (content is TextContent) return content.text;
    if (content is ImageContent) return '[Image: ${content.mimeType}]';
    if (content is EmbeddedResource) return '[Resource: ${content.resource.uri}]';
    return '[Unknown Content]';
  }

  Component _buildPromptItem(Prompt prompt) {
    return div(classes: 'tool-card', [
      div(classes: 'tool-header', [
        h3([Component.text(prompt.name)]),
        button(
          classes: 'btn btn-small btn-secondary',
          attributes: {if (_isLoading) 'disabled': 'true'},
          onClick: () => _handleGetPrompt(prompt),
          [Component.text('Get')],
        ),
      ]),
      if (prompt.description != null) p(classes: 'tool-description', [Component.text(prompt.description!)]),
    ]);
  }

  Component _buildDialog() {
    return div(classes: 'dialog-overlay', [
      div(classes: 'dialog', [
        div(classes: 'dialog-header', [
          h3([Component.text('Get Prompt: ${_selectedPrompt!.name}')]),
          button(
            classes: 'btn-close',
            onClick: () => setState(() => _selectedPrompt = null),
            [Component.text('×')],
          ),
        ]),
        div(classes: 'dialog-content', [
          for (final arg in _selectedPrompt!.arguments!)
            div(classes: 'form-group', [
              label(
                attributes: {'for': 'arg-${arg.name}'},
                [
                  Component.text('${arg.name}${arg.required == true ? '*' : ''}'),
                ],
              ),
              input(
                id: 'arg-${arg.name}',
                type: InputType.text,
                events: {
                  'input': (e) {
                    _argValues[arg.name] = (e.target as dynamic).value;
                  },
                },
              ),
              if (arg.description != null) p(classes: 'text-xs text-muted', [Component.text(arg.description!)]),
            ]),
        ]),
        div(classes: 'dialog-actions', [
          button(
            classes: 'btn btn-secondary',
            onClick: () => setState(() => _selectedPrompt = null),
            [Component.text('Cancel')],
          ),
          button(
            classes: 'btn btn-primary',
            onClick: () => _executeGetPrompt(_selectedPrompt!.name, _argValues),
            [Component.text('Get Prompt')],
          ),
        ]),
      ]),
    ]);
  }
}
