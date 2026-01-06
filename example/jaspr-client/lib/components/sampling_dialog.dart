/// Sampling dialog component.
///
/// A modal dialog for handling MCP sampling requests (LLM completions).
library;

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

/// A modal dialog for sampling requests.
class SamplingDialog extends StatefulComponent {
  final String prompt;
  final void Function(String response) onSubmit;
  final void Function() onCancel;

  const SamplingDialog({
    required this.prompt,
    required this.onSubmit,
    required this.onCancel,
    super.key,
  });

  @override
  State<SamplingDialog> createState() => _SamplingDialogState();
}

class _SamplingDialogState extends State<SamplingDialog> {
  String _response = '';
  bool _useMockResponse = true;

  static const String _mockResponse = '''
Cherry blossoms fall
Softly on the quiet pond
Spring whispers goodbye''';

  void _handleSubmit() {
    final response = _useMockResponse ? _mockResponse : _response;
    if (response.isNotEmpty) {
      component.onSubmit(response);
    }
  }

  @override
  Component build(BuildContext context) {
    return div(classes: 'dialog-overlay', [
      div(classes: 'dialog dialog-wide', [
        div(classes: 'dialog-header', [
          h3([Component.text('LLM Response Requested')]),
          button(
            classes: 'btn-close',
            onClick: component.onCancel,
            [Component.text('×')],
          ),
        ]),
        div(classes: 'dialog-content', [
          div(classes: 'dialog-icon sampling-icon', [Component.text('✨')]),
          p(classes: 'dialog-label', [
            Component.text('Server is asking for:'),
          ]),
          p(classes: 'dialog-prompt', [Component.text(component.prompt)]),
          div(classes: 'form-group', [
            label([
              input(
                type: InputType.checkbox,
                attributes: {if (_useMockResponse) 'checked': 'true'},
                events: {
                  'change': (event) {
                    setState(() {
                      _useMockResponse = !_useMockResponse;
                    });
                  },
                },
              ),
              Component.text(' Use mock haiku response'),
            ]),
          ]),
          if (!_useMockResponse)
            div(classes: 'form-group', [
              label(
                attributes: {'for': 'response-input'},
                [Component.text('Your response:')],
              ),
              textarea(
                id: 'response-input',
                attributes: {
                  'rows': '4',
                  'placeholder': 'Enter your response here...',
                },
                events: {
                  'input': (event) {
                    _response = (event.target as dynamic).value as String;
                  },
                },
                [],
              ),
            ])
          else
            div(classes: 'mock-response', [
              p(classes: 'mock-label', [Component.text('Mock response:')]),
              pre([Component.text(_mockResponse)]),
            ]),
        ]),
        div(classes: 'dialog-actions', [
          button(
            classes: 'btn btn-secondary',
            onClick: component.onCancel,
            [Component.text('Cancel')],
          ),
          button(
            classes: 'btn btn-primary',
            onClick: _handleSubmit,
            [Component.text('Submit Response')],
          ),
        ]),
      ]),
    ]);
  }
}
