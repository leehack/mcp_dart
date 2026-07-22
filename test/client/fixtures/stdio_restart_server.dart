import 'dart:convert';
import 'dart:io';

const _protocolVersion = '2026-07-28';
const _protocolVersionKey = 'io.modelcontextprotocol/protocolVersion';
const _serverInfoKey = 'io.modelcontextprotocol/serverInfo';
const _subscriptionIdKey = 'io.modelcontextprotocol/subscriptionId';
const _supersededReplayFailure = 'superseded-replay-write-failure';

Future<void> main(List<String> arguments) async {
  final launchCountFile = File(arguments.first);
  final replayBehavior =
      arguments.length > 1 ? arguments[1] : 'acknowledge-first';
  final launchCount = _claimLaunchNumber(launchCountFile);
  var rejectedDiscovery = false;
  final receivedSubscriptionIds = <Object?>[];

  if (replayBehavior == 'stderr-before-first-listener') {
    stderr.writeln('stderr-before-first-listener');
    await stderr.flush();
    File('${launchCountFile.path}.stderr-ready').writeAsStringSync('ready');
  }

  if (replayBehavior == 'malformed-then-valid') {
    final valid = jsonEncode({
      'jsonrpc': '2.0',
      'method': 'fixture/after-malformed',
      'params': <String, dynamic>{},
    });
    stdout.add(utf8.encode('{not-json}\n$valid\n'));
    await stdout.flush();
  }

  if (launchCount > 1 && replayBehavior == 'closed-stdin-after-restart') {
    final inputSubscription = stdin.listen((_) {});
    await inputSubscription.cancel();
    File('${launchCountFile.path}.stdin-closed').writeAsStringSync('ready');
    await Future<void>.delayed(const Duration(seconds: 30));
    return;
  }
  if (launchCount == 2 &&
      replayBehavior == 'closed-stdin-ignore-sigterm-after-restart') {
    final ignoredSigterm = ProcessSignal.sigterm.watch().listen((_) {});
    final inputSubscription = stdin.listen((_) {});
    await inputSubscription.cancel();
    File('${launchCountFile.path}.stdin-closed').writeAsStringSync('ready');
    await Future<void>.delayed(const Duration(minutes: 5));
    await ignoredSigterm.cancel();
    return;
  }
  if (launchCount == 2 &&
      replayBehavior == 'closed-stdin-exit-zero-on-sigterm-after-restart') {
    final handledSigterm = ProcessSignal.sigterm.watch().listen((_) => exit(0));
    final inputSubscription = stdin.listen((_) {});
    await inputSubscription.cancel();
    File('${launchCountFile.path}.stdin-closed').writeAsStringSync('ready');
    await Future<void>.delayed(const Duration(minutes: 5));
    await handledSigterm.cancel();
    return;
  }
  await for (final line
      in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    final message = jsonDecode(line) as Map<String, dynamic>;
    final method = message['method'];
    final id = message['id'];

    if (method == null && id == 999) {
      _writeMarkerAtomically(
        File('${launchCountFile.path}.response'),
        line,
      );
      continue;
    }

    if (method == 'server/discover') {
      final exercisesModernDiscoveryRecovery = launchCount == 1 &&
          (replayBehavior == 'modern-discovery-error-exit' ||
              replayBehavior == 'modern-discovery-error-exit-after-retry');
      if (exercisesModernDiscoveryRecovery && !rejectedDiscovery) {
        _send({
          'jsonrpc': '2.0',
          'id': id,
          'error': {
            'code': -32022,
            'message': 'Unsupported protocol version',
            'data': {
              'supported': [_protocolVersion],
              'requested': '1900-01-01',
            },
          },
        });
        await stdout.flush();
        rejectedDiscovery = true;
        if (replayBehavior == 'modern-discovery-error-exit') {
          exitCode = 17;
          return;
        }
        continue;
      }
      if (exercisesModernDiscoveryRecovery && rejectedDiscovery) {
        exitCode = 17;
        return;
      }

      _send({
        'jsonrpc': '2.0',
        'id': id,
        'result': {
          'resultType': 'complete',
          'supportedVersions': [_protocolVersion],
          'ttlMs': 0,
          'cacheScope': 'private',
          'capabilities': {
            'resources': {'listChanged': true},
            'tools': {'listChanged': true},
          },
          '_meta': {
            _serverInfoKey: {
              'name': 'stdio-restart-fixture',
              'version': '1.0.0',
            },
          },
        },
      });
      if (replayBehavior == 'send-server-request') {
        _send({
          'jsonrpc': '2.0',
          'id': 999,
          'method': 'roots/list',
          'params': <String, dynamic>{},
        });
      }
      continue;
    }

    if (method == 'subscriptions/listen') {
      receivedSubscriptionIds.add(id);
      final params = message['params'] as Map<String, dynamic>;
      final meta = params['_meta'] as Map<String, dynamic>;
      if (meta[_protocolVersionKey] != _protocolVersion) {
        exitCode = 2;
        return;
      }
      final requestedNotifications =
          Map<String, dynamic>.from(params['notifications'] as Map);
      if (launchCount > 1 && replayBehavior == 'reordered-acknowledgment') {
        for (final key in const ['resourceSubscriptions', 'taskIds']) {
          final values = requestedNotifications[key];
          if (values is List) {
            requestedNotifications[key] = values.reversed.toList();
          }
        }
      }
      final acknowledgedNotifications = launchCount > 1 &&
              replayBehavior == 'smaller-acknowledgment' &&
              receivedSubscriptionIds.length == 1
          ? <String, dynamic>{'resourcesListChanged': true}
          : launchCount > 1 && replayBehavior == 'mismatched-acknowledgment'
              ? <String, dynamic>{
                  'taskIds': ['not-requested'],
                }
              : requestedNotifications;
      final acknowledgment = {
        'jsonrpc': '2.0',
        'method': 'notifications/subscriptions/acknowledged',
        'params': {
          'notifications': acknowledgedNotifications,
          '_meta': {
            _subscriptionIdKey: id,
            if (replayBehavior == 'changed-acknowledgment-meta')
              'fixtureLaunch': launchCount,
          },
        },
      };
      final resourceListChanged = {
        'jsonrpc': '2.0',
        'method': 'notifications/resources/list_changed',
        'params': {
          '_meta': {_subscriptionIdKey: id},
        },
      };
      if (launchCount == 2 &&
          replayBehavior == _supersededReplayFailure &&
          id == 2) {
        _send(acknowledgment);
        await stdout.flush();
        exit(17);
      }
      if (launchCount > 1 && replayBehavior == 'acknowledge-then-crash-loop') {
        _send(acknowledgment);
        await stdout.flush();
        exit(17);
      }
      if (replayBehavior == 'cancel-then-crash-before-terminal') {
        _send(acknowledgment);
        _send({
          'jsonrpc': '2.0',
          'method': 'notifications/cancelled',
          'params': {
            'requestId': id,
            'reason': 'fixture terminated the subscription',
            '_meta': {_subscriptionIdKey: id},
          },
        });
        await stdout.flush();
        exit(17);
      }
      if (launchCount > 1 && replayBehavior == 'mismatched-acknowledgment') {
        _send(acknowledgment);
        await stdout.flush();
        continue;
      }
      if (launchCount > 1 &&
          replayBehavior == 'complete-first-replay' &&
          id == 2) {
        _send(acknowledgment);
        _send({
          'jsonrpc': '2.0',
          'id': id,
          'result': {
            'resultType': 'complete',
            'subscriptionId': id,
          },
        });
        await stdout.flush();
        continue;
      }
      if (launchCount > 1 && replayBehavior == 'event-before-acknowledgment') {
        _send(resourceListChanged);
        _send(acknowledgment);
      } else {
        _send(acknowledgment);
        _send(resourceListChanged);
      }
      continue;
    }

    if (method == 'resources/list') {
      _send({
        'jsonrpc': '2.0',
        'id': id,
        'result': {
          'resultType': 'complete',
          'resources': <Object>[],
          'ttlMs': 0,
          'cacheScope': 'private',
        },
      });
      continue;
    }

    if (method == 'fixture/recovery-probe') {
      _send({
        'jsonrpc': '2.0',
        'id': id,
        'result': {
          'replayedSubscriptionIds': receivedSubscriptionIds,
        },
      });
      continue;
    }

    if (method == 'fixture/stderr') {
      final params = message['params'] as Map<String, dynamic>?;
      final byteCount = params?['bytes'] as int? ?? 0;
      if (byteCount > 0) {
        stderr.add(List<int>.filled(byteCount, 0x78));
      }
      stderr.writeln(params?['marker'] ?? 'stderr-$launchCount');
      await stderr.flush();
      // Give the parent-side pipe listener time to drain before signaling that
      // a deliberately unobserved burst is complete.
      if (byteCount > 0) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      if (id != null) {
        _send({
          'jsonrpc': '2.0',
          'id': id,
          'result': <String, dynamic>{},
        });
      }
      continue;
    }

    if (method == 'fixture/malformed-cancellation') {
      _send({
        'jsonrpc': '2.0',
        'method': 'notifications/cancelled',
        'params': {
          'requestId': 2,
          'reason': 'unrelated cancellation',
          '_meta': {_subscriptionIdKey: 'different-subscription'},
        },
      });
      continue;
    }

    if (method == 'fixture/notification-only-activity') {
      _send({
        'jsonrpc': '2.0',
        'method': 'fixture/healthy-notification',
        'params': <String, dynamic>{},
      });
      await stdout.flush();
      continue;
    }

    if (method == 'fixture/crash') {
      exitCode = 17;
      return;
    }

    if (method == 'fixture/exit') {
      return;
    }

    if (method == 'fixture/exit-zero-request') {
      return;
    }

    if (method == 'fixture/final-response-exit') {
      _send({
        'jsonrpc': '2.0',
        'id': id,
        'result': {
          'payload': 'x' * (1024 * 1024),
        },
      });
      await stdout.flush();
      return;
    }
  }
}

void _send(Map<String, dynamic> message) {
  stdout.writeln(jsonEncode(message));
}

void _writeMarkerAtomically(File marker, String contents) {
  final temporary = File('${marker.path}.$pid.tmp');
  try {
    temporary.writeAsStringSync(contents, flush: true);
    if (marker.existsSync()) {
      marker.deleteSync();
    }
    temporary.renameSync(marker.path);
  } finally {
    if (temporary.existsSync()) {
      temporary.deleteSync();
    }
  }
}

int _claimLaunchNumber(File markerPrefix) {
  for (var launchNumber = 1; launchNumber <= 1000; launchNumber++) {
    final marker = File('${markerPrefix.path}.launch-$launchNumber');
    try {
      marker.createSync(exclusive: true);
      return launchNumber;
    } on FileSystemException {
      // Another fixture process already owns this immutable launch marker.
      // Exclusive files avoid replacing a counter that the parent test may
      // have open, which is not reliable on Windows.
      if (!marker.existsSync()) {
        rethrow;
      }
    }
  }
  throw StateError('Stdio fixture exceeded 1000 launches.');
}
