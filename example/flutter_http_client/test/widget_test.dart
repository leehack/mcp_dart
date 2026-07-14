import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_dart/mcp_dart.dart';

import 'package:flutter_http_client/main.dart';
import 'package:flutter_http_client/screens/mcp_client_screen.dart';
import 'package:flutter_http_client/services/streamable_mcp_service.dart';

void main() {
  testWidgets('shows the MCP HTTP client UI', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final errorWidgetBuilder = ErrorWidget.builder;
    try {
      await tester.pumpWidget(const MyApp());
    } finally {
      // MyApp installs a global ErrorWidget.builder. Restore it as soon as
      // the first frame is built so Flutter's widget-test global state check
      // sees the original value even if pumpWidget throws.
      ErrorWidget.builder = errorWidgetBuilder;
    }

    expect(find.text('MCP Client'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Connect'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Disconnect'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Call Tool'), findsOneWidget);
    expect(find.textContaining('Welcome to the MCP Client'), findsOneWidget);
    expect(find.textContaining('Notifications (0):'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsNothing);
  });

  test('maps text to the advertised primary required tool argument', () {
    final tool = Tool(
      name: 'search',
      inputSchema: JsonSchema.object(
        properties: {'query': JsonSchema.string()},
        required: ['query'],
      ),
    );

    expect(buildToolArguments(tool, 'MCP Dart'), {'query': 'MCP Dart'});
    expect(() => buildToolArguments(tool, ''), throwsFormatException);
  });

  test('parses numeric tool arguments from the advertised schema', () {
    final tool = Tool(
      name: 'limit',
      inputSchema: JsonSchema.object(
        properties: {'count': JsonSchema.integer()},
        required: ['count'],
      ),
    );

    expect(buildToolArguments(tool, '3'), {'count': 3});
    expect(() => buildToolArguments(tool, 'three'), throwsFormatException);
  });

  test('parses a JSON object for tools with multiple arguments', () {
    final tool = Tool(
      name: 'calculate',
      inputSchema: JsonSchema.object(
        properties: {'left': JsonSchema.number(), 'right': JsonSchema.number()},
        required: ['left', 'right'],
      ),
    );

    expect(buildToolArguments(tool, '{"left": 2, "right": 3}'), {
      'left': 2,
      'right': 3,
    });
    expect(
      () => buildToolArguments(tool, '{"left": 2}'),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('right'),
        ),
      ),
    );
    expect(() => buildToolArguments(tool, '2'), throwsFormatException);
  });

  test('accepts only absolute HTTP server URLs', () {
    final service = StreamableMcpService(
      serverUrl: 'http://localhost:3000/mcp',
    );
    addTearDown(service.dispose);

    expect(service.updateServerUrl('/relative'), isFalse);
    expect(service.serverUrl, 'http://localhost:3000/mcp');
    expect(service.connectionError, contains('absolute HTTP or HTTPS'));

    expect(service.updateServerUrl('https://example.com/mcp'), isTrue);
    expect(service.serverUrl, 'https://example.com/mcp');
    expect(service.connectionError, isNull);
  });

  testWidgets('rebuilds when service notifications change', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final service = StreamableMcpService(
      serverUrl: 'http://localhost:3000/mcp',
    );
    await tester.pumpWidget(
      MaterialApp(home: McpClientScreen(mcpService: service)),
    );

    service.notifications.add(
      NotificationMessage(
        count: 1,
        level: 'progress',
        message: 'greet: 1/2',
        timestamp: DateTime(2026),
      ),
    );
    service.refresh();
    await tester.pump();
    expect(find.textContaining('Notifications (1):'), findsOneWidget);
    expect(find.text('greet: 1/2'), findsOneWidget);

    service.clearNotifications();
    await tester.pump();
    expect(find.textContaining('Notifications (0):'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    service.dispose();
  });

  testWidgets('disables commands while a request is pending', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final service = _PendingListToolsService();
    addTearDown(service.dispose);
    await tester.pumpWidget(
      MaterialApp(home: McpClientScreen(mcpService: service)),
    );

    await tester.tap(find.widgetWithText(ElevatedButton, 'List Tools'));
    await tester.pump();

    expect(
      tester
          .widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, 'Disconnect'),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, 'List Tools'),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(
            find.ancestor(
              of: find.byIcon(Icons.settings),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNull,
    );
    service.completeListTools();
    await tester.pump();

    expect(
      tester
          .widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, 'Disconnect'),
          )
          .onPressed,
      isNotNull,
    );
    expect(
      tester
          .widget<IconButton>(
            find.ancestor(
              of: find.byIcon(Icons.settings),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('ignores a pending request completion after unmount', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final service = _PendingListToolsService();
    addTearDown(service.dispose);
    await tester.pumpWidget(
      MaterialApp(home: McpClientScreen(mcpService: service)),
    );

    await tester.tap(find.widgetWithText(ElevatedButton, 'List Tools'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    service.completeListTools();
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('reports a failed session termination', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final service = _FailedTerminationService();
    addTearDown(service.dispose);
    await tester.pumpWidget(
      MaterialApp(home: McpClientScreen(mcpService: service)),
    );

    await tester.tap(find.widgetWithText(ElevatedButton, 'Terminate Session'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Failed to terminate session'), findsOneWidget);
    expect(find.textContaining('expected termination failure'), findsOneWidget);
  });
}

class _PendingListToolsService extends StreamableMcpService {
  final Completer<void> _listToolsCompleter = Completer<void>();

  _PendingListToolsService() : super(serverUrl: 'http://localhost:3000/mcp');

  @override
  bool get isConnected => true;

  @override
  Future<void> listTools() => _listToolsCompleter.future;

  void completeListTools() => _listToolsCompleter.complete();
}

class _FailedTerminationService extends StreamableMcpService {
  _FailedTerminationService() : super(serverUrl: 'http://localhost:3000/mcp');

  @override
  bool get isConnected => true;

  @override
  bool get canTerminateSession => true;

  @override
  String? get connectionError => 'expected termination failure';

  @override
  Future<bool> terminateSession() async => false;
}
