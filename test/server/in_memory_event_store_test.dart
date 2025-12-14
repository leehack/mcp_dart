import 'package:mcp_dart/src/server/in_memory_event_store.dart';
import 'package:mcp_dart/src/types.dart';
import 'package:test/test.dart';

void main() {
  group('InMemoryEventStore', () {
    late InMemoryEventStore store;

    setUp(() {
      store = InMemoryEventStore();
    });

    test('storeEvent assigns increasing IDs', () async {
      final msg1 = const JsonRpcNotification(method: 'test');
      final msg2 = const JsonRpcNotification(method: 'test2');

      final id1 = await store.storeEvent('stream1', msg1);
      final id2 = await store.storeEvent('stream1', msg2);

      expect(int.parse(id1), lessThan(int.parse(id2)));
    });

    test('replayEventsAfter replays events for correct stream', () async {
      final msg1 = const JsonRpcNotification(method: '1');
      final msg2 = const JsonRpcNotification(method: '2');
      final msg3 = const JsonRpcNotification(method: '3');

      final id1 = await store.storeEvent('stream1', msg1);
      final id2 = await store.storeEvent('stream1', msg2);
      final id3 = await store.storeEvent('stream1', msg3);
      final replayedEvents = <({String id, JsonRpcMessage message})>[];

      final streamId = await store.replayEventsAfter(
        id1,
        send: (id, msg) async {
          replayedEvents.add((id: id, message: msg));
        },
      );

      expect(streamId, 'stream1');
      expect(replayedEvents.length, 2);
      expect(replayedEvents[0].id, id2);
      expect(replayedEvents[0].message, msg2);
      expect(replayedEvents[1].id, id3);
      expect(replayedEvents[1].message, msg3);
    });

    test('replayEventsAfter throws if event ID not found', () async {
      expect(
        () => store.replayEventsAfter('non-existent', send: (_, __) async {}),
        throwsStateError,
      );
    });

    test('replayEventsAfter handles multiple streams', () async {
      final msgA1 = const JsonRpcNotification(method: 'A1');
      final msgB1 = const JsonRpcNotification(method: 'B1');
      final msgA2 = const JsonRpcNotification(method: 'A2');

      final idA1 = await store.storeEvent('streamA', msgA1);
      await store.storeEvent('streamB', msgB1);
      final idA2 = await store.storeEvent('streamA', msgA2);

      final replayedEvents = <({String id, JsonRpcMessage message})>[];

      final streamId = await store.replayEventsAfter(
        idA1,
        send: (id, msg) async {
          replayedEvents.add((id: id, message: msg));
        },
      );

      expect(streamId, 'streamA');
      expect(replayedEvents.length, 1);
      expect(replayedEvents[0].id, idA2);
    });
  });
}
