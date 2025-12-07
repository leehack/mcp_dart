import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

// Mock Transport
class MockTransport implements Transport {
  @override
  String? sessionId;

  @override
  void Function()? onclose;

  @override
  void Function(Error error)? onerror;

  @override
  void Function(JsonRpcMessage message)? onmessage;

  final List<JsonRpcMessage> sentMessages = [];
  final Map<String, JsonRpcMessage> responses = {};

  @override
  Future<void> close() async {
    onclose?.call();
  }

  @override
  Future<void> send(JsonRpcMessage message) async {
    sentMessages.add(message);
    if (message is JsonRpcRequest) {
      if (responses.containsKey(message.method)) {
        final response = responses[message.method]!;
        // Use result or error
        if (response is JsonRpcResponse) {
          // Construct response with matching ID
          onmessage?.call(JsonRpcResponse(id: message.id, result: response.result));
        } else if (response is JsonRpcError) {
           onmessage?.call(JsonRpcError(id: message.id, error: response.error));
        }
      }
    }
  }

  @override
  Future<void> start() async {}
}

void main() {
  group('Client Tasks', () {
    late Client client;
    late MockTransport transport;

    setUp(() {
      transport = MockTransport();
      client = Client(
        Implementation(name: 'test-client', version: '1.0.0'),
        options: ClientOptions(
          capabilities: ClientCapabilities(
            tasks: ClientCapabilitiesTasks(list: true, cancel: true),
          ),
        ),
      );
    });

    test('listTasks sends correct request', () async {
      // Mock initialize response to advertise task support
      transport.responses['initialize'] = JsonRpcResponse(
        id: 1,
        result: InitializeResult(
          protocolVersion: latestProtocolVersion,
          capabilities: ServerCapabilities(
            tasks: ServerCapabilitiesTasks(list: true),
          ),
          serverInfo: Implementation(name: 'test-server', version: '1.0.0'),
        ).toJson(),
      );

      transport.responses['tasks/list'] = JsonRpcResponse(
        id: 2,
        result: ListTasksResult(tasks: []).toJson(),
      );

      await client.connect(transport);
      await client.listTasks();

      final listReq = transport.sentMessages.last as JsonRpcRequest;
      expect(listReq.method, 'tasks/list');
    });

    test('cancelTask sends correct request', () async {
       // Mock initialize response
      transport.responses['initialize'] = JsonRpcResponse(
        id: 1,
        result: InitializeResult(
          protocolVersion: latestProtocolVersion,
          capabilities: ServerCapabilities(
            tasks: ServerCapabilitiesTasks(cancel: true),
          ),
          serverInfo: Implementation(name: 'test-server', version: '1.0.0'),
        ).toJson(),
      );

      // Cancel result is a Task
      final task = Task(
          taskId: '1', status: TaskStatus.cancelled, createdAt: '', lastUpdatedAt: '');
      transport.responses['tasks/cancel'] = JsonRpcResponse(
        id: 2,
        result: CancelTaskResult(task: task).toJson(),
      );

      await client.connect(transport);
      await client.cancelTask(CancelTaskRequestParams(taskId: '1'));

      final req = transport.sentMessages.last as JsonRpcRequest;
      expect(req.method, 'tasks/cancel');
      expect(req.params?['taskId'], '1');
    });
  });
}
