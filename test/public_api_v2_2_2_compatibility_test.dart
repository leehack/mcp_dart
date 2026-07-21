import 'dart:async';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

FutureOr<CallToolResult> _toolImplementation(
  Map<String, dynamic> args,
  RequestHandlerExtra extra,
) =>
    const CallToolResult(content: []);

FutureOr<CallToolResult> _legacyToolImplementation({
  Map<String, dynamic>? args,
  RequestHandlerExtra? extra,
}) =>
    const CallToolResult(content: []);

FutureOr<GetPromptResult> _promptImplementation(
  Map<String, dynamic>? args,
  RequestHandlerExtra? extra,
) =>
    const GetPromptResult(messages: []);

FutureOr<ReadResourceResult> _resourceImplementation(
  Uri uri,
  RequestHandlerExtra extra,
) =>
    const ReadResourceResult(contents: []);

FutureOr<ReadResourceResult> _resourceTemplateImplementation(
  Uri uri,
  Map<String, Object?> variables,
  RequestHandlerExtra extra,
) =>
    const ReadResourceResult(contents: []);

final class _V222McpClientSubclass extends McpClient {
  _V222McpClientSubclass()
      : super(
          const Implementation(name: 'v2.2.2-subclass', version: '1.0.0'),
        );

  @override
  Future<T> request<T extends BaseResultData>(
    JsonRpcRequest requestData,
    T Function(Map<String, dynamic> resultJson) resultFactory, [
    RequestOptions? options,
    int? relatedRequestId,
  ]) {
    return super.request(
      requestData,
      resultFactory,
      options,
      relatedRequestId,
    );
  }

  @override
  // Deliberately preserves the published v2.2.2 override shape.
  // ignore: unnecessary_overrides
  Future<void> notification(
    JsonRpcNotification notificationData, {
    RelatedTaskMetadata? relatedTask,
    int? relatedRequestId,
  }) {
    return super.notification(
      notificationData,
      relatedTask: relatedTask,
      relatedRequestId: relatedRequestId,
    );
  }
}

final class _V222StreamableHttpTransport extends StreamableHttpClientTransport {
  _V222StreamableHttpTransport() : super(Uri.parse('http://localhost/mcp'));

  @override
  // Deliberately preserves the published v2.2.2 override shape.
  // ignore: deprecated_member_use_from_same_package, unnecessary_overrides
  Future<void> finishAuth(String authorizationCode) {
    return super.finishAuth(authorizationCode);
  }
}

final class _V222RegisteredTool implements RegisteredTool {
  @override
  String name = 'legacy';

  @override
  String? title;

  @override
  String? description;

  @override
  ToolInputSchema? inputSchema;

  @override
  ToolOutputSchema? outputSchema;

  @override
  ToolAnnotations? annotations;

  @override
  ToolExecution? execution;

  @override
  ToolCallback? callback;

  @override
  bool enabled = true;

  @override
  void disable() => enabled = false;

  @override
  void enable() => enabled = true;

  @override
  void remove() => enabled = false;

  @override
  void update({
    String? name,
    String? title,
    String? description,
    ToolInputSchema? inputSchema,
    ToolOutputSchema? outputSchema,
    ToolAnnotations? annotations,
    ToolExecution? execution,
    ToolCallback? callback,
    bool? enabled,
  }) {
    this.name = name ?? this.name;
    this.title = title ?? this.title;
    this.description = description ?? this.description;
    this.inputSchema = inputSchema ?? this.inputSchema;
    this.outputSchema = outputSchema ?? this.outputSchema;
    this.annotations = annotations ?? this.annotations;
    this.execution = execution ?? this.execution;
    this.callback = callback ?? this.callback;
    this.enabled = enabled ?? this.enabled;
  }
}

void main() {
  test('published callback typedefs retain their 2.2.2 signatures', () {
    final ToolFunction tool = _toolImplementation;
    final LegacyToolCallback legacyTool = _legacyToolImplementation;
    final PromptCallback prompt = _promptImplementation;
    final ReadResourceCallback resource = _resourceImplementation;
    final ReadResourceTemplateCallback resourceTemplate =
        _resourceTemplateImplementation;

    final FutureOr<CallToolResult> Function(
      Map<String, dynamic>,
      RequestHandlerExtra,
    ) toolRoundTrip = tool;
    final FutureOr<GetPromptResult> Function(
      Map<String, dynamic>?,
      RequestHandlerExtra?,
    ) promptRoundTrip = prompt;

    expect(toolRoundTrip, same(tool));
    expect(promptRoundTrip, same(prompt));
    expect(legacyTool, same(_legacyToolImplementation));
    expect(resource, same(_resourceImplementation));
    expect(resourceTemplate, same(_resourceTemplateImplementation));
    expect(FunctionToolCallback(tool).function, same(tool));
  });

  test('a 2.2.2 RegisteredTool implementation still satisfies the interface',
      () {
    final RegisteredTool tool = _V222RegisteredTool();

    tool.update(
      name: 'updated',
      outputSchema: const ToolOutputSchema(),
      enabled: false,
    );

    expect(tool.name, 'updated');
    expect(tool.outputSchema, isA<ToolOutputSchema>());
    expect(tool.enabled, isFalse);
  });

  test('a 2.2.2 McpClient subclass can retain request ID overrides', () {
    expect(_V222McpClientSubclass(), isA<McpClient>());
  });

  test('a 2.2.2 transport subclass can retain its finishAuth override', () {
    expect(
      _V222StreamableHttpTransport(),
      isA<StreamableHttpClientTransport>(),
    );
  });

  test('multi-round callbacks use additive stateless registration APIs', () {
    final server = McpServer(
      const Implementation(name: 'compatibility-test', version: '1.0.0'),
    );

    final RegisteredStatelessTool tool = server.registerStatelessTool(
      'multi_round_tool',
      callback: (args, extra) =>
          const InputRequiredResult(requestState: 'tool-state'),
    );
    server.registerStatelessPrompt(
      'multi_round_prompt',
      callback: (args, extra) =>
          const InputRequiredResult(requestState: 'prompt-state'),
    );
    final resource = server.registerStatelessResource(
      'multi_round_resource',
      'memory://multi-round',
      null,
      (uri, extra) => const InputRequiredResult(requestState: 'resource-state'),
    );
    final resourceTemplate = server.registerStatelessResourceTemplate(
      'multi_round_template',
      ResourceTemplateRegistration(
        'memory://{id}',
        listCallback: (extra) => const ListResourcesResult(resources: []),
      ),
      null,
      (uri, variables, extra) =>
          const InputRequiredResult(requestState: 'template-state'),
    );

    expect(tool, isA<RegisteredTool>());
    expect(resource, isA<RegisteredResource>());
    expect(resourceTemplate, isA<RegisteredResourceTemplate>());
  });

  test('the public barrel exports JSON Schema validation', () {
    final schema = JsonSchema.string(minLength: 2);

    schema.validate('ok');
    expect(
      () => schema.validate('x'),
      throwsA(isA<JsonSchemaValidationException>()),
    );
  });
}
