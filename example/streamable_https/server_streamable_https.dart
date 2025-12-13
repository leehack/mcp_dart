import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mcp_dart/mcp_dart.dart';

// Add a custom extension to access the server from the RequestHandlerExtra
extension McpRequestHandlerExtra on RequestHandlerExtra {
  Server? get mcpServer => null;
}

// Simple in-memory event store for resumability
class InMemoryEventStore implements EventStore {
  final Map<String, List<({EventId id, JsonRpcMessage message})>> _events = {};
  int _eventCounter = 0;

  @override
  Future<EventId> storeEvent(StreamId streamId, JsonRpcMessage message) async {
    final eventId = (++_eventCounter).toString();
    _events.putIfAbsent(streamId, () => []);
    _events[streamId]!.add((id: eventId, message: message));
    return eventId;
  }

  @override
  Future<StreamId> replayEventsAfter(
    EventId lastEventId, {
    required Future<void> Function(EventId eventId, JsonRpcMessage message)
        send,
  }) async {
    // Find the stream containing this event ID
    String? streamId;
    int fromIndex = -1;

    for (final entry in _events.entries) {
      final idx = entry.value.indexWhere((event) => event.id == lastEventId);

      if (idx >= 0) {
        streamId = entry.key;
        fromIndex = idx;
        break;
      }
    }

    if (streamId == null) {
      throw StateError('Event ID not found: $lastEventId');
    }

    // Replay all events after the lastEventId
    for (int i = fromIndex + 1; i < _events[streamId]!.length; i++) {
      final event = _events[streamId]![i];
      await send(event.id, event.message);
    }

    return streamId;
  }
}

// Create an MCP server with implementation details
McpServer getServer() {
  // Create the McpServer with the implementation details and options
  final server = McpServer(
    Implementation(name: 'simple-streamable-http-server', version: '1.0.0'),
  );

  // Register a simple tool that returns a greeting
  server.tool(
    'greet',
    description: 'A simple greeting tool',
    toolInputSchema: ToolInputSchema(
      properties: {
        'name': {
          'type': 'string',
          'description': 'Name to greet',
        },
      },
      required: ['name'],
    ),
    callback: ({args, meta, extra}) async {
      final name = args?['name'] as String? ?? 'world';
      return CallToolResult.fromContent(
        content: [
          TextContent(text: 'Hello, $name!'),
        ],
      );
    },
  );

  // Register a tool that sends multiple greetings with notifications
  server.tool(
    'multi-greet',
    description:
        'A tool that sends different greetings with delays between them',
    toolInputSchema: ToolInputSchema(
      properties: {
        'name': {
          'type': 'string',
          'description': 'Name to greet',
        },
      },
      required: [],
    ),
    annotations: ToolAnnotations(
      title: 'Multiple Greeting Tool',
      readOnlyHint: true,
      openWorldHint: false,
    ),
    callback: ({args, meta, extra}) async {
      final name = args?['name'] as String? ?? 'world';

      // Helper function for sleeping
      Future<void> sleep(int ms) => Future.delayed(Duration(milliseconds: ms));

      // Send debug notification
      await extra?.sendNotification(JsonRpcLoggingMessageNotification(
          logParams: LoggingMessageNotificationParams(
        level: LoggingLevel.debug,
        data: 'Starting multi-greet for $name',
      )));

      await sleep(1000); // Wait 1 second before first greeting

      // Send first info notification
      await extra?.sendNotification(JsonRpcLoggingMessageNotification(
          logParams: LoggingMessageNotificationParams(
        level: LoggingLevel.info,
        data: 'Sending first greeting to $name',
      )));

      await sleep(1000); // Wait another second before second greeting

      // Send second info notification
      await extra?.sendNotification(JsonRpcLoggingMessageNotification(
          logParams: LoggingMessageNotificationParams(
        level: LoggingLevel.info,
        data: 'Sending second greeting to $name',
      )));

      return CallToolResult.fromContent(
        content: [
          TextContent(text: 'Good morning, $name!'),
        ],
      );
    },
  );

  // Register a simple prompt
  server.prompt(
    'greeting-template',
    description: 'A simple greeting prompt template',
    argsSchema: {
      'name': PromptArgumentDefinition(
        description: 'Name to include in greeting',
        required: true,
      ),
    },
    callback: (args, extra) async {
      final name = args!['name'] as String;
      return GetPromptResult(
        messages: [
          PromptMessage(
            role: PromptMessageRole.user,
            content: TextContent(
              text: 'Please greet $name in a friendly manner.',
            ),
          ),
        ],
      );
    },
  );

  // Register a tool specifically for testing resumability
  server.tool(
    'start-notification-stream',
    description:
        'Starts sending periodic notifications for testing resumability',
    toolInputSchema: ToolInputSchema(
      properties: {
        'interval': {
          'type': 'number',
          'description': 'Interval in milliseconds between notifications',
          'default': 100,
        },
        'count': {
          'type': 'number',
          'description': 'Number of notifications to send (0 for 100)',
          'default': 50,
        },
      },
    ),
    callback: ({args, meta, extra}) async {
      final interval = args?['interval'] as num? ?? 100;
      final count = args?['count'] as num? ?? 50;

      // Helper function for sleeping
      Future<void> sleep(int ms) => Future.delayed(Duration(milliseconds: ms));

      var counter = 0;

      while (count == 0 || counter < count) {
        counter++;
        try {
          await extra?.sendNotification(JsonRpcLoggingMessageNotification(
              logParams: LoggingMessageNotificationParams(
            level: LoggingLevel.info,
            data:
                'Periodic notification #$counter at ${DateTime.now().toIso8601String()}',
          )));
        } catch (error) {
          print('Error sending notification: $error');
        }

        // Wait for the specified interval
        await sleep(interval.toInt());
      }

      return CallToolResult.fromContent(
        content: [
          TextContent(
            text: 'Started sending periodic notifications every ${interval}ms',
          ),
        ],
      );
    },
  );

  // Create a simple resource at a fixed URI
  server.resource(
    'greeting-resource',
    'https://example.com/greetings/default',
    (uri, extra) async {
      return ReadResourceResult(
        contents: [
          ResourceContents.fromJson({
            'uri': 'https://example.com/greetings/default',
            'text': 'Hello, world!',
            'mimeType': 'text/plain'
          }),
        ],
      );
    },
    metadata: (mimeType: 'text/plain', description: null),
  );

  return server;
}

void setCorsHeaders(HttpResponse response) {
  response.headers.set('Access-Control-Allow-Origin', '*'); // Allow any origin
  response.headers
      .set('Access-Control-Allow-Methods', 'GET, POST, DELETE, OPTIONS');
  response.headers.set('Access-Control-Allow-Headers',
      'Origin, X-Requested-With, Content-Type, Accept, mcp-session-id, Last-Event-ID, Authorization');
  response.headers.set('Access-Control-Allow-Credentials', 'true');
  response.headers.set('Access-Control-Max-Age', '86400'); // 24 hours
  response.headers.set('Access-Control-Expose-Headers', 'mcp-session-id');
}

void main() async {
  // Map to store transports by session ID
  final transports = <String, StreamableHTTPServerTransport>{};

  // Create HTTP server
  final server = await HttpServer.bind(InternetAddress.anyIPv4, 3000);
  print('MCP Streamable HTTP Server listening on port 3000');

  await for (final request in server) {
    // Apply CORS headers to all responses
    setCorsHeaders(request.response);

    if (request.method == 'OPTIONS') {
      // Handle CORS preflight request
      request.response.statusCode = HttpStatus.ok;
      await request.response.close();
      continue;
    }

    if (request.uri.path != '/mcp') {
      // Not an MCP endpoint
      request.response
        ..statusCode = HttpStatus.notFound
        ..write('Not Found')
        ..close();
      continue;
    }

    switch (request.method) {
      case 'OPTIONS':
        // Handle preflight requests
        request.response.statusCode = HttpStatus.ok;
        await request.response.close();
        break;
      case 'POST':
        await handlePostRequest(request, transports);
        break;
      case 'GET':
        await handleGetRequest(request, transports);
        break;
      case 'DELETE':
        await handleDeleteRequest(request, transports);
        break;
      default:
        request.response
          ..statusCode = HttpStatus.methodNotAllowed
          ..headers.set(HttpHeaders.allowHeader, 'GET, POST, DELETE, OPTIONS');
        // CORS headers already applied at the top
        request.response
          ..write('Method Not Allowed')
          ..close();
    }
  }
}

// Function to check if a request is an initialization request
bool isInitializeRequest(dynamic body) {
  if (body is Map<String, dynamic> &&
      body.containsKey('method') &&
      body['method'] == 'initialize') {
    return true;
  }
  return false;
}

// Handle POST requests
Future<void> handlePostRequest(
  HttpRequest request,
  Map<String, StreamableHTTPServerTransport> transports,
) async {
  print('Received MCP request');

  try {
    // Parse the body
    final bodyBytes = await collectBytes(request);
    final bodyString = utf8.decode(bodyBytes);
    final body = jsonDecode(bodyString);

    // Check for existing session ID
    final sessionId = request.headers.value('mcp-session-id');
    StreamableHTTPServerTransport? transport;

    if (sessionId != null && transports.containsKey(sessionId)) {
      // Reuse existing transport
      transport = transports[sessionId]!;
    } else if (sessionId == null && isInitializeRequest(body)) {
      // New initialization request
      final eventStore = InMemoryEventStore();
      transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(
          sessionIdGenerator: () => generateUUID(),
          eventStore: eventStore, // Enable resumability
          onsessioninitialized: (sessionId) {
            // Store the transport by session ID when session is initialized
            print('Session initialized with ID: $sessionId');
            transports[sessionId] = transport!;
          },
        ),
      );

      // Set up onclose handler to clean up transport when closed
      transport.onclose = () {
        final sid = transport!.sessionId;
        if (sid != null && transports.containsKey(sid)) {
          print(
              'Transport closed for session $sid, removing from transports map');
          transports.remove(sid);
        }
      };

      // Connect the transport to the MCP server BEFORE handling the request
      final server = getServer();
      await server.connect(transport);

      print('Handling initialization request for a new session');
      await transport.handleRequest(request, body);
      return; // Already handled
    } else {
      // Invalid request - no session ID or not initialization request
      request.response
        ..statusCode = HttpStatus.badRequest
        ..headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      // Apply CORS headers to this specific response
      setCorsHeaders(request.response);
      request.response
        ..write(jsonEncode({
          'jsonrpc': '2.0',
          'error': {
            'code': -32000,
            'message': 'Bad Request: No valid session ID provided',
          },
          'id': null,
        }))
        ..close();
      return;
    }

    // Handle the request with existing transport
    await transport.handleRequest(request, body);
  } catch (error) {
    print('Error handling MCP request: $error');
    // Check if headers are already sent
    bool headersSent = false;
    try {
      headersSent = request.response.headers.contentType
          .toString()
          .startsWith('text/event-stream');
    } catch (_) {
      // Ignore errors when checking headers
    }

    if (!headersSent) {
      request.response
        ..statusCode = HttpStatus.internalServerError
        ..headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      // Apply CORS headers
      setCorsHeaders(request.response);
      request.response
        ..write(jsonEncode({
          'jsonrpc': '2.0',
          'error': {
            'code': -32603,
            'message': 'Internal server error',
          },
          'id': null,
        }))
        ..close();
    }
  }
}

// Handle GET requests for SSE streams
Future<void> handleGetRequest(
  HttpRequest request,
  Map<String, StreamableHTTPServerTransport> transports,
) async {
  final sessionId = request.headers.value('mcp-session-id');
  if (sessionId == null || !transports.containsKey(sessionId)) {
    request.response.statusCode = HttpStatus.badRequest;
    // Apply CORS headers
    setCorsHeaders(request.response);
    request.response
      ..write('Invalid or missing session ID')
      ..close();
    return;
  }

  // Check for Last-Event-ID header for resumability
  final lastEventId = request.headers.value('Last-Event-ID');
  if (lastEventId != null) {
    print('Client reconnecting with Last-Event-ID: $lastEventId');
  } else {
    print('Establishing new SSE stream for session $sessionId');
  }

  final transport = transports[sessionId]!;
  await transport.handleRequest(request);
}

// Handle DELETE requests for session termination
Future<void> handleDeleteRequest(
  HttpRequest request,
  Map<String, StreamableHTTPServerTransport> transports,
) async {
  final sessionId = request.headers.value('mcp-session-id');
  if (sessionId == null || !transports.containsKey(sessionId)) {
    request.response.statusCode = HttpStatus.badRequest;
    // Apply CORS headers
    setCorsHeaders(request.response);
    request.response
      ..write('Invalid or missing session ID')
      ..close();
    return;
  }

  print('Received session termination request for session $sessionId');

  try {
    final transport = transports[sessionId]!;
    await transport.handleRequest(request);
  } catch (error) {
    print('Error handling session termination: $error');
    // Check if headers are already sent
    bool headersSent = false;
    try {
      headersSent = request.response.headers.contentType
          .toString()
          .startsWith('text/event-stream');
    } catch (_) {
      // Ignore errors when checking headers
    }

    if (!headersSent) {
      request.response.statusCode = HttpStatus.internalServerError;
      // Apply CORS headers
      setCorsHeaders(request.response);
      request.response
        ..write('Error processing session termination')
        ..close();
    }
  }
}

// Helper function to collect bytes from an HTTP request
Future<List<int>> collectBytes(HttpRequest request) {
  final completer = Completer<List<int>>();
  final bytes = <int>[];

  request.listen(
    bytes.addAll,
    onDone: () => completer.complete(bytes),
    onError: completer.completeError,
    cancelOnError: true,
  );

  return completer.future;
}
