import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:mason/mason.dart';
import 'package:mcp_dart/mcp_dart.dart' hide Logger;
import 'package:mcp_dart_cli/src/doctor_command.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

class MockLogger extends Mock implements Logger {}

class RecordingMcpClient extends McpClient {
  RecordingMcpClient({this.resourceTemplatesError})
    : super(const Implementation(name: 'doctor-test', version: '1.0.0'));

  final Object? resourceTemplatesError;
  var toolCalls = 0;
  var resourceReads = 0;
  var promptGets = 0;

  @override
  ServerCapabilities? getServerCapabilities() => const ServerCapabilities(
    tools: ServerCapabilitiesTools(),
    resources: ServerCapabilitiesResources(),
    prompts: ServerCapabilitiesPrompts(),
  );

  @override
  Future<ListToolsResult> listTools({
    ListToolsRequest? params,
    RequestOptions? options,
  }) async => const ListToolsResult(tools: []);

  @override
  Future<ListResourcesResult> listResources({
    ListResourcesRequest? params,
    RequestOptions? options,
  }) async => const ListResourcesResult(resources: []);

  @override
  Future<ListResourceTemplatesResult> listResourceTemplates({
    ListResourceTemplatesRequest? params,
    RequestOptions? options,
  }) async {
    final error = resourceTemplatesError;
    if (error != null) {
      throw error;
    }
    return const ListResourceTemplatesResult(resourceTemplates: []);
  }

  @override
  Future<ListPromptsResult> listPrompts({
    ListPromptsRequest? params,
    RequestOptions? options,
  }) async => const ListPromptsResult(prompts: []);

  @override
  Future<CallToolResult> callTool(
    CallToolRequest params, {
    RequestOptions? options,
  }) async {
    toolCalls++;
    return const CallToolResult(content: []);
  }

  @override
  Future<ReadResourceResult> readResource(
    ReadResourceRequest params, [
    RequestOptions? options,
  ]) async {
    resourceReads++;
    return const ReadResourceResult(contents: []);
  }

  @override
  Future<GetPromptResult> getPrompt(
    GetPromptRequest params, [
    RequestOptions? options,
  ]) async {
    promptGets++;
    return const GetPromptResult(messages: []);
  }
}

void main() {
  group('DoctorCommand', () {
    late Logger logger;
    late DoctorCommand command;
    late Directory tempDir;
    late Directory originalCwd;

    setUp(() {
      logger = MockLogger();
      command = DoctorCommand(logger: logger);
      originalCwd = Directory.current;
      tempDir = Directory.systemTemp.createTempSync('doctor_test_');
      tempDir = Directory(tempDir.resolveSymbolicLinksSync());
      Directory.current = tempDir;
    });

    tearDown(() {
      try {
        Directory.current = originalCwd;
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('can be instantiated', () {
      expect(command, isA<DoctorCommand>());
    });

    test('static checks passed', () async {
      File(p.join(tempDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: test_project
dependencies:
  mcp: ^0.1.0
''');
      Directory(p.join(tempDir.path, 'lib', 'mcp')).createSync(recursive: true);
      File(
        p.join(tempDir.path, 'lib', 'mcp', 'mcp.dart'),
      ).writeAsStringSync('void main() {}');
      File(p.join(tempDir.path, 'analysis_options.yaml')).writeAsStringSync('');

      final runner = CommandRunner<int>('mcp_dart', 'CLI')..addCommand(command);
      // We expect software code (attempting connection) or config error if static fails.
      // Since it's a dummy project, dynamic check will fail to connect/run runner, so it likely returns software error or connection error.
      // But we verify static checks printed success.
      await runner.run(['doctor']);

      verify(() => logger.success('[✓] pubspec.yaml exists')).called(1);
      verify(() => logger.success('[✓] mcp dependency found')).called(1);
      verify(() => logger.success('[✓] lib/mcp/mcp.dart exists')).called(1);
    });

    test('fails if pubspec.yaml is missing', () async {
      final runner = CommandRunner<int>('mcp_dart', 'CLI')..addCommand(command);
      await runner.run(['doctor']);
      verify(() => logger.err('[x] pubspec.yaml not found')).called(1);
    });

    test('dynamic inventory never invokes advertised primitives', () async {
      final client = RecordingMcpClient();

      expect(await verifyAdvertisedInventory(client, logger), isTrue);
      expect(client.toolCalls, isZero);
      expect(client.resourceReads, isZero);
      expect(client.promptGets, isZero);
      verify(() => logger.success('[✓] Listed 0 tools')).called(1);
      verify(() => logger.success('[✓] Listed 0 resources')).called(1);
      verify(
        () => logger.success('[✓] Listed 0 resource templates'),
      ).called(1);
      verify(() => logger.success('[✓] Listed 0 prompts')).called(1);
    });

    test('attributes resource template inventory failures', () async {
      final client = RecordingMcpClient(
        resourceTemplatesError: StateError('templates unavailable'),
      );

      expect(await verifyAdvertisedInventory(client, logger), isFalse);
      verify(() => logger.success('[✓] Listed 0 resources')).called(1);
      verify(
        () => logger.err(
          '[x] Failed to list resource templates: '
          'Bad state: templates unavailable',
        ),
      ).called(1);
      verifyNever(
        () => logger.err(
          '[x] Failed to list resources: Bad state: templates unavailable',
        ),
      );
    });
  });
}
