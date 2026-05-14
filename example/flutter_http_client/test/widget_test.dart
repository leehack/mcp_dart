import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_http_client/main.dart';

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
}
