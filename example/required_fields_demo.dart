import 'package:mcp_dart/mcp_dart.dart';

void main() {
  // Create a tool with required fields - this simulates what an MCP server would send
  final calculatorTool = Tool(
    name: 'calculate',
    description: 'Performs mathematical calculations',
    inputSchema: JsonSchema.object(
      properties: {
        'operation': JsonSchema.string(
          enumValues: ['add', 'subtract', 'multiply', 'divide'],
          description: 'The mathematical operation to perform',
        ),
        'a': JsonSchema.number(description: 'First number'),
        'b': JsonSchema.number(description: 'Second number'),
        'precision': JsonSchema.integer(
          description: 'Number of decimal places (optional)',
          defaultValue: 2,
        ),
      },
      required: ['operation', 'a', 'b'],
    ),
    outputSchema: JsonSchema.object(
      properties: {
        'result': JsonSchema.number(description: 'The calculation result'),
        'equation': JsonSchema.string(
          description: 'The equation that was calculated',
        ),
      },
      required: ['result'], // ← Output required fields also preserved!
    ),
  );

  print('=== MCP Tool Schema Demo ===');
  print('Tool: ${calculatorTool.name}');
  print('Description: ${calculatorTool.description}');

  // Serialize to JSON (what MCP client receives)
  final toolJson = calculatorTool.toJson();
  print('\n=== Serialized Tool JSON ===');
  print('Input required fields: ${toolJson['inputSchema']['required']}');
  print('Output required fields: ${toolJson['outputSchema']['required']}');

  // This demonstrates the fix - required fields are preserved in JSON
  print('\n=== Full Input Schema ===');
  final inputSchema = toolJson['inputSchema'] as Map<String, dynamic>;
  print('Type: ${inputSchema['type']}');
  print('Required: ${inputSchema['required']}');
  print('Properties: ${(inputSchema['properties'] as Map).keys.join(', ')}');

  // Deserialize back from JSON (roundtrip test)
  final deserializedTool = Tool.fromJson(toolJson);
  print('\n=== Roundtrip Test ===');
  print(
    'Original required: ${(calculatorTool.inputSchema as JsonObject).required}',
  );
  print(
    'Deserialized required: ${(deserializedTool.inputSchema as JsonObject).required}',
  );
  print(
    'Match: ${_listsEqual((calculatorTool.inputSchema as JsonObject).required, (deserializedTool.inputSchema as JsonObject).required)}',
  );

  // Convert to OpenAI function calling format
  print('\n=== OpenAI Function Format ===');
  final openaiFunction = <String, dynamic>{
    'type': 'function',
    'function': <String, dynamic>{
      'name': calculatorTool.name,
      'description': calculatorTool.description,
      'parameters': calculatorTool.inputSchema.toJson(),
    },
  };

  final functionObj = openaiFunction['function'] as Map<String, dynamic>;
  final parameters = functionObj['parameters'] as Map<String, dynamic>;
  print('Function name: ${functionObj['name']}');
  print('Required parameters: ${parameters['required']}');
  print('✓ Ready for LLM integration!');

  // Convert to Anthropic Claude format
  print('\n=== Anthropic Claude Format ===');
  final anthropicTool = <String, dynamic>{
    'name': calculatorTool.name,
    'description': calculatorTool.description,
    'input_schema': calculatorTool.inputSchema.toJson(),
  };

  final claudeSchema = anthropicTool['input_schema'] as Map<String, dynamic>;
  print('Tool name: ${anthropicTool['name']}');
  print('Required parameters: ${claudeSchema['required']}');
  print('✓ Ready for Claude integration!');

  // Simulate a real MCP server response
  print('\n=== Simulated MCP Server Response ===');
  final listToolsResult = ListToolsResult(tools: [calculatorTool]);
  final serverResponse = listToolsResult.toJson();

  print('Server response preserves required fields:');
  final tools = serverResponse['tools'] as List;
  final firstTool = tools[0] as Map<String, dynamic>;
  final firstToolInputSchema = firstTool['inputSchema'] as Map<String, dynamic>;
  print('  Tool: ${firstTool['name']}');
  print('  Required: ${firstToolInputSchema['required']}');
  print('✓ MCP server integration works!');
}

bool _listsEqual(List<String>? a, List<String>? b) {
  if (a == null && b == null) return true;
  if (a == null || b == null) return false;
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
