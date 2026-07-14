import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:mcp_dart/mcp_dart.dart' as mcp_dart;

/// Executes an MCP tool call.
typedef McpToolCaller =
    Future<mcp_dart.CallToolResult> Function(mcp_dart.CallToolRequest request);

/// Decides whether a Gemini-requested MCP tool call may run.
typedef McpToolApprover =
    Future<bool> Function(String name, Map<String, Object?> arguments);

/// Retrieves one page of MCP tools.
typedef McpToolLister =
    Future<mcp_dart.ListToolsResult> Function(
      mcp_dart.ListToolsRequest? request,
    );

/// Reads one line of interactive input, or returns `null` at end of input.
typedef GeminiLineReader = Future<String?> Function();

/// Writes one line of interactive output.
typedef GeminiLineWriter = void Function(String message);

/// An error returned by the Gemini Interactions API.
final class GeminiApiException implements Exception {
  /// The HTTP status code returned by Gemini.
  final int statusCode;

  /// A concise, credential-free description of the API failure.
  final String message;

  /// Creates an API exception.
  const GeminiApiException(this.statusCode, this.message);

  @override
  String toString() => 'Gemini API request failed (HTTP $statusCode): $message';
}

/// A minimal client for Gemini's REST Interactions API.
final class GeminiInteractionsApi {
  /// The model sent with every interaction.
  final String model;

  final String _apiKey;
  final http.Client _httpClient;
  final Uri _endpoint;
  bool _closed = false;

  /// Creates a Gemini Interactions API client.
  GeminiInteractionsApi({
    required String apiKey,
    this.model = 'gemini-3.5-flash',
    http.Client? httpClient,
    Uri? endpoint,
  }) : _apiKey = apiKey,
       _httpClient = httpClient ?? http.Client(),
       _endpoint =
           endpoint ??
           Uri.parse(
             'https://generativelanguage.googleapis.com/v1beta/interactions',
           ) {
    if (apiKey.trim().isEmpty) {
      throw ArgumentError.value(apiKey, 'apiKey', 'must not be empty');
    }
    if (model.trim().isEmpty) {
      throw ArgumentError.value(model, 'model', 'must not be empty');
    }
  }

  /// Creates one stored interaction.
  ///
  /// [previousInteractionId] chains a tool-result turn to the interaction that
  /// emitted the corresponding function calls. Gemini requires [tools] to be
  /// supplied again on every interaction, even when server-side state is used.
  Future<Map<String, Object?>> createInteraction({
    required Object input,
    required List<Map<String, Object?>> tools,
    String? previousInteractionId,
  }) async {
    if (_closed) {
      throw StateError('Gemini Interactions API client is closed');
    }

    final body = <String, Object?>{
      'model': model,
      'input': input,
      'store': true,
      if (tools.isNotEmpty) 'tools': tools,
      if (previousInteractionId != null)
        'previous_interaction_id': previousInteractionId,
    };
    final response = await _httpClient.post(
      _endpoint,
      headers: {'Content-Type': 'application/json', 'x-goog-api-key': _apiKey},
      body: jsonEncode(body),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw GeminiApiException(
        response.statusCode,
        _errorMessage(response.body),
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException catch (error) {
      throw FormatException(
        'Gemini API returned invalid JSON: ${error.message}',
      );
    }
    return _stringKeyedMap(decoded, 'Gemini interaction response');
  }

  /// Closes the underlying HTTP client.
  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    _httpClient.close();
  }

  static String _errorMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final error = decoded['error'];
        if (error is Map) {
          final status = error['status'];
          final message = error['message'];
          if (status is String && message is String) {
            return '$status: $message';
          }
          if (message is String) {
            return message;
          }
        }
      }
    } on FormatException {
      // Fall back to a bounded plain-text response below.
    }
    final normalized = body.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty) {
      return 'empty error response';
    }
    const maxLength = 500;
    return normalized.length <= maxLength
        ? normalized
        : '${normalized.substring(0, maxLength)}...';
  }
}

/// Converts MCP tool input schemas to the strict subset used by this example.
abstract final class GeminiSchemaAdapter {
  static const _annotationKeywords = {
    r'$comment',
    r'$id',
    r'$schema',
    'default',
    'description',
    'examples',
    'title',
    'type',
  };

  /// Converts a supported MCP tool input schema to a raw REST JSON map.
  ///
  /// The root must be an object because Gemini function arguments are always
  /// objects. Nested properties may use objects, strings and string enums,
  /// numbers, integers, booleans, and arrays. Boolean schemas, unions,
  /// references, combinators, and unsupported validation keywords fail closed
  /// instead of weakening the MCP tool contract. A parameterless object
  /// returns `null`, which omits the optional Gemini `parameters` field.
  static Map<String, Object?>? fromJson(Object? schema, {String path = r'$'}) {
    final result = _fromJson(schema, path);
    if (result != null && result['type'] != 'object') {
      throw UnsupportedError(
        '$path: an MCP tool input schema must have an object root for Gemini',
      );
    }
    return result;
  }

  static Map<String, Object?>? _fromJson(Object? schema, String path) {
    if (schema is bool) {
      throw UnsupportedError(
        '$path: boolean JSON Schemas are not supported by this example',
      );
    }
    final json = _stringKeyedMap(schema, '$path JSON Schema');

    final type = json['type'];
    if (type is List) {
      throw UnsupportedError(
        '$path: union type arrays are not supported by this example',
      );
    }
    if (type is! String) {
      throw UnsupportedError('$path: a string type is required');
    }

    return switch (type) {
      'object' => _objectSchema(json, path),
      'string' => _stringSchema(json, path),
      'number' => _numberSchema(json, path, integer: false),
      'integer' => _numberSchema(json, path, integer: true),
      'boolean' => _booleanSchema(json, path),
      'array' => _arraySchema(json, path),
      _ =>
        throw UnsupportedError(
          '$path: schema type "$type" is not supported by this example',
        ),
    };
  }

  static Map<String, Object?>? _objectSchema(
    Map<String, Object?> json,
    String path,
  ) {
    _rejectUnsupported(json, path, {'properties', 'required'});
    final rawProperties = json['properties'];
    if (rawProperties != null && rawProperties is! Map) {
      throw UnsupportedError('$path.properties: an object is required');
    }

    final properties = <String, Object?>{};
    for (final MapEntry(:key, :value)
        in (rawProperties as Map? ?? {}).entries) {
      if (key is! String) {
        throw UnsupportedError('$path.properties: keys must be strings');
      }
      final translated = _fromJson(value, '$path.properties.$key');
      if (translated == null) {
        throw UnsupportedError(
          '$path.properties.$key: nested parameterless objects are not '
          'supported by this example',
        );
      }
      properties[key] = translated;
    }

    final required = _requiredProperties(json['required'], properties, path);
    if (properties.isEmpty) {
      if (required != null && required.isNotEmpty) {
        throw UnsupportedError(
          '$path.required: cannot require properties that do not exist',
        );
      }
      return null;
    }

    return <String, Object?>{
      ..._annotations(json, path),
      'type': 'object',
      'properties': properties,
      if (required != null) 'required': required,
    };
  }

  static Map<String, Object?> _stringSchema(
    Map<String, Object?> json,
    String path,
  ) {
    _rejectUnsupported(json, path, {'enum'});
    final result = <String, Object?>{
      ..._annotations(json, path),
      'type': 'string',
    };
    if (!json.containsKey('enum')) {
      return result;
    }
    final rawEnum = json['enum'];
    if (rawEnum is! List ||
        rawEnum.isEmpty ||
        rawEnum.any((value) => value is! String)) {
      throw UnsupportedError(
        '$path.enum: Gemini requires a non-empty list of strings',
      );
    }
    result['enum'] = rawEnum.cast<String>();
    return result;
  }

  static Map<String, Object?> _numberSchema(
    Map<String, Object?> json,
    String path, {
    required bool integer,
  }) {
    _rejectUnsupported(json, path, {'format'});
    final format = json['format'];
    final supportedFormats =
        integer ? const {'int32', 'int64'} : const {'float', 'double'};
    if (format != null &&
        (format is! String || !supportedFormats.contains(format))) {
      throw UnsupportedError(
        '$path.format: unsupported ${integer ? 'integer' : 'number'} format',
      );
    }
    return <String, Object?>{
      ..._annotations(json, path),
      'type': integer ? 'integer' : 'number',
      if (format != null) 'format': format,
    };
  }

  static Map<String, Object?> _booleanSchema(
    Map<String, Object?> json,
    String path,
  ) {
    _rejectUnsupported(json, path, const {});
    return <String, Object?>{..._annotations(json, path), 'type': 'boolean'};
  }

  static Map<String, Object?> _arraySchema(
    Map<String, Object?> json,
    String path,
  ) {
    _rejectUnsupported(json, path, {'items'});
    if (!json.containsKey('items')) {
      throw UnsupportedError('$path.items: an item schema is required');
    }
    final items = _fromJson(json['items'], '$path.items');
    if (items == null) {
      throw UnsupportedError(
        '$path.items: parameterless object items are not supported by Gemini',
      );
    }
    return <String, Object?>{
      ..._annotations(json, path),
      'type': 'array',
      'items': items,
    };
  }

  static List<String>? _requiredProperties(
    Object? value,
    Map<String, Object?> properties,
    String path,
  ) {
    if (value == null) {
      return null;
    }
    if (value is! List || value.any((item) => item is! String)) {
      throw UnsupportedError('$path.required: expected a list of strings');
    }
    final required = value.cast<String>();
    final unknown = required.where((name) => !properties.containsKey(name));
    if (unknown.isNotEmpty) {
      throw UnsupportedError(
        '$path.required: unknown properties ${unknown.join(', ')}',
      );
    }
    return required;
  }

  static Map<String, Object?> _annotations(
    Map<String, Object?> json,
    String path,
  ) {
    final result = <String, Object?>{};
    for (final key in _annotationKeywords.where((key) => key != 'type')) {
      if (json.containsKey(key)) {
        result[key] = json[key];
      }
    }
    for (final key in const [
      r'$comment',
      r'$id',
      r'$schema',
      'description',
      'title',
    ]) {
      final value = result[key];
      if (value != null && value is! String) {
        throw UnsupportedError('$path.$key: expected a string');
      }
    }
    final examples = result['examples'];
    if (examples != null && examples is! List) {
      throw UnsupportedError('$path.examples: expected a list');
    }
    return result;
  }

  static void _rejectUnsupported(
    Map<String, Object?> json,
    String path,
    Set<String> supportedKeywords,
  ) {
    final allowed = {..._annotationKeywords, ...supportedKeywords};
    final unsupported = json.keys.where((key) => !allowed.contains(key));
    if (unsupported.isNotEmpty) {
      throw UnsupportedError(
        '$path: Gemini cannot represent JSON Schema keyword(s): '
        '${unsupported.join(', ')}',
      );
    }
  }
}

/// A client that connects Gemini's Interactions API to an MCP server.
class GoogleMcpClient {
  static const _geminiEnvironmentVariables = {'gemini_api_key', 'gemini_model'};
  static final _geminiFunctionNamePattern = RegExp(r'^[A-Za-z0-9_-]{1,128}$');
  static final _invalidGeminiFunctionNameCharacters = RegExp(
    r'[^A-Za-z0-9_-]+',
  );
  static const _geminiImageMimeTypes = {
    'image/png',
    'image/jpeg',
    'image/webp',
    'image/heic',
    'image/heif',
    'image/gif',
    'image/bmp',
    'image/tiff',
  };

  /// The Gemini REST client.
  final GeminiInteractionsApi gemini;

  /// The MCP client instance.
  final mcp_dart.McpClient mcp;

  final McpToolCaller? _toolCaller;
  final McpToolApprover? _toolApprover;
  final McpToolLister? _toolLister;

  /// The maximum number of function-call rounds for one user query.
  final int maxToolRounds;

  /// The maximum number of MCP `tools/list` pages loaded per refresh.
  final int maxToolPages;

  /// The transport layer for communicating with the MCP server.
  mcp_dart.StdioClientTransport? transport;

  List<Map<String, Object?>> _tools = [];
  Map<String, String> _mcpNamesByGeminiName = const {};

  /// Raw Gemini function declarations for the MCP server's tools.
  List<Map<String, Object?>> get tools => _tools;

  set tools(List<Map<String, Object?>> value) {
    _tools = value;
    _mcpNamesByGeminiName = const {};
  }

  /// Creates a Gemini MCP client.
  GoogleMcpClient(
    this.gemini,
    this.mcp, {
    McpToolCaller? toolCaller,
    McpToolApprover? toolApprover,
    McpToolLister? toolLister,
    this.maxToolRounds = 8,
    this.maxToolPages = 100,
  }) : _toolCaller = toolCaller,
       _toolApprover = toolApprover,
       _toolLister = toolLister {
    if (maxToolRounds < 1) {
      throw ArgumentError.value(maxToolRounds, 'maxToolRounds', 'must be > 0');
    }
    if (maxToolPages < 1) {
      throw ArgumentError.value(maxToolPages, 'maxToolPages', 'must be > 0');
    }
  }

  /// Connects to an MCP server started with [cmd] and [args].
  Future<void> connectToServer(String cmd, List<String> args) async {
    final serverEnvironment = Map<String, String>.of(Platform.environment)
      ..removeWhere(
        (name, _) => _geminiEnvironmentVariables.contains(name.toLowerCase()),
      );
    transport = mcp_dart.StdioClientTransport(
      mcp_dart.StdioServerParameters(
        command: cmd,
        args: args,
        environment: serverEnvironment,
        includeParentEnvironment: false,
        stderrMode: ProcessStartMode.inheritStdio,
      ),
    );
    transport!.onerror = (error) {
      print('Transport error: $error');
    };
    transport!.onclose = () {
      print('Transport closed.');
    };
    await mcp.connect(transport!);
  }

  /// Loads every page of tools and converts them to Gemini declarations.
  Future<void> refreshTools() async {
    final discovered = <mcp_dart.Tool>[];
    final seenCursors = <String>{};
    String? cursor;

    for (var pageNumber = 0; pageNumber < maxToolPages; pageNumber++) {
      final request =
          cursor == null ? null : mcp_dart.ListToolsRequest(cursor: cursor);
      final page = await _listTools(request);
      discovered.addAll(page.tools);

      final nextCursor = page.nextCursor;
      if (nextCursor == null) {
        final converted = _toGeminiTools(discovered);
        _tools = converted.declarations;
        _mcpNamesByGeminiName = converted.mcpNamesByGeminiName;
        return;
      }
      if (!seenCursors.add(nextCursor)) {
        throw StateError(
          'MCP tools/list repeated cursor ${jsonEncode(nextCursor)}',
        );
      }
      cursor = nextCursor;
    }

    throw StateError('MCP tools/list exceeded $maxToolPages pages');
  }

  Future<mcp_dart.ListToolsResult> _listTools(
    mcp_dart.ListToolsRequest? request,
  ) {
    final lister = _toolLister;
    if (lister != null) {
      return lister(request);
    }
    return mcp.listTools(params: request);
  }

  ({
    List<Map<String, Object?>> declarations,
    Map<String, String> mcpNamesByGeminiName,
  })
  _toGeminiTools(List<mcp_dart.Tool> discovered) {
    final names = <String>{};
    for (final tool in discovered) {
      if (!names.add(tool.name)) {
        throw StateError(
          'MCP tools/list returned duplicate tool ${jsonEncode(tool.name)}',
        );
      }
    }

    final aliasesByMcpName = _geminiAliases(names);
    final mcpNamesByGeminiName = <String, String>{};
    final declarations = discovered
        .map((tool) {
          final alias = aliasesByMcpName[tool.name]!;
          mcpNamesByGeminiName[alias] = tool.name;
          final parameters = GeminiSchemaAdapter.fromJson(
            tool.inputSchema.toJson(),
          );
          return <String, Object?>{
            'type': 'function',
            'name': alias,
            if (tool.description != null) 'description': tool.description,
            if (parameters != null) 'parameters': parameters,
          };
        })
        .toList(growable: false);
    return (
      declarations: declarations,
      mcpNamesByGeminiName: Map.unmodifiable(mcpNamesByGeminiName),
    );
  }

  Map<String, String> _geminiAliases(Set<String> mcpNames) {
    final sortedNames = mcpNames.toList()..sort();
    final used = <String>{
      for (final name in sortedNames)
        if (_isValidGeminiFunctionName(name)) name,
    };
    final aliases = <String, String>{for (final name in used) name: name};

    for (final mcpName in sortedNames) {
      if (aliases.containsKey(mcpName)) {
        continue;
      }
      var base = mcpName.replaceAll(_invalidGeminiFunctionNameCharacters, '_');
      if (base.isEmpty) {
        base = 'mcp_tool';
      }
      if (base.length > 128) {
        base = base.substring(0, 128);
      }

      var alias = base;
      var suffixNumber = 2;
      while (!used.add(alias)) {
        final suffix = '_${suffixNumber++}';
        final maxBaseLength = 128 - suffix.length;
        final prefix =
            base.length <= maxBaseLength
                ? base
                : base.substring(0, maxBaseLength);
        alias = '$prefix$suffix';
      }
      aliases[mcpName] = alias;
    }
    return aliases;
  }

  bool _isValidGeminiFunctionName(String name) =>
      _geminiFunctionNamePattern.hasMatch(name);

  /// Sends [query] to Gemini and executes all requested MCP tools.
  ///
  /// Tool discovery runs once before the first interaction. That snapshot is
  /// reused for every tool-call round in this query.
  ///
  /// Parallel calls from one interaction are returned together. Sequential
  /// call rounds are chained with the preceding interaction ID.
  Future<String> processQuery(String query) async {
    await refreshTools();
    final queryTools = List<Map<String, Object?>>.unmodifiable(_tools);
    final queryMcpNamesByGeminiName = _mcpNamesByGeminiName;
    final advertisedNames = {
      for (final tool in queryTools)
        if (tool['name'] case final String name) name,
    };
    Object input = query;
    String? previousInteractionId;
    final finalText = <String>[];
    var toolRounds = 0;

    while (true) {
      final response = await gemini.createInteraction(
        input: input,
        tools: queryTools,
        previousInteractionId: previousInteractionId,
      );
      final interaction = _parseInteraction(response);
      finalText.addAll(interaction.text);

      if (interaction.calls.isEmpty) {
        return finalText.join('\n');
      }
      if (toolRounds >= maxToolRounds) {
        throw StateError('Gemini exceeded $maxToolRounds tool rounds');
      }
      toolRounds++;

      final resolvedCalls = <({_FunctionCall call, String mcpName})>[];
      final approvals = <bool>[];
      for (final call in interaction.calls) {
        if (!_isValidGeminiFunctionName(call.name)) {
          throw StateError(
            'Gemini returned invalid function name ${jsonEncode(call.name)}',
          );
        }
        if (!advertisedNames.contains(call.name)) {
          throw StateError(
            'Gemini requested unadvertised MCP tool '
            '${jsonEncode(call.name)}',
          );
        }
        final mcpName = queryMcpNamesByGeminiName[call.name] ?? call.name;
        resolvedCalls.add((call: call, mcpName: mcpName));
        final approver = _toolApprover;
        final approved =
            approver != null &&
            await approver(
              mcpName,
              Map<String, Object?>.unmodifiable(call.arguments),
            );
        approvals.add(approved);
        final encodedMcpName = jsonEncode(mcpName);
        finalText.add(
          approved
              ? '[Calling tool $encodedMcpName with args '
                  '${jsonEncode(call.arguments)}]'
              : '[Declined tool $encodedMcpName]',
        );
      }

      final results = await Future.wait(
        List.generate(resolvedCalls.length, (index) {
          final (:call, :mcpName) = resolvedCalls[index];
          if (!approvals[index]) {
            return Future.value(_declinedFunctionResult(call));
          }
          return _executeFunctionCall(call, mcpName);
        }),
      );

      input = results;
      previousInteractionId = interaction.id;
    }
  }

  Future<Map<String, Object?>> _executeFunctionCall(
    _FunctionCall call,
    String mcpName,
  ) async {
    final mcp_dart.CallToolResult result;
    try {
      result = await _callTool(
        mcp_dart.CallToolRequest(name: mcpName, arguments: call.arguments),
      );
    } on mcp_dart.McpError catch (error) {
      if (error.code == mcp_dart.ErrorCode.connectionClosed.value) {
        rethrow;
      }
      return {
        'type': 'function_result',
        'name': call.name,
        'call_id': call.id,
        'result': [
          {
            'type': 'text',
            'text': 'MCP tool error ${error.code}: ${error.message}',
          },
        ],
        'is_error': true,
      };
    }
    return <String, Object?>{
      'type': 'function_result',
      'name': call.name,
      'call_id': call.id,
      'result': _geminiToolResult(result),
      if (result.isError) 'is_error': true,
    };
  }

  Map<String, Object?> _declinedFunctionResult(_FunctionCall call) => {
    'type': 'function_result',
    'name': call.name,
    'call_id': call.id,
    'result': [
      {'type': 'text', 'text': 'The user declined this MCP tool call.'},
    ],
    'is_error': true,
  };

  Object _geminiToolResult(mcp_dart.CallToolResult result) {
    final parts = <Map<String, Object?>>[];
    for (final content in result.content) {
      if (!_isAssistantFacing(content)) {
        continue;
      }
      switch (content) {
        case final mcp_dart.TextContent text:
          parts.add({'type': 'text', 'text': text.text});
        case final mcp_dart.ImageContent image:
          if (!_geminiImageMimeTypes.contains(image.mimeType)) {
            throw UnsupportedError(
              'Gemini function results do not support MCP image MIME type '
              '${jsonEncode(image.mimeType)}',
            );
          }
          try {
            base64Decode(image.data);
          } on FormatException catch (error) {
            throw FormatException(
              'MCP image content is not valid base64: ${error.message}',
            );
          }
          parts.add({
            'type': 'image',
            'mime_type': image.mimeType,
            'data': image.data,
          });
        default:
          throw UnsupportedError(
            'Gemini function results cannot represent MCP content type '
            '${content.type}',
          );
      }
    }

    if (!result.hasStructuredContent) {
      return parts;
    }

    final structured = result.structuredContentJson?.toJson();
    final encoded = jsonEncode(structured);
    final representedByText = parts.any(
      (part) => part['type'] == 'text' && part['text'] == encoded,
    );
    if ((parts.isEmpty || (parts.length == 1 && representedByText)) &&
        (structured is Map || structured is String)) {
      return structured as Object;
    }
    if (!representedByText) {
      parts.add({'type': 'text', 'text': encoded});
    }
    return parts;
  }

  bool _isAssistantFacing(mcp_dart.Content content) {
    final annotations = switch (content) {
      final mcp_dart.TextContent value => value.annotations,
      final mcp_dart.ImageContent value => value.annotations,
      final mcp_dart.AudioContent value => value.annotations,
      final mcp_dart.EmbeddedResource value => value.annotations,
      final mcp_dart.ResourceLink value => value.parsedAnnotations,
      mcp_dart.UnknownContent() => null,
    };
    final audience = annotations?.audience;
    return audience == null ||
        audience.contains(mcp_dart.AnnotationAudience.assistant);
  }

  Future<mcp_dart.CallToolResult> _callTool(mcp_dart.CallToolRequest request) {
    final caller = _toolCaller;
    if (caller != null) {
      return caller(request);
    }
    return mcp.callTool(request);
  }

  /// Starts an interactive prompt. Type `quit` to exit.
  ///
  /// Query failures propagate to the caller so command-line integrations can
  /// report a nonzero exit status. Supplying [readLine] lets the CLI share one
  /// input stream with its tool-approval prompts.
  Future<void> chatLoop({
    GeminiLineReader? readLine,
    GeminiLineWriter? writeLine,
  }) async {
    final iterator =
        readLine == null
            ? StreamIterator(
              stdin.transform(utf8.decoder).transform(const LineSplitter()),
            )
            : null;
    Future<String?> readFromStdin() async {
      if (await iterator!.moveNext()) {
        return iterator.current;
      }
      return null;
    }

    final reader = readLine ?? readFromStdin;
    final writer = writeLine ?? print;
    writer('\nMCP Client Started!');
    writer("Type your queries or 'quit' to exit.");

    try {
      while (true) {
        final message = await reader();
        if (message == null || message.trim().toLowerCase() == 'quit') {
          return;
        }
        final response = await processQuery(message);
        writer('\n$response');
      }
    } finally {
      await iterator?.cancel();
    }
  }

  /// Closes both the MCP connection and the Gemini HTTP client.
  Future<void> cleanup() async {
    try {
      await mcp.close();
    } finally {
      gemini.close();
    }
  }

  _ParsedInteraction _parseInteraction(Map<String, Object?> response) {
    final id = _requiredString(response, 'id', 'Gemini interaction');
    final status = _requiredString(response, 'status', 'Gemini interaction');
    final rawSteps = response['steps'];
    if (rawSteps is! List) {
      throw StateError('Gemini interaction "steps" must be a list');
    }

    final text = <String>[];
    final calls = <_FunctionCall>[];
    for (var index = 0; index < rawSteps.length; index++) {
      final step = _stringKeyedMap(
        rawSteps[index],
        'Gemini interaction step $index',
      );
      final type = _requiredString(
        step,
        'type',
        'Gemini interaction step $index',
      );
      switch (type) {
        case 'model_output':
          final error = step['error'];
          if (error != null) {
            throw StateError(
              'Gemini model output failed: ${jsonEncode(error)}',
            );
          }
          final content = step['content'];
          if (content == null) {
            continue;
          }
          if (content is! List) {
            throw StateError(
              'Gemini model output step $index "content" must be a list',
            );
          }
          for (
            var contentIndex = 0;
            contentIndex < content.length;
            contentIndex++
          ) {
            final part = _stringKeyedMap(
              content[contentIndex],
              'Gemini model output content $contentIndex',
            );
            final partType = _requiredString(
              part,
              'type',
              'Gemini model output content $contentIndex',
            );
            if (partType == 'text') {
              text.add(
                _requiredString(
                  part,
                  'text',
                  'Gemini model output content $contentIndex',
                ),
              );
            }
          }
        case 'function_call':
          calls.add(
            _FunctionCall(
              id: _requiredString(step, 'id', 'Gemini function call'),
              name: _requiredString(step, 'name', 'Gemini function call'),
              arguments: _stringKeyedMap(
                step['arguments'],
                'Gemini function call arguments',
              ),
            ),
          );
        default:
          // Thought and future server-side tool steps do not need client work.
          continue;
      }
    }

    if (calls.isNotEmpty && status != 'requires_action') {
      throw StateError(
        'Gemini interaction returned function calls with status "$status"',
      );
    }
    if (calls.isEmpty && status == 'requires_action') {
      throw StateError(
        'Gemini interaction requires action but returned no function calls',
      );
    }
    if (calls.isEmpty && status != 'completed') {
      throw StateError('Gemini interaction ended with status "$status"');
    }

    return _ParsedInteraction(id: id, text: text, calls: calls);
  }
}

final class _FunctionCall {
  final String id;
  final String name;
  final Map<String, Object?> arguments;

  const _FunctionCall({
    required this.id,
    required this.name,
    required this.arguments,
  });
}

final class _ParsedInteraction {
  final String id;
  final List<String> text;
  final List<_FunctionCall> calls;

  const _ParsedInteraction({
    required this.id,
    required this.text,
    required this.calls,
  });
}

Map<String, Object?> _stringKeyedMap(Object? value, String label) {
  if (value is! Map) {
    throw StateError('$label must be an object');
  }
  final result = <String, Object?>{};
  for (final MapEntry(:key, :value) in value.entries) {
    if (key is! String) {
      throw StateError('$label must use string keys');
    }
    result[key] = value;
  }
  return result;
}

String _requiredString(Map<String, Object?> value, String key, String label) {
  final result = value[key];
  if (result is! String || result.isEmpty) {
    throw StateError('$label "$key" must be a non-empty string');
  }
  return result;
}
