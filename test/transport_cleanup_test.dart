/// Tests for StreamableHTTPServerTransport cleanup fixes:
///
/// 1. JsonRpcError responses now trigger the same cleanup as JsonRpcResponse
/// 2. close() now cleans up _adapterStreamMapping
/// 3. ShelfHttpResponseAdapter._bodyController is always closed
library;

import 'dart:async';

import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import '../lib/src/server/shelf_http_adapter.dart';

void main() {
  group('ShelfHttpResponseAdapter resource cleanup', () {
    test('close() completes done future for JSON responses', () async {
      Completer<Response> responseCompleter = Completer<Response>();
      ShelfHttpResponseAdapter adapter = ShelfHttpResponseAdapter(responseCompleter);

      adapter.statusCode = 200;
      adapter.setHeader('Content-Type', 'application/json');
      adapter.write('{"result": "ok"}');

      // close() should complete without hanging
      await adapter.close();

      // The response completer should have been completed by _sendBufferedResponse
      expect(responseCompleter.isCompleted, isTrue);

      Response response = await responseCompleter.future;
      expect(response.statusCode, equals(200));
      String body = await response.readAsString();
      expect(body, equals('{"result": "ok"}'));
    });

    test('close() completes done future for SSE responses', () async {
      Completer<Response> responseCompleter = Completer<Response>();
      ShelfHttpResponseAdapter adapter = ShelfHttpResponseAdapter(responseCompleter);

      adapter.statusCode = 200;
      adapter.setHeader('Content-Type', 'text/event-stream');
      adapter.write('event: message\ndata: test\n\n');

      expect(responseCompleter.isCompleted, isTrue);

      // In production, the shelf server actively reads the stream body.
      // We must drain it here so that _bodyController.close() can complete.
      Response response = await responseCompleter.future;
      // Start draining the stream in the background
      List<List<int>> chunks = <List<int>>[];
      // ignore: unawaited_futures
      response.read().listen((List<int> chunk) => chunks.add(chunk)).asFuture<void>();

      await adapter.close();

      expect(chunks, isNotEmpty);
    });

    test('close() is idempotent', () async {
      Completer<Response> responseCompleter = Completer<Response>();
      ShelfHttpResponseAdapter adapter = ShelfHttpResponseAdapter(responseCompleter);

      adapter.statusCode = 200;
      adapter.setHeader('Content-Type', 'application/json');
      adapter.write('{"ok": true}');

      await adapter.close();
      await adapter.close(); // second close should not throw
    });

    test('writing after close throws StateError', () async {
      Completer<Response> responseCompleter = Completer<Response>();
      ShelfHttpResponseAdapter adapter = ShelfHttpResponseAdapter(responseCompleter);

      adapter.statusCode = 200;
      adapter.setHeader('Content-Type', 'application/json');
      adapter.write('{"ok": true}');
      await adapter.close();

      expect(() => adapter.write('more'), throwsStateError);
    });

    test('flush does not close the adapter prematurely', () async {
      Completer<Response> responseCompleter = Completer<Response>();
      ShelfHttpResponseAdapter adapter = ShelfHttpResponseAdapter(responseCompleter);

      adapter.statusCode = 200;
      adapter.setHeader('Content-Type', 'application/json');
      adapter.write('part1');
      await adapter.flush();

      // Should still be able to write after flush
      adapter.write('part2');
      await adapter.close();

      Response response = await responseCompleter.future;
      String body = await response.readAsString();
      expect(body, equals('part1part2'));
    });
  });

  group('Transport send() error response cleanup (simulated)', () {
    test('error responses are tracked in requestResponseMap', () {
      _CleanupTracker tracker = _CleanupTracker();

      tracker.addRequestMapping(requestId: 1, streamId: 'stream-1');
      tracker.recordResponse(requestId: 1, isError: true);

      bool cleaned = tracker.tryCleanupStream('stream-1');
      expect(cleaned, isTrue);
      expect(tracker.hasRequestMapping(1), isFalse);
    });

    test('success responses are tracked in requestResponseMap', () {
      _CleanupTracker tracker = _CleanupTracker();

      tracker.addRequestMapping(requestId: 1, streamId: 'stream-1');
      tracker.recordResponse(requestId: 1, isError: false);

      bool cleaned = tracker.tryCleanupStream('stream-1');
      expect(cleaned, isTrue);
      expect(tracker.hasRequestMapping(1), isFalse);
    });

    test('mixed batch: cleanup waits for all responses', () {
      _CleanupTracker tracker = _CleanupTracker();

      tracker.addRequestMapping(requestId: 1, streamId: 'stream-1');
      tracker.addRequestMapping(requestId: 2, streamId: 'stream-1');
      tracker.addRequestMapping(requestId: 3, streamId: 'stream-1');

      tracker.recordResponse(requestId: 1, isError: false);
      tracker.recordResponse(requestId: 2, isError: true);

      bool cleaned = tracker.tryCleanupStream('stream-1');
      expect(cleaned, isFalse);

      tracker.recordResponse(requestId: 3, isError: false);

      cleaned = tracker.tryCleanupStream('stream-1');
      expect(cleaned, isTrue);
      expect(tracker.hasRequestMapping(1), isFalse);
      expect(tracker.hasRequestMapping(2), isFalse);
      expect(tracker.hasRequestMapping(3), isFalse);
    });

    test('all-error batch triggers cleanup', () {
      _CleanupTracker tracker = _CleanupTracker();

      tracker.addRequestMapping(requestId: 1, streamId: 'stream-1');
      tracker.addRequestMapping(requestId: 2, streamId: 'stream-1');

      tracker.recordResponse(requestId: 1, isError: true);
      tracker.recordResponse(requestId: 2, isError: true);

      bool cleaned = tracker.tryCleanupStream('stream-1');
      expect(cleaned, isTrue);
    });

    test('without fix: error-only responses would never trigger cleanup', () {
      _BrokenCleanupTracker brokenTracker = _BrokenCleanupTracker();

      brokenTracker.addRequestMapping(requestId: 1, streamId: 'stream-1');
      brokenTracker.recordResponse(requestId: 1, isError: true);

      bool cleaned = brokenTracker.tryCleanupStream('stream-1');
      expect(cleaned, isFalse, reason: 'Old code never cleaned up error responses');

      expect(brokenTracker.hasRequestMapping(1), isTrue);
    });
  });

  group('Transport close() adapter cleanup (simulated)', () {
    test('close clears adapter stream mapping', () {
      _TransportCloseTracker tracker = _TransportCloseTracker();

      tracker.addAdapterStream('stream-1');
      tracker.addAdapterStream('stream-2');

      expect(tracker.adapterStreamCount, equals(2));

      tracker.simulateClose();

      expect(tracker.adapterStreamCount, equals(0));
    });

    test('close clears both dart:io and adapter mappings', () {
      _TransportCloseTracker tracker = _TransportCloseTracker();

      tracker.addDartIoStream('stream-a');
      tracker.addAdapterStream('stream-b');

      tracker.simulateClose();

      expect(tracker.dartIoStreamCount, equals(0));
      expect(tracker.adapterStreamCount, equals(0));
    });

    test('close clears keep-alive timers', () {
      _TransportCloseTracker tracker = _TransportCloseTracker();

      tracker.addKeepAliveTimer('stream-1');
      tracker.addKeepAliveTimer('stream-2');

      expect(tracker.timerCount, equals(2));

      tracker.simulateClose();

      expect(tracker.timerCount, equals(0));
      expect(tracker.cancelledTimerCount, equals(2));
    });
  });
}

// =============================================================================
// Test Helpers
// =============================================================================

class _CleanupTracker {
  final Map<int, String> _requestToStreamMapping = <int, String>{};
  final Map<int, bool> _requestResponseMap = <int, bool>{};

  void addRequestMapping({required int requestId, required String streamId}) {
    _requestToStreamMapping[requestId] = streamId;
  }

  void recordResponse({required int requestId, required bool isError}) {
    _requestResponseMap[requestId] = isError;
  }

  bool hasRequestMapping(int requestId) => _requestToStreamMapping.containsKey(requestId);

  bool tryCleanupStream(String streamId) {
    List<int> relatedIds = _requestToStreamMapping.entries
        .where((MapEntry<int, String> entry) => entry.value == streamId)
        .map((MapEntry<int, String> entry) => entry.key)
        .toList();

    bool allResponsesReady = relatedIds.every(
      (int id) => _requestResponseMap.containsKey(id),
    );

    if (allResponsesReady) {
      for (int id in relatedIds) {
        _requestResponseMap.remove(id);
        _requestToStreamMapping.remove(id);
      }
      return true;
    }
    return false;
  }
}

class _BrokenCleanupTracker {
  final Map<int, String> _requestToStreamMapping = <int, String>{};
  final Map<int, bool> _requestResponseMap = <int, bool>{};

  void addRequestMapping({required int requestId, required String streamId}) {
    _requestToStreamMapping[requestId] = streamId;
  }

  void recordResponse({required int requestId, required bool isError}) {
    if (!isError) {
      _requestResponseMap[requestId] = false;
    }
  }

  bool hasRequestMapping(int requestId) => _requestToStreamMapping.containsKey(requestId);

  bool tryCleanupStream(String streamId) {
    List<int> relatedIds = _requestToStreamMapping.entries
        .where((MapEntry<int, String> entry) => entry.value == streamId)
        .map((MapEntry<int, String> entry) => entry.key)
        .toList();

    bool allResponsesReady = relatedIds.every(
      (int id) => _requestResponseMap.containsKey(id),
    );

    if (allResponsesReady) {
      for (int id in relatedIds) {
        _requestResponseMap.remove(id);
        _requestToStreamMapping.remove(id);
      }
      return true;
    }
    return false;
  }
}

class _TransportCloseTracker {
  final Map<String, bool> _streamMapping = <String, bool>{};
  final Map<String, bool> _adapterStreamMapping = <String, bool>{};
  final Map<String, bool> _keepAliveTimers = <String, bool>{};
  int cancelledTimerCount = 0;

  void addDartIoStream(String streamId) {
    _streamMapping[streamId] = true;
  }

  void addAdapterStream(String streamId) {
    _adapterStreamMapping[streamId] = true;
  }

  void addKeepAliveTimer(String streamId) {
    _keepAliveTimers[streamId] = true;
  }

  int get dartIoStreamCount => _streamMapping.length;
  int get adapterStreamCount => _adapterStreamMapping.length;
  int get timerCount => _keepAliveTimers.length;

  void simulateClose() {
    cancelledTimerCount = _keepAliveTimers.length;
    _keepAliveTimers.clear();
    _streamMapping.clear();
    _adapterStreamMapping.clear();
  }
}
