/// Proof-of-Concept Test for Shelf HTTP Adapter
/// 
/// This validates that the shelf adapter can handle the write pattern
/// used by StreamableHTTPServerTransport (multiple writes, flush, close).
/// 
/// Note: These tests focus on validating the adapter works, not on testing
/// full streaming behavior which requires more complex async handling.
library;

import 'dart:async';
import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import '../lib/src/server/shelf_http_adapter.dart';

void main() {
  group('ShelfHttpAdapter POC', () {
    test('basic write and response creation works', () async {
      // Create a mock request
      final request = Request('POST', Uri.parse('http://localhost/test'));

      // Create the adapter
      final responseCompleter = Completer<Response>();
      final adapter = ShelfHttpAdapter(request, responseCompleter);

      // Set headers and status
      adapter.response.statusCode = 200;
      adapter.response.setHeader('Content-Type', 'text/event-stream');
      adapter.response.setHeader('Cache-Control', 'no-cache');

      // Write data - this should trigger response creation
      adapter.response.write('event: message\ndata: test\n\n');
      await adapter.response.flush();

      // Response should be created now
      final response = await adapter.shelfResponse;
      
      // Verify response was created with correct headers
      expect(response.statusCode, equals(200));
      expect(response.headers['content-type'], equals('text/event-stream'));
      expect(response.headers['cache-control'], equals('no-cache'));
    });

    test('response headers are set correctly', () async {
      final request = Request('GET', Uri.parse('http://localhost/test'));
      final responseCompleter = Completer<Response>();
      final adapter = ShelfHttpAdapter(request, responseCompleter);

      adapter.response.statusCode = 404;
      adapter.response.setHeader('Content-Type', 'application/json');
      adapter.response.setHeader('X-Custom-Header', 'test-value');
      adapter.response.write('{"error": "Not Found"}');
      await adapter.response.flush();

      final response = await adapter.shelfResponse;
      expect(response.statusCode, equals(404));
      expect(response.headers['content-type'], equals('application/json'));
      expect(response.headers['x-custom-header'], equals('test-value'));
    });

    test('can read request headers (case-insensitive)', () {
      final request = Request(
        'POST',
        Uri.parse('http://localhost/test'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'text/event-stream',
          'mcp-session-id': 'test-session-123',
        },
      );

      final responseCompleter = Completer<Response>();
      final adapter = ShelfHttpAdapter(request, responseCompleter);

      // Test case-insensitive header access
      expect(adapter.getHeader('content-type'), equals('application/json'));
      expect(adapter.getHeader('Content-Type'), equals('application/json'));
      expect(adapter.getHeader('CONTENT-TYPE'), equals('application/json'));

      expect(adapter.getHeader('accept'), equals('text/event-stream'));
      expect(adapter.getHeader('mcp-session-id'), equals('test-session-123'));
      expect(adapter.getHeader('non-existent'), isNull);
    });

    test('can read request body stream', () async {
      final testBody = '{"jsonrpc": "2.0", "method": "initialize", "id": 1}';
      final request = Request(
        'POST',
        Uri.parse('http://localhost/test'),
        body: testBody,
      );

      final responseCompleter = Completer<Response>();
      final adapter = ShelfHttpAdapter(request, responseCompleter);

      // Read body stream
      final bodyChunks = <List<int>>[];
      await for (final chunk in adapter.bodyStream) {
        bodyChunks.add(chunk);
      }

      final bodyString = utf8.decode(bodyChunks.expand((x) => x).toList());
      expect(bodyString, equals(testBody));
    });

    test('contentType is parsed correctly', () {
      final request = Request(
        'POST',
        Uri.parse('http://localhost/test'),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );

      final responseCompleter = Completer<Response>();
      final adapter = ShelfHttpAdapter(request, responseCompleter);

      expect(adapter.contentType, isNotNull);
      expect(adapter.contentType!.mimeType, equals('application/json'));
      expect(adapter.contentType!.charset, equals('utf-8'));
    });

    test('contentType returns null for missing header', () {
      final request = Request('GET', Uri.parse('http://localhost/test'));

      final responseCompleter = Completer<Response>();
      final adapter = ShelfHttpAdapter(request, responseCompleter);

      expect(adapter.contentType, isNull);
    });

    test('cannot modify response after it has been sent', () async {
      final request = Request('POST', Uri.parse('http://localhost/test'));
      final responseCompleter = Completer<Response>();
      final adapter = ShelfHttpAdapter(request, responseCompleter);

      // Send response by writing data and flushing (finalizes the response)
      adapter.response.write('test');
      await adapter.response.flush();

      // Try to modify - should throw
      expect(() => adapter.response.statusCode = 404, throwsStateError);
      expect(
        () => adapter.response.setHeader('X-Test', 'value'),
        throwsStateError,
      );
    });

    test('multiple writes accumulate correctly', () async {
      final request = Request('POST', Uri.parse('http://localhost/test'));
      final responseCompleter = Completer<Response>();
      final adapter = ShelfHttpAdapter(request, responseCompleter);

      adapter.response.statusCode = 200;
      
      // Multiple writes before flush
      adapter.response.write('line1\n');
      adapter.response.write('line2\n');
      adapter.response.write('line3\n');
      await adapter.response.flush();

      // Response should now exist
      final response = await adapter.shelfResponse;
      expect(response.statusCode, equals(200));

      final body = await response.readAsString();
      expect(body, equals('line1\nline2\nline3\n'));
    });
  });
}

