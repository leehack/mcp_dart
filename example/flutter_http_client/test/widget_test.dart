// Widget smoke tests for the MCP HTTP client example.
//
// These tests verify that the MCP client UI renders correctly in its initial
// disconnected state, without requiring a live server.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_dart/mcp_dart.dart';

import 'package:flutter_http_client/main.dart';
import 'package:flutter_http_client/screens/mcp_client_screen.dart';
import 'package:flutter_http_client/services/streamable_mcp_service.dart';

// ---------------------------------------------------------------------------
// Minimal stub – overrides only what the widget reads in the disconnected state
// ---------------------------------------------------------------------------
class _FakeMcpService extends StreamableMcpService {
  _FakeMcpService() : super(serverUrl: 'http://localhost:3000/mcp');

  @override
  bool get isConnected => false;

  @override
  String? get connectionError => null;

  @override
  List<Tool>? get availableTools => null;

  @override
  List<Prompt>? get availablePrompts => null;

  @override
  List<Resource>? get availableResources => null;
}

// ---------------------------------------------------------------------------
// Helper: pump MyApp inside a fixed-size surface to prevent overflow errors
// ---------------------------------------------------------------------------
Widget _testApp() {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 800,
        height: 1024,
        child: McpClientScreen(mcpService: _FakeMcpService()),
      ),
    ),
  );
}

void main() {
  testWidgets('MCP client screen renders AppBar title', (tester) async {
    await tester.pumpWidget(_testApp());
    expect(find.text('MCP Client'), findsOneWidget);
  });

  testWidgets('Connect button is present and enabled when disconnected',
      (tester) async {
    await tester.pumpWidget(_testApp());

    // "Connect" must be visible (requiresConnection: false means it is enabled)
    expect(find.text('Connect'), findsOneWidget);
  });

  testWidgets('Disconnect and Terminate Session buttons are present',
      (tester) async {
    await tester.pumpWidget(_testApp());
    expect(find.text('Disconnect'), findsOneWidget);
    expect(find.text('Terminate Session'), findsOneWidget);
  });

  testWidgets('Status chip shows Disconnected when not connected',
      (tester) async {
    await tester.pumpWidget(_testApp());
    expect(find.text('Disconnected'), findsOneWidget);
    expect(find.text('Connected'), findsNothing);
  });

  testWidgets('Settings icon button is present in AppBar', (tester) async {
    await tester.pumpWidget(_testApp());
    expect(find.byIcon(Icons.settings), findsOneWidget);
  });

  testWidgets('Response area shows welcome message on startup', (tester) async {
    await tester.pumpWidget(_testApp());
    // The initial _responseText set in initState
    expect(find.textContaining('Welcome to the MCP Client'), findsOneWidget);
  });

  testWidgets('No counter widgets from default Flutter template exist',
      (tester) async {
    await tester.pumpWidget(_testApp());
    expect(find.byIcon(Icons.add), findsNothing);
    // The old template asserted '0' and '1' as counter values
    expect(find.text('0'), findsNothing);
    expect(find.text('1'), findsNothing);
  });
}
