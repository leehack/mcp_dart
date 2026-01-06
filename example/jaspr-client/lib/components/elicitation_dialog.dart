/// Elicitation dialog component.
///
/// A modal dialog for handling MCP elicitation requests (e.g., confirm/cancel).
library;

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

/// A modal dialog for elicitation requests.
class ElicitationDialog extends StatelessComponent {
  final String message;
  final void Function() onConfirm;
  final void Function() onDecline;
  final void Function() onCancel;

  const ElicitationDialog({
    required this.message,
    required this.onConfirm,
    required this.onDecline,
    required this.onCancel,
    super.key,
  });

  @override
  Component build(BuildContext context) {
    return div(classes: 'dialog-overlay', [
      div(classes: 'dialog', [
        div(classes: 'dialog-header', [
          h3([Component.text('Server Request')]),
          button(
            classes: 'btn-close',
            onClick: onCancel,
            [Component.text('×')],
          ),
        ]),
        div(classes: 'dialog-content', [
          div(classes: 'dialog-icon elicitation-icon', [Component.text('?')]),
          p(classes: 'dialog-message', [Component.text(message)]),
        ]),
        div(classes: 'dialog-actions', [
          button(
            classes: 'btn btn-secondary',
            onClick: onDecline,
            [Component.text('No')],
          ),
          button(
            classes: 'btn btn-primary',
            onClick: onConfirm,
            [Component.text('Yes')],
          ),
        ]),
      ]),
    ]);
  }
}
