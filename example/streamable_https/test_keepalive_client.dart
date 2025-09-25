import 'dart:async';
import 'dart:convert';
import 'dart:io';

void main() async {
  print('MCP Keep-Alive Test Client');
  print('This client will connect to the server and monitor SSE keep-alive messages\n');

  try {
    // First, initialize the session
    print('1. Initializing session...');
    final initClient = HttpClient();
    final initRequest = await initClient.postUrl(Uri.parse('http://localhost:3001/mcp'));
    
    initRequest.headers.set('Content-Type', 'application/json');
    initRequest.headers.set('Accept', 'application/json, text/event-stream');
    
    initRequest.write(jsonEncode({
      'jsonrpc': '2.0',
      'method': 'initialize',
      'params': {
        'protocolVersion': '0.1.0',
        'capabilities': {
          'roots': {'listChanged': true},
          'sampling': {},
        },
        'clientInfo': {
          'name': 'test-client',
          'version': '1.0.0',
        },
      },
      'id': 1,
    }));
    
    final initResponse = await initRequest.close();
    final sessionId = initResponse.headers.value('mcp-session-id');
    
    if (sessionId == null) {
      print('ERROR: No session ID received');
      return;
    }
    
    print('Session initialized with ID: $sessionId');
    
    // Read the SSE stream
    final responseBody = StringBuffer();
    await for (final chunk in initResponse.transform(utf8.decoder)) {
      responseBody.write(chunk);
      // Print each SSE event as it arrives
      final lines = chunk.split('\n');
      for (final line in lines) {
        if (line.trim().isNotEmpty) {
          print('SSE: $line');
        }
      }
    }
    
    // Now establish SSE connection
    print('\n2. Establishing SSE connection to monitor keep-alive messages...');
    final sseClient = HttpClient();
    final sseRequest = await sseClient.getUrl(Uri.parse('http://localhost:3001/mcp'));
    
    sseRequest.headers.set('Accept', 'text/event-stream');
    sseRequest.headers.set('mcp-session-id', sessionId);
    
    final sseResponse = await sseRequest.close();
    
    if (sseResponse.statusCode != 200) {
      print('ERROR: SSE connection failed with status ${sseResponse.statusCode}');
      return;
    }
    
    print('SSE connection established, monitoring for keep-alive messages...');
    print('(Keep-alive messages should appear every 5 seconds)\n');
    
    // Create a timer to track time
    final startTime = DateTime.now();
    Timer.periodic(Duration(seconds: 1), (timer) {
      final elapsed = DateTime.now().difference(startTime).inSeconds;
      stdout.write('\rElapsed time: ${elapsed}s');
    });
    
    // Monitor the SSE stream
    int keepAliveCount = 0;
    await for (final chunk in sseResponse.transform(utf8.decoder)) {
      final lines = chunk.split('\n');
      for (final line in lines) {
        if (line.startsWith(':')) {
          // This is a comment/keep-alive message
          keepAliveCount++;
          print('\n[Keep-Alive #$keepAliveCount] $line');
          stdout.write('Elapsed time: ${DateTime.now().difference(startTime).inSeconds}s');
        } else if (line.trim().isNotEmpty) {
          // Other SSE messages
          print('\n[SSE Event] $line');
        }
      }
    }
    
  } catch (e) {
    print('Error: $e');
  }
}
