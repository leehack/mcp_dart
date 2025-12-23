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
  server.registerTool(
    'register_user',
    description: 'Register a new user account by collecting their information',
    inputSchema: JsonSchema.object(properties: {}),
    callback: (args, extra) async {
      try {
        // Collect username
        final usernameResult = await server.elicitInput(
          ElicitRequest.form(
            message: 'Enter your username (3-20 characters)',
            requestedSchema: JsonSchema.object(
              properties: {
                'username': JsonSchema.string(
                  minLength: 3,
                  maxLength: 20,
                  description: 'Your desired username',
                ),
              },
              required: ['username'],
            ),
          ),
        );

        if (!usernameResult.accepted) {
          return CallToolResult.fromContent(
            [
              const TextContent(text: 'Registration cancelled by user.'),
            ],
          );
        }

        final username = usernameResult.content?['username'] as String;

        // Collect email
        final emailResult = await server.elicitInput(
          ElicitRequest.form(
            message: 'Enter your email address',
            requestedSchema: JsonSchema.object(
              properties: {
                'email': JsonSchema.string(
                  minLength: 3,
                  description: 'Your email address',
                ),
              },
              required: ['email'],
            ),
          ),
        );

        if (!emailResult.accepted) {
          return CallToolResult.fromContent(
            [
              const TextContent(text: 'Registration cancelled by user.'),
            ],
          );
        }

        final email = emailResult.content?['email'] as String;

        // Collect password
        final passwordResult = await server.elicitInput(
          ElicitRequest.form(
            message: 'Enter your password (min 8 characters)',
            requestedSchema: JsonSchema.object(
              properties: {
                'password': JsonSchema.string(
                  minLength: 8,
                  description: 'Your password',
                ),
              },
              required: ['password'],
            ),
          ),
        );

        if (!passwordResult.accepted) {
          return CallToolResult.fromContent(
            [
              const TextContent(text: 'Registration cancelled by user.'),
            ],
          );
        }

        // Collect newsletter preference
        final newsletterResult = await server.elicitInput(
          ElicitRequest.form(
            message: 'Subscribe to newsletter?',
            requestedSchema: JsonSchema.object(
              properties: {
                'newsletter': JsonSchema.boolean(
                  defaultValue: false,
                  description: 'Receive updates via email',
                ),
              },
            ),
          ),
        );

        final newsletter = newsletterResult.accepted
            ? (newsletterResult.content?['newsletter'] as bool? ?? false)
            : false;

        // Return success response
        return CallToolResult.fromContent(
          [
            TextContent(
              text: '''Registration successful!

Username: $username
Email: $email
Newsletter: ${newsletter ? 'Yes' : 'No'}''',
            ),
          ],
        );
      } catch (error) {
        return CallToolResult(
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
  server.registerTool(
    'create_event',
    description: 'Create a calendar event by collecting event details',
    inputSchema: JsonSchema.object(properties: {}),
    callback: (args, extra) async {
      try {
        // Step 1: Collect basic event information
        final titleResult = await server.elicitInput(
          ElicitRequest.form(
            message: 'Step 1: Enter event title',
            requestedSchema: JsonSchema.object(
              properties: {
                'title': JsonSchema.string(
                  minLength: 1,
                  description: 'Name of the event',
                ),
              },
              required: ['title'],
            ),
          ),
        );

        if (!titleResult.accepted) {
          return CallToolResult.fromContent(
            [const TextContent(text: 'Event creation cancelled.')],
          );
        }

        final title = titleResult.content?['title'] as String;

        final descriptionResult = await server.elicitInput(
          ElicitRequest.form(
            message: 'Enter event description (optional, or type "skip")',
            requestedSchema: JsonSchema.object(
              properties: {
                'description': JsonSchema.string(
                  minLength: 0,
                  description: 'Event description',
                ),
              },
            ),
          ),
        );

        final description = descriptionResult.accepted &&
                (descriptionResult.content?['description'] as String? ?? '')
                        .toLowerCase() !=
                    'skip'
            ? (descriptionResult.content?['description'] as String? ?? '')
            : '';

        // Step 2: Collect date and time
        final dateResult = await server.elicitInput(
          ElicitRequest.form(
            message: 'Step 2: Enter event date (YYYY-MM-DD)',
            requestedSchema: JsonSchema.object(
              properties: {
                'date': JsonSchema.string(
                  pattern: r'^\d{4}-\d{2}-\d{2}$',
                  description: 'Event date in YYYY-MM-DD format',
                ),
              },
              required: ['date'],
            ),
          ),
        );

        if (!dateResult.accepted) {
          return CallToolResult.fromContent(
            [const TextContent(text: 'Event creation cancelled.')],
          );
        }

        final date = dateResult.content?['date'] as String;

        final startTimeResult = await server.elicitInput(
          ElicitRequest.form(
            message: 'Enter start time (HH:MM)',
            requestedSchema: JsonSchema.object(
              properties: {
                'startTime': JsonSchema.string(
                  pattern: r'^\d{2}:\d{2}$',
                  description: 'Event start time in HH:MM format',
                ),
              },
              required: ['startTime'],
            ),
          ),
        );

        if (!startTimeResult.accepted) {
          return CallToolResult.fromContent(
            [const TextContent(text: 'Event creation cancelled.')],
          );
        }

        final startTime = startTimeResult.content?['startTime'] as String;

        final durationResult = await server.elicitInput(
          ElicitRequest.form(
            message: 'Enter duration in minutes (15-480)',
            requestedSchema: JsonSchema.object(
              properties: {
                'duration': JsonSchema.number(
                  minimum: 15,
                  maximum: 480,
                  defaultValue: 60,
                  description: 'Duration in minutes',
                ),
              },
            ),
          ),
        );

        if (!durationResult.accepted) {
          return CallToolResult.fromContent(
            [const TextContent(text: 'Event creation cancelled.')],
          );
        }

        final duration = durationResult.content?['duration'] as num? ?? 60;

        // Return success response
        return CallToolResult.fromContent(
          [
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
        return CallToolResult(
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
  server.registerTool(
    'update_shipping_address',
    description: 'Update shipping address with validation',
    inputSchema: JsonSchema.object(properties: {}),
    callback: (args, extra) async {
      try {
        // Collect name
        final nameResult = await server.elicitInput(
          ElicitRequest.form(
            message: 'Enter recipient full name',
            requestedSchema: JsonSchema.object(
              properties: {
                'name': JsonSchema.string(
                  minLength: 1,
                  description: 'Recipient name',
                ),
              },
              required: ['name'],
            ),
          ),
        );

        if (!nameResult.accepted) {
          return CallToolResult.fromContent(
            [
              const TextContent(text: 'Address update cancelled by user.'),
            ],
          );
        }

        final name = nameResult.content?['name'] as String;

        // Collect street address
        final streetResult = await server.elicitInput(
          ElicitRequest.form(
            message: 'Enter street address',
            requestedSchema: JsonSchema.object(
              properties: {
                'street': JsonSchema.string(
                  minLength: 1,
                  description: 'Street address',
                ),
              },
              required: ['street'],
            ),
          ),
        );

        if (!streetResult.accepted) {
          return CallToolResult.fromContent(
            [
              const TextContent(text: 'Address update cancelled by user.'),
            ],
          );
        }

        final street = streetResult.content?['street'] as String;

        // Collect city
        final cityResult = await server.elicitInput(
          ElicitRequest.form(
            message: 'Enter city',
            requestedSchema: JsonSchema.object(
              properties: {
                'city': JsonSchema.string(
                  minLength: 1,
                  description: 'City name',
                ),
              },
              required: ['city'],
            ),
          ),
        );

        if (!cityResult.accepted) {
          return CallToolResult.fromContent(
            [
              const TextContent(text: 'Address update cancelled by user.'),
            ],
          );
        }

        final city = cityResult.content?['city'] as String;

        // Collect state (2 letters)
        final stateResult = await server.elicitInput(
          ElicitRequest.form(
            message: 'Enter state/province (2 letters)',
            requestedSchema: JsonSchema.object(
              properties: {
                'state': JsonSchema.string(
                  minLength: 2,
                  maxLength: 2,
                  pattern: r'^[A-Z]{2}$',
                  description: 'Two-letter state code (e.g., CA, NY)',
                ),
              },
              required: ['state'],
            ),
          ),
        );

        if (!stateResult.accepted) {
          return CallToolResult.fromContent(
            [
              const TextContent(text: 'Address update cancelled by user.'),
            ],
          );
        }

        final state = stateResult.content?['state'] as String;

        // Collect ZIP code
        final zipResult = await server.elicitInput(
          ElicitRequest.form(
            message: 'Enter ZIP/Postal code',
            requestedSchema: JsonSchema.object(
              properties: {
                'zip': JsonSchema.string(
                  minLength: 5,
                  maxLength: 10,
                  description: '5-digit ZIP code or postal code',
                ),
              },
              required: ['zip'],
            ),
          ),
        );

        if (!zipResult.accepted) {
          return CallToolResult.fromContent(
            [
              const TextContent(text: 'Address update cancelled by user.'),
            ],
          );
        }

        final zipCode = zipResult.content?['zip'] as String;

        // Collect optional phone number
        final phoneResult = await server.elicitInput(
          ElicitRequest.form(
            message: 'Enter phone number (optional, or type "skip")',
            requestedSchema: JsonSchema.object(
              properties: {
                'phone': JsonSchema.string(
                  minLength: 0,
                  description: 'Contact phone number',
                ),
              },
            ),
          ),
        );

        final phone = phoneResult.accepted &&
                (phoneResult.content?['phone'] as String? ?? '')
                        .toLowerCase() !=
                    'skip'
            ? (phoneResult.content?['phone'] as String? ?? '')
            : '';

        // Return success response
        return CallToolResult.fromContent(
          [
            TextContent(
              text: '''Address updated successfully!

$name
$street
$city, $state $zipCode${phone.isNotEmpty ? '\nPhone: $phone' : ''}''',
            ),
          ],
        );
      } catch (error) {
        return CallToolResult(
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
      request.response.write(
        jsonEncode(
          JsonRpcError(
            id: null,
            error: JsonRpcErrorData(
              code: ErrorCode.connectionClosed.value,
              message:
                  'Bad Request: No valid session ID provided or not an initialization request',
            ),
          ).toJson(),
        ),
      );
      request.response.close();
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
      request.response.write(
        jsonEncode(
          JsonRpcError(
            id: null,
            error: JsonRpcErrorData(
              code: ErrorCode.internalError.value,
              message: 'Internal server error',
            ),
          ).toJson(),
        ),
      );
      request.response.close();
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
