import 'dart:async';

import 'package:mcp_dart/mcp_dart.dart';
import 'server_iostream.dart';

/// Creates and returns a client with custom stream transport connected to a server.
Future<void> main() async {
  // Create a client
  final client = Client(
    Implementation(name: "example-dart-iostream-client", version: "1.0.0"),
    options: ClientOptions(capabilities: ClientCapabilities()),
  );

  final server = await getServer();

  // Create custom streams for transport
  final serverToClientStreamController = StreamController<List<int>>();
  final clientToServerStreamController = StreamController<List<int>>();

  // Create transport using custom streams
  final clientTransport = IOStreamTransport(
    stream: serverToClientStreamController.stream,
    sink: clientToServerStreamController.sink,
  );

  final serverTransport = IOStreamTransport(
    stream: clientToServerStreamController.stream,
    sink: serverToClientStreamController.sink,
  );

  // Set up listeners for transport events
  clientTransport.onclose = () {
    print('Client transport closed');
  };

  clientTransport.onerror = (error) {
    print('Client transport error: $error');
  };

  serverTransport.onclose = () {
    print('Server transport closed');
  };

  serverTransport.onerror = (error) {
    print('Server transport error: $error');
  };

  print('Starting client with custom stream transport...');

  await server.connect(serverTransport);
  // Connect the client to the transport
  await client.connect(clientTransport);

  final availableTools = await client.listTools();
  final toolNames = availableTools.tools.map((e) => e.name);
  print("Client setup complete. Available tools: $toolNames");
}
