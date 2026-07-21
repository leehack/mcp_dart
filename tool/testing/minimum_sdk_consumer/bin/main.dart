import 'package:mcp_dart/mcp_dart.dart';

void main() {
  final schema = JsonSchema.fromJson(const {'type': 'string'});
  schema.validate('minimum-sdk');

  const request = JsonRpcListToolsRequest(id: 1);
  if (request.method != Method.toolsList) {
    throw StateError('Unexpected tools/list request method.');
  }
}
