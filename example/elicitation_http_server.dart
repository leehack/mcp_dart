/// HTTP server example demonstrating elicitation feature with Streamable HTTP transport.
///
/// This example mirrors the TypeScript elicitationExample.ts and shows:
/// - User registration with multiple fields
/// - Multi-step workflow (event creation)
/// - Address collection with validation
///
/// Run with: dart run example/elicitation_http_server.dart
///
/// Connect using an HTTP MCP client on http://localhost:3000/mcp
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mcp_dart/mcp_dart.dart';

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

// Create MCP server with elicitation tools
McpServer getServer() {
  final server = McpServer(
    const Implementation(name: 'elicitation-example-server', version: '1.0.0'),
  );

  // Example 1: Simple user registration tool
  // Collects username, email, and password from the user
  server.tool(
    'register_user',
    description: 'Register a new user account by collecting their information',
    toolInputSchema: const ToolInputSchema(properties: {}),
    callback: ({args, meta, extra}) async {
      try {
        // Collect username
        final usernameResult = await server.elicitUserInput(
          'Enter your username (3-20 characters)',
          {
            'type': 'object',
            'properties': {
              'username': {
                'type': 'string',
                'minLength': 3,
                'maxLength': 20,
                'description': 'Your desired username',
              },
            },
            'required': ['username'],
          },
        );

        if (!usernameResult.accepted) {
          return CallToolResult.fromContent(
            content: [
              const TextContent(text: 'Registration cancelled by user.'),
            ],
          );
        }

        final username = usernameResult.content?['username'] as String;

        // Collect email
        final emailResult = await server.elicitUserInput(
          'Enter your email address',
          {
            'type': 'object',
            'properties': {
              'email': {
                'type': 'string',
                'minLength': 3,
                'description': 'Your email address',
              },
            },
            'required': ['email'],
          },
        );

        if (!emailResult.accepted) {
          return CallToolResult.fromContent(
            content: [
              const TextContent(text: 'Registration cancelled by user.'),
            ],
          );
        }

        final email = emailResult.content?['email'] as String;

        // Collect password
        final passwordResult = await server.elicitUserInput(
          'Enter your password (min 8 characters)',
          {
            'type': 'object',
            'properties': {
              'password': {
                'type': 'string',
                'minLength': 8,
                'description': 'Your password',
              },
            },
            'required': ['password'],
          },
        );

        if (!passwordResult.accepted) {
          return CallToolResult.fromContent(
            content: [
              const TextContent(text: 'Registration cancelled by user.'),
            ],
          );
        }

        // Collect newsletter preference
        final newsletterResult = await server.elicitUserInput(
          'Subscribe to newsletter?',
          {
            'type': 'object',
            'properties': {
              'newsletter': {
                'type': 'boolean',
                'default': false,
                'description': 'Receive updates via email',
              },
            },
          },
        );

        final newsletter = newsletterResult.accepted
            ? (newsletterResult.content?['newsletter'] as bool? ?? false)
            : false;

        // Return success response
        return CallToolResult.fromContent(
          content: [
            TextContent(
              text: '''Registration successful!

Username: $username
Email: $email
Newsletter: ${newsletter ? 'Yes' : 'No'}''',
            ),
          ],
        );
      } catch (error) {
        return CallToolResult.fromContent(
          content: [
            TextContent(text: 'Registration failed: $error'),
          ],
          isError: true,
        );
      }
    },
  );

  // Example 2: Multi-step workflow with multiple elicitation requests
  // Demonstrates how to collect information in multiple steps
  server.tool(
    'create_event',
    description: 'Create a calendar event by collecting event details',
    toolInputSchema: const ToolInputSchema(properties: {}),
    callback: ({args, meta, extra}) async {
      try {
        // Step 1: Collect basic event information
        final titleResult = await server.elicitUserInput(
          'Step 1: Enter event title',
          {
            'type': 'object',
            'properties': {
              'title': {
                'type': 'string',
                'minLength': 1,
                'description': 'Name of the event',
              },
            },
            'required': ['title'],
          },
        );

        if (!titleResult.accepted) {
          return CallToolResult.fromContent(
            content: [const TextContent(text: 'Event creation cancelled.')],
          );
        }

        final title = titleResult.content?['title'] as String;

        final descriptionResult = await server.elicitUserInput(
          'Enter event description (optional, or type "skip")',
          {
            'type': 'object',
            'properties': {
              'description': {
                'type': 'string',
                'minLength': 0,
                'description': 'Event description',
              },
            },
          },
        );

        final description = descriptionResult.accepted &&
                (descriptionResult.content?['description'] as String? ?? '')
                        .toLowerCase() !=
                    'skip'
            ? (descriptionResult.content?['description'] as String? ?? '')
            : '';

        // Step 2: Collect date and time
        final dateResult = await server.elicitUserInput(
          'Step 2: Enter event date (YYYY-MM-DD)',
          {
            'type': 'object',
            'properties': {
              'date': {
                'type': 'string',
                'pattern': r'^\d{4}-\d{2}-\d{2}$',
                'description': 'Event date in YYYY-MM-DD format',
              },
            },
            'required': ['date'],
          },
        );

        if (!dateResult.accepted) {
          return CallToolResult.fromContent(
            content: [const TextContent(text: 'Event creation cancelled.')],
          );
        }

        final date = dateResult.content?['date'] as String;

        final startTimeResult = await server.elicitUserInput(
          'Enter start time (HH:MM)',
          {
            'type': 'object',
            'properties': {
              'startTime': {
                'type': 'string',
                'pattern': r'^\d{2}:\d{2}$',
                'description': 'Event start time in HH:MM format',
              },
            },
            'required': ['startTime'],
          },
        );

        if (!startTimeResult.accepted) {
          return CallToolResult.fromContent(
            content: [const TextContent(text: 'Event creation cancelled.')],
          );
        }

        final startTime = startTimeResult.content?['startTime'] as String;

        final durationResult = await server.elicitUserInput(
          'Enter duration in minutes (15-480)',
          {
            'type': 'object',
            'properties': {
              'duration': {
                'type': 'number',
                'minimum': 15,
                'maximum': 480,
                'default': 60,
                'description': 'Duration in minutes',
              },
            },
          },
        );

        if (!durationResult.accepted) {
          return CallToolResult.fromContent(
            content: [const TextContent(text: 'Event creation cancelled.')],
          );
        }

        final duration = durationResult.content?['duration'] as num? ?? 60;

        // Return success response
        return CallToolResult.fromContent(
          content: [
            TextContent(
              text: '''Event created successfully!

Title: $title
Description: ${description.isEmpty ? '(none)' : description}
Date: $date
Start Time: $startTime
Duration: $duration minutes''',
            ),
          ],
        );
      } catch (error) {
        return CallToolResult.fromContent(
          content: [
            TextContent(text: 'Event creation failed: $error'),
          ],
          isError: true,
        );
      }
    },
  );

  // Example 3: Collecting address information
  // Demonstrates validation with patterns and optional fields
  server.tool(
    'update_shipping_address',
    description: 'Update shipping address with validation',
    toolInputSchema: const ToolInputSchema(properties: {}),
    callback: ({args, meta, extra}) async {
      try {
        // Collect name
        final nameResult = await server.elicitUserInput(
          'Enter recipient full name',
          {
            'type': 'object',
            'properties': {
              'name': {
                'type': 'string',
                'minLength': 1,
                'description': 'Recipient name',
              },
            },
            'required': ['name'],
          },
        );

        if (!nameResult.accepted) {
          return CallToolResult.fromContent(
            content: [
              const TextContent(text: 'Address update cancelled by user.'),
            ],
          );
        }

        final name = nameResult.content?['name'] as String;

        // Collect street address
        final streetResult = await server.elicitUserInput(
          'Enter street address',
          {
            'type': 'object',
            'properties': {
              'street': {
                'type': 'string',
                'minLength': 1,
                'description': 'Street address',
              },
            },
            'required': ['street'],
          },
        );

        if (!streetResult.accepted) {
          return CallToolResult.fromContent(
            content: [
              const TextContent(text: 'Address update cancelled by user.'),
            ],
          );
        }

        final street = streetResult.content?['street'] as String;

        // Collect city
        final cityResult = await server.elicitUserInput(
          'Enter city',
          {
            'type': 'object',
            'properties': {
              'city': {
                'type': 'string',
                'minLength': 1,
                'description': 'City name',
              },
            },
            'required': ['city'],
          },
        );

        if (!cityResult.accepted) {
          return CallToolResult.fromContent(
            content: [
              const TextContent(text: 'Address update cancelled by user.'),
            ],
          );
        }

        final city = cityResult.content?['city'] as String;

        // Collect state (2 letters)
        final stateResult = await server.elicitUserInput(
          'Enter state/province (2 letters)',
          {
            'type': 'object',
            'properties': {
              'state': {
                'type': 'string',
                'minLength': 2,
                'maxLength': 2,
                'pattern': r'^[A-Z]{2}$',
                'description': 'Two-letter state code (e.g., CA, NY)',
              },
            },
            'required': ['state'],
          },
        );

        if (!stateResult.accepted) {
          return CallToolResult.fromContent(
            content: [
              const TextContent(text: 'Address update cancelled by user.'),
            ],
          );
        }

        final state = stateResult.content?['state'] as String;

        // Collect ZIP code
        final zipResult = await server.elicitUserInput(
          'Enter ZIP/Postal code',
          {
            'type': 'object',
            'properties': {
              'zip': {
                'type': 'string',
                'minLength': 5,
                'maxLength': 10,
                'description': '5-digit ZIP code or postal code',
              },
            },
            'required': ['zip'],
          },
        );

        if (!zipResult.accepted) {
          return CallToolResult.fromContent(
            content: [
              const TextContent(text: 'Address update cancelled by user.'),
            ],
          );
        }

        final zipCode = zipResult.content?['zip'] as String;

        // Collect optional phone number
        final phoneResult = await server.elicitUserInput(
          'Enter phone number (optional, or type "skip")',
          {
            'type': 'object',
            'properties': {
              'phone': {
                'type': 'string',
                'minLength': 0,
                'description': 'Contact phone number',
              },
            },
          },
        );

        final phone = phoneResult.accepted &&
                (phoneResult.content?['phone'] as String? ?? '')
                        .toLowerCase() !=
                    'skip'
            ? (phoneResult.content?['phone'] as String? ?? '')
            : '';

        // Return success response
        return CallToolResult.fromContent(
          content: [
            TextContent(
              text: '''Address updated successfully!

$name
$street
$city, $state $zipCode${phone.isNotEmpty ? '\nPhone: $phone' : ''}''',
            ),
          ],
        );
      } catch (error) {
        return CallToolResult.fromContent(
          content: [
            TextContent(text: 'Address update failed: $error'),
          ],
          isError: true,
        );
      }
    },
  );

  return server;
}

void setCorsHeaders(HttpResponse response) {
  response.headers.set('Access-Control-Allow-Origin', '*');
  response.headers
      .set('Access-Control-Allow-Methods', 'GET, POST, DELETE, OPTIONS');
  response.headers.set(
    'Access-Control-Allow-Headers',
    'Origin, X-Requested-With, Content-Type, Accept, mcp-session-id, Last-Event-ID, Authorization',
  );
  response.headers.set('Access-Control-Allow-Credentials', 'true');
  response.headers.set('Access-Control-Max-Age', '86400');
  response.headers.set('Access-Control-Expose-Headers', 'mcp-session-id');
}

void main() async {
  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 3000;

  // Map to store transports by session ID
  final transports = <String, StreamableHTTPServerTransport>{};

  // Create HTTP server
  final httpServer = await HttpServer.bind(InternetAddress.anyIPv4, port);
  print('Elicitation example server is running on http://localhost:$port/mcp');
  print('Available tools:');
  print('  - register_user: Collect user registration information');
  print('  - create_event: Multi-step event creation');
  print('  - update_shipping_address: Collect and validate address');
  print('');
  print('Connect your MCP client to this server using the HTTP transport.');

  await for (final request in httpServer) {
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
      case 'POST':
        await _handlePostRequest(request, transports);
        break;
      case 'GET':
        await _handleGetRequest(request, transports);
        break;
      case 'DELETE':
        await _handleDeleteRequest(request, transports);
        break;
      default:
        request.response
          ..statusCode = HttpStatus.methodNotAllowed
          ..headers.set(HttpHeaders.allowHeader, 'GET, POST, DELETE, OPTIONS')
          ..write('Method Not Allowed')
          ..close();
    }
  }
}

// Check if a request is an initialization request
bool _isInitializeRequest(dynamic body) {
  return body is Map<String, dynamic> &&
      body.containsKey('method') &&
      body['method'] == 'initialize';
}

// Handle POST requests
Future<void> _handlePostRequest(
  HttpRequest request,
  Map<String, StreamableHTTPServerTransport> transports,
) async {
  try {
    // Parse the body
    final bodyBytes = await _collectBytes(request);
    final bodyString = utf8.decode(bodyBytes);
    final body = jsonDecode(bodyString);

    // Check for existing session ID
    final sessionId = request.headers.value('mcp-session-id');
    StreamableHTTPServerTransport? transport;

    if (sessionId != null && transports.containsKey(sessionId)) {
      // Reuse existing transport
      transport = transports[sessionId]!;
    } else if (sessionId == null && _isInitializeRequest(body)) {
      // New initialization request
      final eventStore = InMemoryEventStore();
      transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(
          sessionIdGenerator: () => generateUUID(),
          eventStore: eventStore,
          onsessioninitialized: (sessionId) {
            print('Session initialized with ID: $sessionId');
            transports[sessionId] = transport!;
          },
        ),
      );

      // Set up onclose handler
      transport.onclose = () {
        final sid = transport!.sessionId;
        if (sid != null && transports.containsKey(sid)) {
          print('Transport closed for session $sid');
          transports.remove(sid);
        }
      };

      // Connect the transport to the MCP server
      final server = getServer();
      await server.connect(transport);

      await transport.handleRequest(request, body);
      return;
    } else {
      // Invalid request
      request.response
        ..statusCode = HttpStatus.badRequest
        ..headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      setCorsHeaders(request.response);
      request.response
        ..write(
          jsonEncode({
            'jsonrpc': '2.0',
            'error': {
              'code': -32000,
              'message': 'Bad Request: No valid session ID provided',
            },
            'id': null,
          }),
        )
        ..close();
      return;
    }

    // Handle the request with existing transport
    await transport.handleRequest(request, body);
  } catch (error) {
    print('Error handling MCP request: $error');
    if (!request.response.headers.contentType
        .toString()
        .startsWith('text/event-stream')) {
      request.response
        ..statusCode = HttpStatus.internalServerError
        ..headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      setCorsHeaders(request.response);
      request.response
        ..write(
          jsonEncode({
            'jsonrpc': '2.0',
            'error': {
              'code': -32603,
              'message': 'Internal server error',
            },
            'id': null,
          }),
        )
        ..close();
    }
  }
}

// Handle GET requests for SSE streams
Future<void> _handleGetRequest(
  HttpRequest request,
  Map<String, StreamableHTTPServerTransport> transports,
) async {
  final sessionId = request.headers.value('mcp-session-id');
  if (sessionId == null || !transports.containsKey(sessionId)) {
    request.response.statusCode = HttpStatus.badRequest;
    setCorsHeaders(request.response);
    request.response
      ..write('Invalid or missing session ID')
      ..close();
    return;
  }

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
Future<void> _handleDeleteRequest(
  HttpRequest request,
  Map<String, StreamableHTTPServerTransport> transports,
) async {
  final sessionId = request.headers.value('mcp-session-id');
  if (sessionId == null || !transports.containsKey(sessionId)) {
    request.response.statusCode = HttpStatus.badRequest;
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
    if (!request.response.headers.contentType
        .toString()
        .startsWith('text/event-stream')) {
      request.response.statusCode = HttpStatus.internalServerError;
      setCorsHeaders(request.response);
      request.response
        ..write('Error processing session termination')
        ..close();
    }
  }
}

// Helper function to collect bytes from an HTTP request
Future<List<int>> _collectBytes(HttpRequest request) {
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
