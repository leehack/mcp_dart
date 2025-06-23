// compile time constrants.
// you can set them from the CLI:
//
// $ flutter run --dart-define=ZAPIER_MCP_URL=$ZAPIER_MCP_URL
//
// you can set them from your VSCode launch.json:
//
// {
//   "version": "0.2.0",
//   "configurations": [
//     {
//       "name": "flutter_client",
//       "request": "launch",
//       "type": "dart",
//       "toolArgs": ["--dart-define=ZAPIER_MCP_URL=${env:ZAPIER_MCP_URL}"]
//     }
//   ]
// }
//
class Env {
  // ignore: constant_identifier_names
  static const ZAPIER_MCP_URL =
      String.fromEnvironment('ZAPIER_MCP_URL', defaultValue: '');
}
