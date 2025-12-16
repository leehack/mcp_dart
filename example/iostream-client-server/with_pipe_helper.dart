import 'dart:async';

import 'package:mcp_dart/mcp_dart.dart';
import 'server_iostream.dart';

class PipeTransport {
  /// The client end of the pipe transport
  late final IOStreamTransport client;

  /// The server end of the pipe transport
  late final IOStreamTransport server;

  /// Creates a new pipe transport with in-memory streams.
  PipeTransport() {
    final clientToServerController = StreamController<List<int>>();
    final serverToClientController = StreamController<List<int>>();

    // Client reads from server's output, writes to server's input
    client = IOStreamTransport(
      stream: serverToClientController.stream,
      sink: clientToServerController.sink,
    );

    // Server reads from client's output, writes to client's input
    server = IOStreamTransport(
      stream: clientToServerController.stream,
      sink: serverToClientController.sink,
    );
  }
}

/// Creates and returns a client with custom stream transport connected to a server.
Future<void> main() async {
  // Create a client
  final client = Client(
    const Implementation(
      name: "example-dart-iostream-client",
      version: "1.0.0",
    ),
    options: const ClientOptions(capabilities: ClientCapabilities()),
  );

  final server = await getServer();

  final transport = PipeTransport();

  // Set up listeners for transport events
  transport.client.onclose = () {
    print('Client transport closed');
  };

  transport.client.onerror = (error) {
    print('Client transport error: $error');
  };

  transport.server.onclose = () {
    print('Server transport closed');
  };

  transport.server.onerror = (error) {
    print('Server transport error: $error');
  };

  print('Starting client with custom stream transport...');

  await server.connect(transport.server);
  // Connect the client to the transport
  await client.connect(transport.client);

  final availableTools = await client.listTools();
  final toolNames = availableTools.tools.map((e) => e.name);
  print("Client setup complete. Available tools: $toolNames");
}
