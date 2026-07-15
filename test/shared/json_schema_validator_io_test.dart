import 'dart:io';

import 'package:mcp_dart/src/shared/json_schema/json_schema.dart';
import 'package:mcp_dart/src/shared/json_schema/json_schema_validator.dart';
import 'package:test/test.dart';

void main() {
  test('validation never dereferences a network schema', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var requests = 0;
    final subscription = server.listen((request) {
      requests++;
      request.response
        ..headers.contentType = ContentType.json
        ..write('{"type":"string"}')
        ..close();
    });
    addTearDown(() async {
      await server.close(force: true);
      await subscription.cancel();
    });

    final schema = JsonSchema.fromJson({
      r'$ref': 'http://${server.address.host}:${server.port}/schema.json',
    });

    expect(
      () => schema.validate('value'),
      throwsA(
        isA<JsonSchemaValidationException>().having(
          (error) => error.message,
          'message',
          contains(r'External $ref'),
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(requests, isZero);
  });
}
