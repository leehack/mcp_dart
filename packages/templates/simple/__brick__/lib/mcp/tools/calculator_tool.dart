import 'package:mcp_dart/mcp_dart.dart';

import 'base_tool.dart';

/// A simple tool that adds two numbers.
class CalculatorTool extends BaseTool {
  @override
  String get name => 'add';

  @override
  String get description => 'Adds two numbers';

  @override
  ToolInputSchema get inputSchema => ToolInputSchema(
        properties: {
          'a': JsonSchema.number(description: 'First number'),
          'b': JsonSchema.number(description: 'Second number'),
        },
        required: ['a', 'b'],
      );

  @override
  ToolOutputSchema? get outputSchema => ToolOutputSchema(
        properties: {
          'result': JsonSchema.number(description: 'The sum of a and b'),
        },
      );

  @override
  Future<CallToolResult> execute(
      Map<String, dynamic> args, RequestHandlerExtra? extra) async {
    final a = args['a'] as num;
    final b = args['b'] as num;
    return CallToolResult(
      content: [TextContent(text: 'Result: ${a + b}')],
    );
  }
}
