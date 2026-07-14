import 'package:flutter/material.dart';
import 'package:flutter_http_client/screens/mcp_client_screen.dart';
import 'package:flutter_http_client/services/streamable_mcp_service.dart';

void main() {
  // Set error handling for the entire app
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
  };

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final StreamableMcpService _mcpService = StreamableMcpService(
    serverUrl: 'http://localhost:3000/mcp',
  );

  @override
  void dispose() {
    _mcpService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MCP Dart Flutter Client',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: McpClientScreen(mcpService: _mcpService),
      builder: (context, child) {
        // Add an error handling wrapper around the app
        return Builder(
          builder: (context) {
            // Catch Flutter framework errors
            ErrorWidget.builder = (FlutterErrorDetails errorDetails) {
              return Scaffold(
                body: Center(
                  child: Text(
                    'App Error: ${errorDetails.exception}',
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              );
            };
            return child ?? const SizedBox.shrink();
          },
        );
      },
    );
  }
}
