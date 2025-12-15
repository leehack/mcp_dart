import 'package:test/test.dart';
import 'package:mcp_dart/src/shared/json_schema/json_schema.dart';
import 'package:mcp_dart/src/shared/json_schema/json_schema_validator.dart';

void main() {
  group('JsonSchemaValidation', () {
    test('validates simple string schema', () {
      final schema = JsonSchema.string(minLength: 3);
      schema.validate("abc"); // Should pass

      expect(
        () => schema.validate("ab"),
        throwsA(isA<JsonSchemaValidationException>()),
      );
    });

    test('validates object schema', () {
      final schema = JsonSchema.object(
        properties: {
          "name": JsonSchema.string(),
          "age": JsonSchema.integer(),
        },
        required: ["name"],
      );

      schema.validate({"name": "John", "age": 30}); // Pass
      schema.validate({"name": "John"}); // Pass (age optional)

      expect(
        () => schema.validate({"age": 30}),
        throwsA(isA<JsonSchemaValidationException>()),
      );
    });

    test('validates complex validation from map (legacy support)', () {
      final mapSchema = {"type": "string", "minLength": 3};
      // Simulating what happens when we convert from Map
      final schema = JsonSchema.fromJson(mapSchema);
      schema.validate("abc");
      expect(
        () => schema.validate("ab"),
        throwsA(isA<JsonSchemaValidationException>()),
      );
    });
  });
}
