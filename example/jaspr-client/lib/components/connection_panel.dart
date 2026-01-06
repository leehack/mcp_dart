/// Connection panel component.
///
/// Provides UI for entering server URL and connecting/disconnecting.
library;

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../services/mcp_service.dart';

/// A panel for managing server connection.
class ConnectionPanel extends StatefulComponent {
  final McpConnectionState connectionState;
  final Future<void> Function(String serverUrl) onConnect;
  final Future<void> Function() onDisconnect;

  const ConnectionPanel({
    required this.connectionState,
    required this.onConnect,
    required this.onDisconnect,
    super.key,
  });

  @override
  State<ConnectionPanel> createState() => _ConnectionPanelState();
}

class _ConnectionPanelState extends State<ConnectionPanel> {
  String _serverUrl = 'http://localhost:8000/mcp';
  bool _isLoading = false;

  Future<void> _handleConnect() async {
    if (_isLoading) return;

    setState(() => _isLoading = true);
    try {
      await component.onConnect(_serverUrl);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleDisconnect() async {
    if (_isLoading) return;

    setState(() => _isLoading = true);
    try {
      await component.onDisconnect();
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Component build(BuildContext context) {
    final isConnected = component.connectionState == McpConnectionState.connected;
    final isConnecting = component.connectionState == McpConnectionState.connecting || _isLoading;

    return section(classes: 'panel connection-panel', [
      h2([Component.text('Connection')]),
      div(classes: 'form-group', [
        label(
          attributes: {'for': 'server-url'},
          [Component.text('Server URL')],
        ),
        input(
          id: 'server-url',
          type: InputType.text,
          value: _serverUrl,
          attributes: {
            'placeholder': 'http://localhost:8000/mcp',
            if (isConnected || isConnecting) 'disabled': 'true',
          },
          events: {
            'input': (event) {
              _serverUrl = (event.target as dynamic).value as String;
            },
          },
        ),
      ]),
      div(classes: 'button-group', [
        if (!isConnected)
          button(
            key: Key('connect-btn'),
            classes: 'btn btn-primary',
            attributes: {if (isConnecting) 'disabled': 'true'},
            events: {'click': (_) => _handleConnect()},
            [Component.text(isConnecting ? 'Connecting...' : 'Connect')],
          ),
        if (isConnected)
          button(
            key: Key('disconnect-btn'),
            classes: 'btn btn-secondary',
            attributes: {if (isConnecting) 'disabled': 'true'},
            events: {'click': (_) => _handleDisconnect()},
            [Component.text('Disconnect')],
          ),
      ]),
    ]);
  }
}
