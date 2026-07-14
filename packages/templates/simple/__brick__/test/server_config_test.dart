import 'package:test/test.dart';
import 'package:{{name.snakeCase()}}/mcp/server_config.dart';

void main() {
  group('ServerConfig', () {
    test('defaults to stdio and a loopback HTTP host', () {
      final config = ServerConfig.fromArgs(const <String>[]);

      expect(config.transport, TransportType.stdio);
      expect(config.host, '127.0.0.1');
      expect(config.port, 3000);
      expect(config.path, '/mcp');
    });

    test('parses explicit Streamable HTTP options', () {
      final config = ServerConfig.fromArgs(const <String>[
        '--transport',
        'http',
        '--host',
        'localhost',
        '--port',
        '8080',
        '--path',
        '/api/mcp',
      ]);

      expect(config.transport, TransportType.http);
      expect(config.host, 'localhost');
      expect(config.port, 8080);
      expect(config.path, '/api/mcp');
    });

    test('rejects invalid ports', () {
      expect(
        () => ServerConfig.fromArgs(const <String>['--port', '70000']),
        throwsFormatException,
      );
    });
  });
}
