import 'dart:async';
import 'dart:convert';
import 'dart:io';

// This fixture deliberately leaves stdin unread so a large client write
// remains blocked while the client handles oversized stdout.
Future<void> main(List<String> args) async {
  final markerPrefix = args.single;
  final launches = File('$markerPrefix.launches');
  final launchCount =
      launches.existsSync() ? int.parse(launches.readAsStringSync()) + 1 : 1;
  launches.writeAsStringSync('$launchCount');

  stdout.writeln(
    jsonEncode({
      'jsonrpc': '2.0',
      'id': 1,
      'result': {
        'supportedVersions': ['2026-07-28'],
      },
    }),
  );
  await stdout.flush();

  if (launchCount > 1) {
    await Future<void>.delayed(const Duration(seconds: 30));
    return;
  }

  await _waitForFile('$markerPrefix.overflow');
  stdout.add(List<int>.filled(1025, 120));
  await stdout.flush();

  // The parent acknowledges the error from its onerror callback. The next
  // response must not be delivered, even while process cleanup awaits stdin.
  await _waitForFile('$markerPrefix.overflow-observed');
  stdout.writeln(jsonEncode({'jsonrpc': '2.0', 'id': 99, 'result': {}}));
  await stdout.flush();
  await Future<void>.delayed(const Duration(milliseconds: 10));
  stdout.add(List<int>.filled(1025, 120));
  await stdout.flush();
  File('$markerPrefix.sent-after-overflow').writeAsStringSync('sent');
  await Future<void>.delayed(const Duration(seconds: 30));
}

Future<void> _waitForFile(String path) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (!File(path).existsSync()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('Timed out waiting for $path');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
