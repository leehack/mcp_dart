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

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Simple MCP Client',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: McpClientScreen(
        mcpService: StreamableMcpService(
          serverUrl: 'http://localhost:3000/mcp',
        ),
      ),
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
