import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:mason/mason.dart';
import 'package:mcp_dart/mcp_dart.dart' hide Logger;
// ignore: implementation_imports
import 'package:mcp_dart/src/shared/json_schema/json_schema_validator.dart';

import 'inspectors/inspection_report.dart';
import 'utils/inspect_handlers.dart';
import 'utils/mcp_connection.dart';

/// Inspects a live MCP server and produces an observable behavior report.
class InspectServerCommand extends Command<int> {
  /// Creates a server inspector command.
  InspectServerCommand({Logger? logger}) : _logger = logger ?? Logger() {
    argParser
      ..addOption(
        'url',
        help: 'The MCP Streamable HTTP endpoint to connect to.',
      )
      ..addOption(
        'command',
        abbr: 'c',
        help:
            'The executable command to start the MCP server. If omitted, the command uses the current Dart project.',
      )
      ..addMultiOption(
        'server-args',
        abbr: 'a',
        help: 'Arguments to pass to the server command.',
      )
      ..addMultiOption(
        'env',
        help: 'Environment variables for the server in KEY=VALUE format.',
      )
      ..addOption(
        'probe-config',
        help:
            'JSON file describing explicit tool, resource, prompt, completion, and task probes.',
      )
      ..addFlag(
        'json',
        help: 'Print machine-readable JSON to stdout.',
        negatable: false,
      )
      ..addFlag(
        'strict',
        help: 'Treat warnings as a non-zero result.',
        negatable: false,
      );
  }

  final Logger _logger;

  @override
  final String name = 'inspect-server';

  @override
  final String description =
      'Inspects an MCP server handshake, capabilities, and advertised primitives.';

  @override
  String get invocation =>
      'mcp_dart inspect-server [options] [-- <server-command> ...]';

  @override
  Future<int> run() async {
    final target = _parseConnectionTarget(argResults);
    if (target == null) return ExitCode.usage.code;

    final probeConfig = await _parseProbeConfig(argResults);
    if (probeConfig == null) return ExitCode.usage.code;

    final jsonOutput = argResults?['json'] as bool? ?? false;
    final strict = argResults?['strict'] as bool? ?? false;

    final inspector = McpServerInspector(
      logger: _logger,
      probeConfig: probeConfig,
      silentHandlers: jsonOutput,
    );
    final report = await inspector.inspect(target);

    if (jsonOutput) {
      stdout
          .writeln(const JsonEncoder.withIndent('  ').convert(report.toJson()));
    } else {
      _printReport(report);
    }

    if (!report.passed || (strict && report.warningCount > 0)) {
      return ExitCode.software.code;
    }

    return ExitCode.success.code;
  }

  ServerInspectionTarget? _parseConnectionTarget(ArgResults? results) {
    final url = results?['url'] as String?;
    String? command = results?['command'] as String?;
    var serverArgs = results?['server-args'] as List<String>? ?? const [];
    final rest = results?.rest ?? const <String>[];

    if (url != null && command != null) {
      _logger.err('Cannot specify both --url and --command.');
      return null;
    }
    if (url != null && rest.isNotEmpty) {
      _logger.err('Cannot specify positional server arguments with --url.');
      return null;
    }

    Uri? parsedUrl;
    if (url != null) {
      parsedUrl = Uri.tryParse(url);
      if (parsedUrl == null || !parsedUrl.hasScheme) {
        _logger.err('--url must be an absolute URI.');
        return null;
      }
    }

    if (rest.isNotEmpty) {
      if (command == null) {
        command = rest.first;
        serverArgs = rest.sublist(1);
      } else {
        serverArgs = [...serverArgs, ...rest];
      }
    }

    final env = _parseEnvArgs(results);
    if (env == null) return null;

    return ServerInspectionTarget(
      command: command,
      serverArgs: serverArgs,
      url: parsedUrl,
      env: env,
    );
  }

  Map<String, String>? _parseEnvArgs(ArgResults? results) {
    final envList = results?['env'] as List<String>? ?? const [];
    final env = <String, String>{};
    for (final entry in envList) {
      final separator = entry.indexOf('=');
      if (separator <= 0) {
        _logger.err('--env values must use KEY=VALUE syntax.');
        return null;
      }
      env[entry.substring(0, separator)] = entry.substring(separator + 1);
    }
    return env;
  }

  Future<InspectionProbeConfig?> _parseProbeConfig(ArgResults? results) async {
    final path = results?['probe-config'] as String?;
    if (path == null || path.trim().isEmpty) {
      return const InspectionProbeConfig();
    }

    try {
      final decoded = jsonDecode(await File(path).readAsString());
      if (decoded is! Map) {
        _logger.err('--probe-config must contain a JSON object.');
        return null;
      }
      return InspectionProbeConfig.fromJson(decoded.cast<String, dynamic>());
    } catch (error) {
      _logger.err('Failed to read --probe-config: $error');
      return null;
    }
  }

  void _printReport(InspectionReport report) {
    _logger.info('MCP server inspection: ${report.target}');
    _logger.info(
      'Checks: ${report.passCount} pass, ${report.warningCount} warning, '
      '${report.failCount} fail, ${report.infoCount} info.',
    );

    final serverInfo = report.metadata['serverInfo'];
    if (serverInfo is Map) {
      _logger.info(
        'Server: ${serverInfo['name'] ?? '(unknown)'} '
        '${serverInfo['version'] ?? ''}',
      );
    }

    final inventory = report.inventory;
    if (inventory.isNotEmpty) {
      _logger.info(
        'Inventory: ${(inventory['tools'] as List?)?.length ?? 0} tools, '
        '${(inventory['resources'] as List?)?.length ?? 0} resources, '
        '${(inventory['resourceTemplates'] as List?)?.length ?? 0} templates, '
        '${(inventory['prompts'] as List?)?.length ?? 0} prompts.',
      );
    }

    for (final check in report.checks) {
      final marker = switch (check.status) {
        'pass' => '[pass]',
        'warning' => '[warn]',
        'fail' => '[fail]',
        _ => '[info]',
      };
      final line = '$marker ${check.id}: ${check.message}';
      switch (check.status) {
        case 'fail':
          _logger.err(line);
          break;
        case 'warning':
          _logger.warn(line);
          break;
        case 'pass':
          _logger.detail(line);
          break;
        default:
          _logger.info(line);
      }
    }
  }
}

/// Live MCP server inspector.
class McpServerInspector {
  /// Creates a server inspector.
  McpServerInspector({
    Logger? logger,
    this.probeConfig = const InspectionProbeConfig(),
    this.silentHandlers = false,
  }) : _logger = logger ?? Logger();

  final Logger _logger;

  /// Explicit probes requested by the user.
  final InspectionProbeConfig probeConfig;

  /// Whether notification/request handlers should avoid logging to stdout.
  final bool silentHandlers;

  /// Inspects [target].
  Future<InspectionReport> inspect(ServerInspectionTarget target) async {
    final checks = InspectionCheckBuilder();
    final handlers = InspectHandlers(_logger, silent: silentHandlers);
    final inventory = <String, dynamic>{};
    final metadata = <String, dynamic>{
      'transport': target.transport,
    };

    McpConnection? connection;
    try {
      connection = await _connect(target);
      handlers.registerHandlers(connection.client);
      checks.pass(
        'lifecycle.initialize',
        'Initialize handshake completed.',
      );

      final client = connection.client;
      final serverInfo = client.getServerVersion();
      final capabilities = client.getServerCapabilities();
      final instructions = client.getInstructions();

      if (serverInfo != null) {
        metadata['serverInfo'] = serverInfo.toJson();
        _checkImplementation(checks, serverInfo);
      } else {
        checks.fail(
          'lifecycle.server-info',
          'Initialize result did not expose serverInfo.',
        );
      }

      if (capabilities != null) {
        metadata['capabilities'] = capabilities.toJson();
        checks.pass(
          'lifecycle.capabilities',
          'Server capabilities were negotiated.',
          details: capabilities.toJson(),
        );
      } else {
        checks.fail(
          'lifecycle.capabilities',
          'Initialize result did not expose capabilities.',
        );
      }

      if (instructions != null && instructions.trim().isNotEmpty) {
        metadata['instructions'] = instructions;
      }

      await _probePing(client, checks);
      await _inspectTools(client, capabilities, checks, inventory);
      await _probeConfiguredTools(client, checks, inventory);
      await _inspectResources(client, capabilities, checks, inventory);
      await _inspectPrompts(client, capabilities, checks, inventory);
      await _inspectCompletions(client, capabilities, checks, inventory);
      await _inspectLogging(client, capabilities, checks);
      await _inspectTasks(client, capabilities, checks, inventory);
      _inspectObservedNotifications(handlers, checks, inventory);
      await _inspectStreamableHttpTarget(target, connection, checks, metadata);
    } catch (error) {
      checks.fail(
        'lifecycle.connect',
        'Failed to inspect server: $error',
      );
    } finally {
      await connection?.close();
    }

    return InspectionReport(
      kind: 'server',
      target: target.description,
      metadata: metadata,
      inventory: inventory,
      checks: checks.checks,
    );
  }

  Future<McpConnection> _connect(ServerInspectionTarget target) {
    final clientOptions = McpClientOptions(
      capabilities: const ClientCapabilities(
        roots: ClientCapabilitiesRoots(listChanged: true),
        sampling: ClientCapabilitiesSampling(),
        elicitation: ClientElicitation.formOnly(),
      ),
    );

    if (target.command != null) {
      return McpConnection.connectToCommand(
        _logger,
        target.command!,
        target.serverArgs,
        env: target.env,
        options: clientOptions,
      );
    }

    if (target.url != null) {
      return McpConnection.connectToUrl(
        _logger,
        target.url!,
        options: clientOptions,
      );
    }

    if (target.serverArgs.isNotEmpty || target.env.isNotEmpty) {
      _logger.info(
        'Using local project. --server-args and --env are ignored for local project runner.',
      );
    }
    return McpConnection.connectToLocalProject(_logger, options: clientOptions);
  }

  void _checkImplementation(
    InspectionCheckBuilder checks,
    Implementation implementation,
  ) {
    final missing = <String>[];
    if (implementation.name.trim().isEmpty) missing.add('name');
    if (implementation.version.trim().isEmpty) missing.add('version');

    if (missing.isEmpty) {
      checks.pass(
        'lifecycle.server-info',
        'Server implementation has name and version.',
      );
    } else {
      checks.fail(
        'lifecycle.server-info',
        'Server implementation is missing: ${missing.join(', ')}.',
      );
    }
  }

  Future<void> _probePing(
    McpClient client,
    InspectionCheckBuilder checks,
  ) async {
    try {
      await client.ping(
        const RequestOptions(timeout: Duration(seconds: 5)),
      );
      checks.pass('base.ping', 'Server responded to ping.');
    } catch (error) {
      checks.warning(
        'base.ping',
        'Server did not respond to ping: $error',
      );
    }
  }

  Future<void> _inspectTools(
    McpClient client,
    ServerCapabilities? capabilities,
    InspectionCheckBuilder checks,
    Map<String, dynamic> inventory,
  ) async {
    if (capabilities?.tools == null) {
      checks.info(
        'tools.capability',
        'Server does not advertise tools.',
      );
      inventory['tools'] = <Map<String, dynamic>>[];
      return;
    }

    checks.pass(
      'tools.capability',
      'Server advertises tools.',
      details: capabilities!.tools!.toJson(),
    );

    try {
      final result = await client.listTools(
        options: const RequestOptions(timeout: Duration(seconds: 5)),
      );
      inventory['tools'] = result.tools.map((tool) => tool.toJson()).toList();
      checks.pass(
        'tools.list',
        'tools/list returned ${result.tools.length} tools.',
      );
      _checkTools(checks, result.tools);
    } catch (error) {
      checks.fail(
        'tools.list',
        'Server advertises tools but tools/list failed: $error',
      );
    }
  }

  void _checkTools(InspectionCheckBuilder checks, List<Tool> tools) {
    final seen = <String>{};
    var hasFailures = false;
    var hasWarnings = false;

    for (final tool in tools) {
      if (!seen.add(tool.name)) {
        hasFailures = true;
        checks.fail('tools.unique-name', 'Duplicate tool name: ${tool.name}.');
      }

      final nameWarning = _toolNameWarning(tool.name);
      if (nameWarning != null) {
        hasFailures = true;
        checks.fail('tools.name-format', nameWarning);
      }

      final schemaJson = tool.inputSchema.toJson();
      if (schemaJson['type'] != 'object') {
        hasFailures = true;
        checks.fail(
          'tools.input-schema',
          'Tool ${tool.name} inputSchema root should be an object schema.',
          details: schemaJson,
        );
      }

      final outputSchema = tool.outputSchema?.toJson();
      if (outputSchema != null && outputSchema['type'] != 'object') {
        hasFailures = true;
        checks.fail(
          'tools.output-schema',
          'Tool ${tool.name} outputSchema root should be an object schema.',
          details: outputSchema,
        );
      }

      if (tool.description == null || tool.description!.trim().isEmpty) {
        hasWarnings = true;
        checks.warning(
          'tools.description',
          'Tool ${tool.name} has no description.',
        );
      }
    }

    if (!hasFailures) {
      checks.pass('tools.schema',
          'All advertised tools have usable names and object schemas.');
    }
    if (!hasWarnings) {
      checks.pass(
          'tools.descriptions', 'All advertised tools include descriptions.');
    }
  }

  Future<void> _probeConfiguredTools(
    McpClient client,
    InspectionCheckBuilder checks,
    Map<String, dynamic> inventory,
  ) async {
    if (probeConfig.toolCalls.isEmpty) {
      checks.info(
        'tools.call.configured',
        'No configured tool call probes were provided.',
      );
      return;
    }

    final tools = _inventoryTools(inventory);
    final results = <Map<String, dynamic>>[];
    var failures = 0;
    for (final probe in probeConfig.toolCalls) {
      final tool = _findTool(tools, probe.name);
      if (tool == null) {
        failures += 1;
        checks.fail(
          'tools.call.${probe.name}',
          'Configured tool probe ${probe.name} was not advertised.',
        );
        continue;
      }

      try {
        final result = await client.callTool(
          CallToolRequest(name: probe.name, arguments: probe.arguments),
          options: const RequestOptions(timeout: Duration(seconds: 10)),
        );
        final resultJson = result.toJson();
        results.add(<String, dynamic>{
          'name': probe.name,
          'arguments': probe.arguments,
          'result': resultJson,
        });
        if (result.isError) {
          failures += 1;
          checks.fail(
            'tools.call.${probe.name}',
            'Configured tool probe ${probe.name} returned isError.',
            details: resultJson,
          );
          continue;
        }

        checks.pass(
          'tools.call.${probe.name}',
          'Configured tool probe ${probe.name} completed successfully.',
        );
        if (!_validateConfiguredToolOutput(checks, tool, result)) {
          failures += 1;
        }
      } catch (error) {
        failures += 1;
        results.add(<String, dynamic>{
          'name': probe.name,
          'arguments': probe.arguments,
          'error': error.toString(),
        });
        checks.fail(
          'tools.call.${probe.name}',
          'Configured tool probe ${probe.name} failed: $error',
        );
        if (tool.outputSchema != null &&
            error.toString().contains('Structured content does not match')) {
          checks.fail(
            'tools.output-schema.${probe.name}',
            'Structured output for ${probe.name} did not match outputSchema: $error',
          );
        }
      }
    }

    inventory['toolCalls'] = results;
    if (failures == 0) {
      checks.pass(
        'tools.call.configured',
        'All configured tool call probes completed successfully.',
      );
    }
  }

  bool _validateConfiguredToolOutput(
    InspectionCheckBuilder checks,
    Tool tool,
    CallToolResult result,
  ) {
    if (tool.outputSchema == null) {
      checks.info(
        'tools.output-schema.${tool.name}',
        'Tool ${tool.name} does not advertise outputSchema.',
      );
      return true;
    }

    try {
      tool.outputSchema!.validate(result.structuredContentJson?.toJson());
      checks.pass(
        'tools.output-schema.${tool.name}',
        'Structured output for ${tool.name} matched its outputSchema.',
      );
      return true;
    } catch (error) {
      checks.fail(
        'tools.output-schema.${tool.name}',
        'Structured output for ${tool.name} did not match outputSchema: $error',
      );
      return false;
    }
  }

  Future<void> _inspectResources(
    McpClient client,
    ServerCapabilities? capabilities,
    InspectionCheckBuilder checks,
    Map<String, dynamic> inventory,
  ) async {
    if (capabilities?.resources == null) {
      checks.info(
        'resources.capability',
        'Server does not advertise resources.',
      );
      inventory['resources'] = <Map<String, dynamic>>[];
      inventory['resourceTemplates'] = <Map<String, dynamic>>[];
      return;
    }

    checks.pass(
      'resources.capability',
      'Server advertises resources.',
      details: capabilities!.resources!.toJson(),
    );

    try {
      final result = await client.listResources(
        options: const RequestOptions(timeout: Duration(seconds: 5)),
      );
      inventory['resources'] =
          result.resources.map((resource) => resource.toJson()).toList();
      checks.pass(
        'resources.list',
        'resources/list returned ${result.resources.length} resources.',
      );
      _checkResources(checks, result.resources);
      await _probeResourceRead(client, checks, inventory, result.resources);
      await _probeResourceSubscription(
        client,
        capabilities.resources!,
        checks,
        inventory,
        result.resources,
      );
    } catch (error) {
      checks.fail(
        'resources.list',
        'Server advertises resources but resources/list failed: $error',
      );
    }

    try {
      final result = await client.listResourceTemplates(
        options: const RequestOptions(timeout: Duration(seconds: 5)),
      );
      inventory['resourceTemplates'] = result.resourceTemplates
          .map((template) => template.toJson())
          .toList();
      checks.pass(
        'resources.templates.list',
        'resources/templates/list returned ${result.resourceTemplates.length} templates.',
      );
      _checkResourceTemplates(checks, result.resourceTemplates);
    } catch (error) {
      checks.fail(
        'resources.templates.list',
        'Server advertises resources but resources/templates/list failed: $error',
      );
    }
  }

  void _checkResources(
    InspectionCheckBuilder checks,
    List<Resource> resources,
  ) {
    final seen = <String>{};
    var hasFailures = false;

    for (final resource in resources) {
      if (!seen.add(resource.uri)) {
        hasFailures = true;
        checks.fail(
          'resources.unique-uri',
          'Duplicate resource URI: ${resource.uri}.',
        );
      }
      if (resource.uri.trim().isEmpty || Uri.tryParse(resource.uri) == null) {
        hasFailures = true;
        checks.fail(
          'resources.uri',
          'Resource ${resource.name} has an invalid URI: ${resource.uri}.',
        );
      }
      if (resource.name.trim().isEmpty) {
        hasFailures = true;
        checks.fail(
          'resources.name',
          'Resource ${resource.uri} has an empty name.',
        );
      }
    }

    if (!hasFailures) {
      checks.pass(
        'resources.shape',
        'All listed resources have unique URIs and names.',
      );
    }
  }

  Future<void> _probeResourceRead(
    McpClient client,
    InspectionCheckBuilder checks,
    Map<String, dynamic> inventory,
    List<Resource> resources,
  ) async {
    if (resources.isEmpty) {
      checks.info(
        'resources.read',
        'No listed resources are available for resources/read probing.',
      );
      return;
    }

    final resource = _selectResource(resources);
    if (resource == null) {
      checks.fail(
        'resources.read',
        'Configured resource ${probeConfig.resource?.uri} was not advertised.',
      );
      return;
    }
    try {
      final result = await client.readResource(
        ReadResourceRequest(uri: resource.uri),
        const RequestOptions(timeout: Duration(seconds: 5)),
      );
      inventory['resourceReads'] = <Map<String, dynamic>>[
        <String, dynamic>{
          'uri': resource.uri,
          'result': result.toJson(),
        },
      ];
      checks.pass(
        'resources.read',
        'resources/read succeeded for ${resource.uri}.',
      );
      if (result.contents.isEmpty) {
        checks.warning(
          'resources.read.contents',
          'resources/read returned no contents for ${resource.uri}.',
        );
      } else {
        checks.pass(
          'resources.read.contents',
          'resources/read returned ${result.contents.length} content item(s).',
        );
      }
    } catch (error) {
      checks.fail(
        'resources.read',
        'Server listed ${resource.uri} but resources/read failed: $error',
      );
    }
  }

  Future<void> _probeResourceSubscription(
    McpClient client,
    ServerCapabilitiesResources resourcesCapability,
    InspectionCheckBuilder checks,
    Map<String, dynamic> inventory,
    List<Resource> resources,
  ) async {
    final configuredResource = probeConfig.resource;
    if (resourcesCapability.subscribe != true) {
      if (configuredResource?.subscribe == true) {
        checks.fail(
          'resources.subscribe',
          'Probe config requested resource subscription but server does not advertise resources.subscribe.',
        );
      } else {
        checks.info(
          'resources.subscribe',
          'Server does not advertise resources.subscribe.',
        );
      }
      return;
    }
    if (configuredResource?.subscribe == false) {
      checks.info(
        'resources.subscribe',
        'Probe config disabled resource subscription probing.',
      );
      return;
    }
    if (resources.isEmpty) {
      checks.info(
        'resources.subscribe',
        'Server advertises resources.subscribe but listed no resources to subscribe to.',
      );
      return;
    }

    final resource = _selectResource(resources);
    if (resource == null) {
      checks.fail(
        'resources.subscribe',
        'Configured resource ${configuredResource?.uri} was not advertised.',
      );
      return;
    }
    try {
      await client.subscribeResource(
        SubscribeRequest(uri: resource.uri),
        const RequestOptions(timeout: Duration(seconds: 5)),
      );
      await client.unsubscribeResource(
        UnsubscribeRequest(uri: resource.uri),
        const RequestOptions(timeout: Duration(seconds: 5)),
      );
      inventory['resourceSubscriptions'] = <Map<String, dynamic>>[
        <String, dynamic>{
          'uri': resource.uri,
          'subscribedAndUnsubscribed': true
        },
      ];
      checks.pass(
        'resources.subscribe',
        'resources/subscribe and resources/unsubscribe succeeded for ${resource.uri}.',
      );
    } catch (error) {
      checks.fail(
        'resources.subscribe',
        'Server advertises resources.subscribe but subscribe/unsubscribe failed for ${resource.uri}: $error',
      );
    }
  }

  void _checkResourceTemplates(
    InspectionCheckBuilder checks,
    List<ResourceTemplate> templates,
  ) {
    final seen = <String>{};
    var hasFailures = false;

    for (final template in templates) {
      if (!seen.add(template.uriTemplate)) {
        hasFailures = true;
        checks.fail(
          'resources.templates.unique-uri-template',
          'Duplicate resource template URI: ${template.uriTemplate}.',
        );
      }
      if (template.uriTemplate.trim().isEmpty) {
        hasFailures = true;
        checks.fail(
          'resources.templates.uri-template',
          'Resource template ${template.name} has an empty URI template.',
        );
      }
      if (template.name.trim().isEmpty) {
        hasFailures = true;
        checks.fail(
          'resources.templates.name',
          'Resource template ${template.uriTemplate} has an empty name.',
        );
      }
    }

    if (!hasFailures) {
      checks.pass(
        'resources.templates.shape',
        'All listed resource templates have unique URI templates and names.',
      );
    }
  }

  Future<void> _inspectPrompts(
    McpClient client,
    ServerCapabilities? capabilities,
    InspectionCheckBuilder checks,
    Map<String, dynamic> inventory,
  ) async {
    if (capabilities?.prompts == null) {
      checks.info(
        'prompts.capability',
        'Server does not advertise prompts.',
      );
      inventory['prompts'] = <Map<String, dynamic>>[];
      return;
    }

    checks.pass(
      'prompts.capability',
      'Server advertises prompts.',
      details: capabilities!.prompts!.toJson(),
    );

    try {
      final result = await client.listPrompts(
        options: const RequestOptions(timeout: Duration(seconds: 5)),
      );
      inventory['prompts'] =
          result.prompts.map((prompt) => prompt.toJson()).toList();
      checks.pass(
        'prompts.list',
        'prompts/list returned ${result.prompts.length} prompts.',
      );
      _checkPrompts(checks, result.prompts);
      await _probePromptGet(client, checks, inventory, result.prompts);
    } catch (error) {
      checks.fail(
        'prompts.list',
        'Server advertises prompts but prompts/list failed: $error',
      );
    }
  }

  void _checkPrompts(InspectionCheckBuilder checks, List<Prompt> prompts) {
    final seen = <String>{};
    var hasFailures = false;

    for (final prompt in prompts) {
      if (!seen.add(prompt.name)) {
        hasFailures = true;
        checks.fail(
          'prompts.unique-name',
          'Duplicate prompt name: ${prompt.name}.',
        );
      }
      if (prompt.name.trim().isEmpty) {
        hasFailures = true;
        checks.fail('prompts.name', 'Prompt name cannot be empty.');
      }

      final argumentNames = <String>{};
      for (final argument in prompt.arguments ?? const <PromptArgument>[]) {
        if (!argumentNames.add(argument.name)) {
          hasFailures = true;
          checks.fail(
            'prompts.arguments.unique-name',
            'Prompt ${prompt.name} has duplicate argument ${argument.name}.',
          );
        }
        if (argument.name.trim().isEmpty) {
          hasFailures = true;
          checks.fail(
            'prompts.arguments.name',
            'Prompt ${prompt.name} has an empty argument name.',
          );
        }
      }
    }

    if (!hasFailures) {
      checks.pass(
        'prompts.shape',
        'All listed prompts have unique names and argument names.',
      );
    }
  }

  Future<void> _probePromptGet(
    McpClient client,
    InspectionCheckBuilder checks,
    Map<String, dynamic> inventory,
    List<Prompt> prompts,
  ) async {
    if (prompts.isEmpty) {
      checks.info(
        'prompts.get',
        'No listed prompts are available for prompts/get probing.',
      );
      return;
    }

    final prompt = _selectPrompt(prompts);
    if (prompt == null) {
      checks.fail(
        'prompts.get',
        'Configured prompt ${probeConfig.prompt?.name} was not advertised.',
      );
      return;
    }
    try {
      final result = await client.getPrompt(
        GetPromptRequest(
          name: prompt.name,
          arguments:
              probeConfig.prompt?.arguments ?? _samplePromptArguments(prompt),
        ),
        const RequestOptions(timeout: Duration(seconds: 5)),
      );
      inventory['promptGets'] = <Map<String, dynamic>>[
        <String, dynamic>{
          'name': prompt.name,
          'result': result.toJson(),
        },
      ];
      checks.pass(
        'prompts.get',
        'prompts/get succeeded for ${prompt.name}.',
      );
      if (result.messages.isEmpty) {
        checks.warning(
          'prompts.get.messages',
          'prompts/get returned no messages for ${prompt.name}.',
        );
      } else {
        checks.pass(
          'prompts.get.messages',
          'prompts/get returned ${result.messages.length} message(s).',
        );
      }
    } catch (error) {
      checks.fail(
        'prompts.get',
        'Server listed ${prompt.name} but prompts/get failed: $error',
      );
    }
  }

  Map<String, String>? _samplePromptArguments(Prompt prompt) {
    final arguments = prompt.arguments ?? const <PromptArgument>[];
    if (arguments.isEmpty) return const <String, String>{};

    return <String, String>{
      for (final argument in arguments)
        if (argument.required == true) argument.name: '',
    };
  }

  Future<void> _inspectCompletions(
    McpClient client,
    ServerCapabilities? capabilities,
    InspectionCheckBuilder checks,
    Map<String, dynamic> inventory,
  ) async {
    if (capabilities?.completions == null) {
      checks.info(
        'completion.capability',
        'Server does not advertise completions.',
      );
      return;
    }

    checks.pass(
      'completion.capability',
      'Server advertises completions.',
      details: capabilities!.completions!.toJson(),
    );

    final prompts = _inventoryPrompts(inventory);
    final completionProbe = probeConfig.completion;
    final prompt = completionProbe == null
        ? prompts.firstWhere(
            (candidate) =>
                (candidate.arguments ?? const <PromptArgument>[]).isNotEmpty,
            orElse: () => const Prompt(name: ''),
          )
        : _findPrompt(prompts, completionProbe.prompt) ??
            const Prompt(name: '');
    if (prompt.name.isEmpty) {
      checks.info(
        'completion.complete',
        'Server advertises completions but no prompt argument was available for a safe completion probe.',
      );
      return;
    }

    final promptArguments = prompt.arguments ?? const <PromptArgument>[];
    if (promptArguments.isEmpty) {
      checks.info(
        'completion.complete',
        'Prompt ${prompt.name} does not advertise arguments for completion probing.',
      );
      return;
    }

    final argumentName = completionProbe?.argument;
    final argument = argumentName == null
        ? promptArguments.first
        : promptArguments.firstWhere(
            (candidate) => candidate.name == argumentName,
            orElse: () => const PromptArgument(name: ''),
          );
    if (argument.name.isEmpty) {
      checks.fail(
        'completion.complete',
        'Configured completion argument $argumentName was not advertised by prompt ${prompt.name}.',
      );
      return;
    }
    try {
      final result = await client.complete(
        CompleteRequest(
          ref: PromptReference(name: prompt.name, title: prompt.title),
          argument: ArgumentCompletionInfo(
            name: argument.name,
            value: completionProbe?.value ?? '',
          ),
        ),
        const RequestOptions(timeout: Duration(seconds: 5)),
      );
      inventory['completions'] = <Map<String, dynamic>>[
        <String, dynamic>{
          'prompt': prompt.name,
          'argument': argument.name,
          'result': result.toJson(),
        },
      ];
      checks.pass(
        'completion.complete',
        'completion/complete succeeded for prompt ${prompt.name} argument ${argument.name}.',
      );
    } catch (error) {
      checks.fail(
        'completion.complete',
        'Server advertises completions but completion/complete failed: $error',
      );
    }
  }

  Future<void> _inspectLogging(
    McpClient client,
    ServerCapabilities? capabilities,
    InspectionCheckBuilder checks,
  ) async {
    if (capabilities?.logging == null) {
      checks.info(
        'logging.capability',
        'Server does not advertise logging.',
      );
      return;
    }

    checks.pass(
      'logging.capability',
      'Server advertises logging.',
      details: capabilities!.logging,
    );
    try {
      await client.setLoggingLevel(
        LoggingLevel.info,
        const RequestOptions(timeout: Duration(seconds: 5)),
      );
      checks.pass('logging.set-level', 'logging/setLevel accepted info level.');
    } catch (error) {
      checks.fail(
        'logging.set-level',
        'Server advertises logging but logging/setLevel failed: $error',
      );
    }
  }

  Future<void> _inspectTasks(
    McpClient client,
    ServerCapabilities? capabilities,
    InspectionCheckBuilder checks,
    Map<String, dynamic> inventory,
  ) async {
    final taskCapabilities = capabilities?.tasks;
    if (taskCapabilities == null) {
      checks.info('tasks.capability', 'Server does not advertise tasks.');
      return;
    }

    checks.pass(
      'tasks.capability',
      'Server advertises tasks.',
      details: taskCapabilities.toJson(),
    );

    if (taskCapabilities.list == true) {
      try {
        final tasks = await TaskClient(client).listTasks();
        inventory['tasks'] = tasks.map((task) => task.toJson()).toList();
        checks.pass('tasks.list', 'tasks/list returned ${tasks.length} tasks.');
      } catch (error) {
        checks.fail(
          'tasks.list',
          'Server advertises tasks.list but tasks/list failed: $error',
        );
      }
    } else {
      checks.info('tasks.list', 'Server does not advertise tasks.list.');
    }

    final supportsTaskToolCalls =
        taskCapabilities.requests?.tools?.call != null;
    if (!supportsTaskToolCalls) {
      checks.info(
        'tasks.tools.call',
        'Server does not advertise tasks.requests.tools.call.',
      );
      return;
    }

    final tools = _inventoryTools(inventory);
    final taskTool = _selectTaskTool(tools);
    if (taskTool.name.isEmpty) {
      checks.info(
        'tasks.tools.call',
        'Server advertises task-augmented tool calls but no task-capable tool with safe empty arguments was found.',
      );
      return;
    }

    final taskConfig = probeConfig.task;
    final taskArguments = taskConfig?.arguments ?? const <String, dynamic>{};
    final taskParams = <String, dynamic>{
      'ttl': taskConfig?.ttl ?? 60000,
      if (taskConfig?.pollInterval != null)
        'pollInterval': taskConfig!.pollInterval,
    };

    if (taskConfig?.cancel == true) {
      await _probeTaskCancellation(
        client,
        checks,
        inventory,
        taskTool,
        taskArguments,
        taskParams,
      );
      return;
    }

    final messages = <Map<String, dynamic>>[];
    try {
      await for (final message in TaskClient(client)
          .callToolStream(
            taskTool.name,
            taskArguments,
            task: taskParams,
          )
          .timeout(const Duration(seconds: 10))) {
        messages.add(_taskStreamMessageToJson(message));
        if (message is TaskErrorMessage) {
          throw message.error;
        }
      }
      inventory['taskToolCalls'] = <Map<String, dynamic>>[
        <String, dynamic>{
          'tool': taskTool.name,
          'messages': messages,
        },
      ];
      checks.pass(
        'tasks.tools.call',
        'Task-augmented tools/call completed for ${taskTool.name}.',
      );
      _checkTaskLifecycle(checks, taskTool, messages);
      _validateTaskToolResult(checks, taskTool, messages);
    } catch (error) {
      inventory['taskToolCalls'] = <Map<String, dynamic>>[
        <String, dynamic>{
          'tool': taskTool.name,
          'messages': messages,
          'error': error.toString(),
        },
      ];
      checks.fail(
        'tasks.tools.call',
        'Task-augmented tools/call failed for ${taskTool.name}: $error',
      );
    }
  }

  Future<void> _probeTaskCancellation(
    McpClient client,
    InspectionCheckBuilder checks,
    Map<String, dynamic> inventory,
    Tool taskTool,
    Map<String, dynamic> arguments,
    Map<String, dynamic> taskParams,
  ) async {
    try {
      final taskClient = TaskClient(client);
      final createdMessage = await taskClient
          .callToolStream(
            taskTool.name,
            arguments,
            task: taskParams,
          )
          .timeout(const Duration(seconds: 10))
          .firstWhere(
        (message) {
          if (message is TaskErrorMessage) {
            throw message.error;
          }
          return message is TaskCreatedMessage;
        },
        orElse: () => throw StateError(
          'Task probe for ${taskTool.name} completed without creating a task.',
        ),
      );
      final created = (createdMessage as TaskCreatedMessage).task;
      final cancelled = await taskClient.cancelTaskWithResult(
        created.taskId,
      );
      inventory['taskCancellations'] = <Map<String, dynamic>>[
        <String, dynamic>{
          'tool': taskTool.name,
          'created': created.toJson(),
          'cancelled': cancelled.toJson(),
        },
      ];
      if (cancelled.status == TaskStatus.cancelled) {
        checks.pass(
          'tasks.cancel',
          'tasks/cancel returned a cancelled task for ${created.taskId}.',
        );
      } else {
        checks.warning(
          'tasks.cancel',
          'tasks/cancel returned non-cancelled status ${cancelled.status.name} for ${created.taskId}.',
          details: cancelled.toJson(),
        );
      }
    } catch (error) {
      inventory['taskCancellations'] = <Map<String, dynamic>>[
        <String, dynamic>{
          'tool': taskTool.name,
          'arguments': arguments,
          'error': error.toString(),
        },
      ];
      checks.fail(
        'tasks.cancel',
        'Configured task cancellation probe failed for ${taskTool.name}: $error',
      );
    }
  }

  bool _canProbeTaskToolWithEmptyArguments(Tool tool) {
    final taskSupport = tool.execution?.taskSupport ?? 'forbidden';
    if (taskSupport == 'forbidden') return false;
    final required = tool.inputSchema.toJson()['required'];
    return required is! List || required.isEmpty;
  }

  Tool _selectTaskTool(List<Tool> tools) {
    final taskConfig = probeConfig.task;
    if (taskConfig?.tool != null) {
      return _findTool(tools, taskConfig!.tool!) ??
          Tool(name: '', inputSchema: JsonObject());
    }
    return tools.firstWhere(
      _canProbeTaskToolWithEmptyArguments,
      orElse: () => Tool(name: '', inputSchema: JsonObject()),
    );
  }

  void _checkTaskLifecycle(
    InspectionCheckBuilder checks,
    Tool taskTool,
    List<Map<String, dynamic>> messages,
  ) {
    final taskMessages = messages
        .where((message) => message['task'] is Map<String, dynamic>)
        .toList();
    if (taskMessages.isEmpty) {
      checks.info(
        'tasks.lifecycle',
        'Task probe for ${taskTool.name} completed immediately without creating a task.',
      );
      return;
    }

    checks.pass(
      'tasks.lifecycle.created',
      'Task probe for ${taskTool.name} created a task.',
    );
    final statuses = taskMessages
        .map((message) => (message['task'] as Map<String, dynamic>)['status'])
        .whereType<String>()
        .toList();
    final terminalStatuses = {'completed', 'failed', 'cancelled'};
    if (statuses.isNotEmpty && terminalStatuses.contains(statuses.last)) {
      checks.pass(
        'tasks.lifecycle.terminal',
        'Task probe for ${taskTool.name} reached terminal status ${statuses.last}.',
      );
    } else {
      checks.warning(
        'tasks.lifecycle.terminal',
        'Task probe for ${taskTool.name} did not observe a terminal task status.',
        details: <String, dynamic>{'statuses': statuses},
      );
    }
  }

  void _validateTaskToolResult(
    InspectionCheckBuilder checks,
    Tool taskTool,
    List<Map<String, dynamic>> messages,
  ) {
    if (taskTool.outputSchema == null) {
      checks.info(
        'tasks.result.output-schema',
        'Task tool ${taskTool.name} does not advertise outputSchema.',
      );
      return;
    }
    final resultMessage = messages.lastWhere(
      (message) => message['result'] is Map<String, dynamic>,
      orElse: () => const <String, dynamic>{},
    );
    final result = resultMessage['result'];
    if (result is! Map<String, dynamic>) {
      checks.warning(
        'tasks.result.output-schema',
        'Task tool ${taskTool.name} advertised outputSchema but no task result was observed.',
      );
      return;
    }
    try {
      taskTool.outputSchema!.validate(result['structuredContent']);
      checks.pass(
        'tasks.result.output-schema',
        'Task result structuredContent for ${taskTool.name} matched outputSchema.',
      );
    } catch (error) {
      checks.fail(
        'tasks.result.output-schema',
        'Task result structuredContent for ${taskTool.name} did not match outputSchema: $error',
      );
    }
  }

  List<Tool> _inventoryTools(Map<String, dynamic> inventory) {
    return (inventory['tools'] as List<dynamic>?)
            ?.whereType<Map<String, dynamic>>()
            .map(Tool.fromJson)
            .toList() ??
        const <Tool>[];
  }

  List<Prompt> _inventoryPrompts(Map<String, dynamic> inventory) {
    return (inventory['prompts'] as List<dynamic>?)
            ?.whereType<Map<String, dynamic>>()
            .map(Prompt.fromJson)
            .toList() ??
        const <Prompt>[];
  }

  Tool? _findTool(List<Tool> tools, String name) {
    for (final tool in tools) {
      if (tool.name == name) return tool;
    }
    return null;
  }

  Resource? _selectResource(List<Resource> resources) {
    final configured = probeConfig.resource?.uri;
    if (configured == null) return resources.first;
    for (final resource in resources) {
      if (resource.uri == configured) return resource;
    }
    return null;
  }

  Prompt? _selectPrompt(List<Prompt> prompts) {
    final configured = probeConfig.prompt?.name;
    if (configured == null) return prompts.first;
    return _findPrompt(prompts, configured);
  }

  Prompt? _findPrompt(List<Prompt> prompts, String name) {
    for (final prompt in prompts) {
      if (prompt.name == name) return prompt;
    }
    return null;
  }

  Map<String, dynamic> _taskStreamMessageToJson(TaskStreamMessage message) {
    return switch (message) {
      TaskCreatedMessage(:final task) => <String, dynamic>{
          'type': message.type,
          'task': task.toJson(),
        },
      TaskStatusMessage(:final task) => <String, dynamic>{
          'type': message.type,
          'task': task.toJson(),
        },
      TaskResultMessage(:final result) => <String, dynamic>{
          'type': message.type,
          'result': result.toJson(),
        },
      TaskErrorMessage(:final error) => <String, dynamic>{
          'type': message.type,
          'error': error.toString(),
        },
    };
  }

  void _inspectObservedNotifications(
    InspectHandlers handlers,
    InspectionCheckBuilder checks,
    Map<String, dynamic> inventory,
  ) {
    inventory['notifications'] = handlers.notifications;
    if (handlers.notifications.isEmpty) {
      checks.info(
        'notifications.observed',
        'No server notifications were observed during inspection.',
      );
    } else {
      checks.pass(
        'notifications.observed',
        'Observed ${handlers.notifications.length} server notification(s).',
      );
    }

    if (handlers.progressIssues.isEmpty) {
      checks.pass(
        'notifications.progress.shape',
        'Observed progress notifications, if any, had valid token and monotonic progress shape.',
      );
    } else {
      checks.fail(
        'notifications.progress.shape',
        'Observed malformed or non-monotonic progress notifications.',
        details: <String, dynamic>{'issues': handlers.progressIssues},
      );
    }
  }

  Future<void> _inspectStreamableHttpTarget(
    ServerInspectionTarget target,
    McpConnection connection,
    InspectionCheckBuilder checks,
    Map<String, dynamic> metadata,
  ) async {
    if (target.url == null) return;

    final transport = connection.transport;
    if (transport is! StreamableHttpClientTransport) {
      checks.warning(
        'transport.streamable-http',
        'URL target did not use StreamableHttpClientTransport.',
      );
      return;
    }

    metadata['streamableHttp'] = <String, dynamic>{
      if (transport.sessionId != null) 'sessionId': transport.sessionId,
      if (transport.protocolVersion != null)
        'protocolVersion': transport.protocolVersion,
    };
    if (transport.sessionId == null) {
      checks.info(
        'transport.streamable-http.session',
        'No Streamable HTTP session id was established; target may be stateless.',
      );
    } else {
      checks.pass(
        'transport.streamable-http.session',
        'Streamable HTTP session id was established.',
      );
    }

    await _probeStreamableHttpPreflight(
      target.url!,
      transport.sessionId,
      checks,
      metadata,
    );
    await _probeAuthorizationMetadata(target.url!, checks, metadata);

    try {
      await transport.terminateSession();
      checks.pass(
        'transport.streamable-http.delete-session',
        'Streamable HTTP DELETE session termination succeeded or was accepted as unsupported.',
      );
    } catch (error) {
      checks.warning(
        'transport.streamable-http.delete-session',
        'Streamable HTTP DELETE session termination failed: $error',
      );
    }
  }

  Future<void> _probeStreamableHttpPreflight(
    Uri endpoint,
    String? sessionId,
    InspectionCheckBuilder checks,
    Map<String, dynamic> metadata,
  ) async {
    final probes = <Map<String, dynamic>>[];

    final withoutSession = await _httpGetJson(
      endpoint,
      headers: const <String, String>{
        HttpHeaders.acceptHeader: 'application/json, text/event-stream',
      },
    );
    probes.add(<String, dynamic>{
      'name': 'getWithoutSession',
      ...withoutSession,
    });
    final withoutSessionStatus = withoutSession['statusCode'];
    if (withoutSessionStatus == 400 ||
        withoutSessionStatus == 401 ||
        withoutSessionStatus == 404 ||
        withoutSessionStatus == 405) {
      checks.pass(
        'transport.streamable-http.get-without-session',
        'Streamable HTTP GET without a session was rejected or challenged.',
        details: withoutSession,
      );
    } else {
      checks.info(
        'transport.streamable-http.get-without-session',
        'Streamable HTTP GET without a session returned $withoutSessionStatus.',
        details: withoutSession,
      );
    }

    final bogusSession = await _httpGetJson(
      endpoint,
      headers: const <String, String>{
        HttpHeaders.acceptHeader: 'application/json, text/event-stream',
        'Mcp-Session-Id': 'mcp-dart-inspector-bogus-session',
      },
    );
    probes.add(<String, dynamic>{'name': 'bogusSession', ...bogusSession});
    final bogusSessionStatus = bogusSession['statusCode'];
    if (bogusSessionStatus == 400 || bogusSessionStatus == 404) {
      checks.pass(
        'transport.streamable-http.bogus-session',
        'Streamable HTTP rejected a bogus session id.',
        details: bogusSession,
      );
    } else if (sessionId == null) {
      checks.info(
        'transport.streamable-http.bogus-session',
        'Target appears stateless or did not reject a bogus session id.',
        details: bogusSession,
      );
    } else {
      checks.warning(
        'transport.streamable-http.bogus-session',
        'Stateful Streamable HTTP target did not clearly reject a bogus session id.',
        details: bogusSession,
      );
    }

    final originProbe = await _httpGetJson(
      endpoint,
      headers: const <String, String>{
        HttpHeaders.acceptHeader: 'application/json, text/event-stream',
        'origin': 'https://mcp-dart-inspector.invalid',
      },
    );
    probes.add(<String, dynamic>{'name': 'originHeader', ...originProbe});
    checks.info(
      'transport.streamable-http.origin-header',
      'Origin-header preflight returned ${originProbe['statusCode']}.',
      details: originProbe,
    );

    metadata['streamableHttpPreflight'] = probes;
    await _probeAuthorizationChallenge(withoutSession, checks, metadata);
  }

  Future<void> _probeAuthorizationChallenge(
    Map<String, dynamic> response,
    InspectionCheckBuilder checks,
    Map<String, dynamic> metadata,
  ) async {
    final headers = response['headers'];
    final authenticate = headers is Map<String, dynamic>
        ? headers[HttpHeaders.wwwAuthenticateHeader]
        : null;
    if (response['statusCode'] != 401) {
      checks.info(
        'authorization.www-authenticate',
        'Endpoint did not return a 401 authorization challenge during preflight.',
      );
      return;
    }
    if (authenticate is String && authenticate.trim().isNotEmpty) {
      metadata['authorizationChallenge'] = authenticate;
      checks.pass(
        'authorization.www-authenticate',
        'Endpoint returned a WWW-Authenticate challenge.',
        details: <String, dynamic>{'www-authenticate': authenticate},
      );
    } else {
      checks.warning(
        'authorization.www-authenticate',
        'Endpoint returned 401 without a WWW-Authenticate header.',
        details: response,
      );
    }
  }

  Future<void> _probeAuthorizationMetadata(
    Uri endpoint,
    InspectionCheckBuilder checks,
    Map<String, dynamic> metadata,
  ) async {
    final candidates = <Uri>[
      endpoint.replace(
        path: '/.well-known/oauth-protected-resource${endpoint.path}',
      ),
      endpoint.replace(path: '/.well-known/oauth-protected-resource'),
    ];
    final attempts = <Map<String, dynamic>>[];
    for (final candidate in candidates) {
      final result = await _httpGetJson(candidate);
      attempts.add(result);
      if (result['statusCode'] == 200 &&
          result['body'] is Map<String, dynamic>) {
        final body = result['body'] as Map<String, dynamic>;
        metadata['authorization'] = <String, dynamic>{
          'protectedResourceMetadata': body,
          'url': candidate.toString(),
        };
        checks.pass(
          'authorization.protected-resource-metadata',
          'Discovered OAuth protected-resource metadata.',
          details: <String, dynamic>{'url': candidate.toString()},
        );
        _checkProtectedResourceMetadata(body, checks);
        await _probeAuthorizationServerMetadata(body, checks, metadata);
        return;
      }
    }

    checks.info(
      'authorization.protected-resource-metadata',
      'No OAuth protected-resource metadata was discovered for this endpoint.',
      details: <String, dynamic>{'attempts': attempts},
    );
  }

  void _checkProtectedResourceMetadata(
    Map<String, dynamic> metadata,
    InspectionCheckBuilder checks,
  ) {
    final resource = metadata['resource'];
    final authorizationServers = metadata['authorization_servers'];
    if (resource is String &&
        resource.trim().isNotEmpty &&
        authorizationServers is List &&
        authorizationServers.every((server) => server is String)) {
      checks.pass(
        'authorization.protected-resource-metadata.shape',
        'OAuth protected-resource metadata includes resource and authorization_servers.',
      );
    } else {
      checks.fail(
        'authorization.protected-resource-metadata.shape',
        'OAuth protected-resource metadata is missing resource or authorization_servers.',
        details: metadata,
      );
    }
  }

  Future<void> _probeAuthorizationServerMetadata(
    Map<String, dynamic> protectedResourceMetadata,
    InspectionCheckBuilder checks,
    Map<String, dynamic> reportMetadata,
  ) async {
    final authorizationServers =
        protectedResourceMetadata['authorization_servers'];
    if (authorizationServers is! List) return;

    final discoveries = <Map<String, dynamic>>[];
    for (final server in authorizationServers.whereType<String>()) {
      final issuer = Uri.tryParse(server);
      if (issuer == null || !issuer.hasScheme) {
        discoveries.add(<String, dynamic>{
          'issuer': server,
          'error': 'authorization server is not an absolute URI',
        });
        continue;
      }

      Map<String, dynamic>? discovered;
      for (final candidate in _authorizationServerMetadataCandidates(issuer)) {
        final result = await _httpGetJson(candidate);
        discoveries.add(<String, dynamic>{
          'issuer': server,
          'url': candidate.toString(),
          ...result,
        });
        if (result['statusCode'] == 200 &&
            result['body'] is Map<String, dynamic>) {
          discovered = result['body'] as Map<String, dynamic>;
          break;
        }
      }

      if (discovered != null) {
        final hasEndpoints = discovered['authorization_endpoint'] is String &&
            discovered['token_endpoint'] is String;
        if (hasEndpoints) {
          checks.pass(
            'authorization.server-metadata',
            'Discovered OAuth authorization-server metadata for $server.',
          );
        } else {
          checks.warning(
            'authorization.server-metadata',
            'Authorization-server metadata for $server is missing authorization_endpoint or token_endpoint.',
            details: discovered,
          );
        }

        final methods = discovered['code_challenge_methods_supported'];
        if (methods is List && methods.contains('S256')) {
          checks.pass(
            'authorization.pkce-s256',
            'Authorization server $server advertises PKCE S256.',
          );
        } else {
          checks.warning(
            'authorization.pkce-s256',
            'Authorization server $server does not advertise PKCE S256.',
            details: discovered,
          );
        }
      }
    }

    reportMetadata['authorizationServerDiscovery'] = discoveries;
  }

  List<Uri> _authorizationServerMetadataCandidates(Uri issuer) {
    final pathPrefix = issuer.path.endsWith('/')
        ? issuer.path.substring(0, issuer.path.length - 1)
        : issuer.path;
    return <Uri>[
      issuer.replace(
        path: '/.well-known/oauth-authorization-server$pathPrefix',
      ),
      issuer.replace(
        path: '/.well-known/openid-configuration$pathPrefix',
      ),
    ];
  }

  Future<Map<String, dynamic>> _httpGetJson(
    Uri uri, {
    Map<String, String> headers = const <String, String>{},
  }) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri).timeout(
            const Duration(seconds: 2),
          );
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      for (final entry in headers.entries) {
        request.headers.set(entry.key, entry.value);
      }
      final response = await request.close().timeout(
            const Duration(seconds: 2),
          );
      final bodyText = await response.transform(utf8.decoder).join();
      Object? body;
      if (bodyText.trim().isNotEmpty) {
        try {
          body = jsonDecode(bodyText);
        } catch (_) {
          body = bodyText;
        }
      }
      return <String, dynamic>{
        'url': uri.toString(),
        'statusCode': response.statusCode,
        'headers': <String, dynamic>{
          for (final name in _debugHeaderNames)
            if (response.headers.value(name) != null)
              name: response.headers.value(name),
        },
        if (body != null) 'body': body,
      };
    } catch (error) {
      return <String, dynamic>{
        'url': uri.toString(),
        'error': error.toString(),
      };
    } finally {
      client.close(force: true);
    }
  }

  static const Set<String> _debugHeaderNames = <String>{
    HttpHeaders.wwwAuthenticateHeader,
    HttpHeaders.contentTypeHeader,
    'mcp-session-id',
    'mcp-protocol-version',
  };

  String? _toolNameWarning(String name) {
    if (name.isEmpty) return 'Tool name cannot be empty.';
    if (name.length > 128) {
      return 'Tool name exceeds 128 characters: $name.';
    }
    if (!RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(name)) {
      return 'Tool name contains characters outside A-Z, a-z, 0-9, underscore, dash, and dot: $name.';
    }
    return null;
  }
}

/// Explicit live probes requested for server inspection.
class InspectionProbeConfig {
  /// Creates an inspection probe config.
  const InspectionProbeConfig({
    this.toolCalls = const <ToolCallProbe>[],
    this.resource,
    this.prompt,
    this.completion,
    this.task,
  });

  /// Tool calls to execute with caller-provided arguments.
  final List<ToolCallProbe> toolCalls;

  /// Resource read/subscription probe override.
  final ResourceProbe? resource;

  /// Prompt get probe override.
  final PromptProbe? prompt;

  /// Completion probe override.
  final CompletionProbe? completion;

  /// Task probe override.
  final TaskProbe? task;

  /// Parses a JSON probe configuration.
  factory InspectionProbeConfig.fromJson(Map<String, dynamic> json) {
    return InspectionProbeConfig(
      toolCalls:
          _readObjectList(json['tools']).map(ToolCallProbe.fromJson).toList(),
      resource: json['resource'] is Map
          ? ResourceProbe.fromJson(
              (json['resource'] as Map).cast<String, dynamic>(),
            )
          : null,
      prompt: json['prompt'] is Map
          ? PromptProbe.fromJson(
              (json['prompt'] as Map).cast<String, dynamic>(),
            )
          : null,
      completion: json['completion'] is Map
          ? CompletionProbe.fromJson(
              (json['completion'] as Map).cast<String, dynamic>(),
            )
          : null,
      task: json['task'] is Map
          ? TaskProbe.fromJson((json['task'] as Map).cast<String, dynamic>())
          : null,
    );
  }
}

/// Explicit tool call probe.
class ToolCallProbe {
  /// Creates a tool call probe.
  const ToolCallProbe({
    required this.name,
    this.arguments = const <String, dynamic>{},
  });

  /// Tool name.
  final String name;

  /// Tool arguments.
  final Map<String, dynamic> arguments;

  /// Parses a tool call probe.
  factory ToolCallProbe.fromJson(Map<String, dynamic> json) {
    return ToolCallProbe(
      name: json['name'] as String,
      arguments: _readObject(json['arguments']),
    );
  }
}

/// Explicit resource probe.
class ResourceProbe {
  /// Creates a resource probe.
  const ResourceProbe({required this.uri, this.subscribe});

  /// Resource URI.
  final String uri;

  /// Whether subscription should be required.
  final bool? subscribe;

  /// Parses a resource probe.
  factory ResourceProbe.fromJson(Map<String, dynamic> json) {
    return ResourceProbe(
      uri: json['uri'] as String,
      subscribe: json['subscribe'] as bool?,
    );
  }
}

/// Explicit prompt probe.
class PromptProbe {
  /// Creates a prompt probe.
  const PromptProbe({
    required this.name,
    this.arguments = const <String, String>{},
  });

  /// Prompt name.
  final String name;

  /// Prompt arguments.
  final Map<String, String> arguments;

  /// Parses a prompt probe.
  factory PromptProbe.fromJson(Map<String, dynamic> json) {
    return PromptProbe(
      name: json['name'] as String,
      arguments: _readStringObject(json['arguments']),
    );
  }
}

/// Explicit completion probe.
class CompletionProbe {
  /// Creates a completion probe.
  const CompletionProbe({
    required this.prompt,
    required this.argument,
    this.value = '',
  });

  /// Prompt name.
  final String prompt;

  /// Prompt argument name.
  final String argument;

  /// Prefix value to complete.
  final String value;

  /// Parses a completion probe.
  factory CompletionProbe.fromJson(Map<String, dynamic> json) {
    return CompletionProbe(
      prompt: json['prompt'] as String,
      argument: json['argument'] as String,
      value: json['value'] as String? ?? '',
    );
  }
}

/// Explicit task probe.
class TaskProbe {
  /// Creates a task probe.
  const TaskProbe({
    this.tool,
    this.arguments = const <String, dynamic>{},
    this.ttl,
    this.pollInterval,
    this.cancel = false,
  });

  /// Task-capable tool to call.
  final String? tool;

  /// Tool arguments.
  final Map<String, dynamic> arguments;

  /// Requested task TTL.
  final int? ttl;

  /// Requested poll interval.
  final int? pollInterval;

  /// Whether to create then cancel the task instead of waiting for result.
  final bool cancel;

  /// Parses a task probe.
  factory TaskProbe.fromJson(Map<String, dynamic> json) {
    return TaskProbe(
      tool: json['tool'] as String?,
      arguments: _readObject(json['arguments']),
      ttl: json['ttl'] as int?,
      pollInterval: json['pollInterval'] as int?,
      cancel: json['cancel'] as bool? ?? false,
    );
  }
}

List<Map<String, dynamic>> _readObjectList(Object? value) {
  if (value is! List) return const <Map<String, dynamic>>[];
  return value
      .whereType<Map>()
      .map((item) => item.cast<String, dynamic>())
      .toList();
}

Map<String, dynamic> _readObject(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.cast<String, dynamic>();
  return const <String, dynamic>{};
}

Map<String, String> _readStringObject(Object? value) {
  final object = _readObject(value);
  return object.map(
    (key, value) => MapEntry(key, value?.toString() ?? ''),
  );
}

/// Target for server inspection.
class ServerInspectionTarget {
  /// Creates a server inspection target.
  const ServerInspectionTarget({
    required this.command,
    required this.serverArgs,
    required this.url,
    required this.env,
  });

  /// Stdio server command.
  final String? command;

  /// Arguments for [command].
  final List<String> serverArgs;

  /// Streamable HTTP endpoint.
  final Uri? url;

  /// Environment variables for stdio server commands.
  final Map<String, String> env;

  /// Transport kind.
  String get transport {
    if (url != null) return 'streamable-http';
    return 'stdio';
  }

  /// Human-readable target description.
  String get description {
    if (url != null) return url.toString();
    if (command != null) return [command!, ...serverArgs].join(' ');
    return 'local Dart project';
  }
}
