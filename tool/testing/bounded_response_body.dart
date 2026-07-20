import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

Future<String> readBoundedUtf8ResponseBody(
  Stream<List<int>> body, {
  required Duration timeout,
  required int maxBytes,
}) async {
  if (timeout <= Duration.zero) {
    throw ArgumentError.value(timeout, 'timeout', 'Must be positive.');
  }
  if (maxBytes <= 0) {
    throw ArgumentError.value(maxBytes, 'maxBytes', 'Must be positive.');
  }

  final stopwatch = Stopwatch()..start();
  final iterator = StreamIterator<List<int>>(body);
  final bytes = BytesBuilder(copy: false);
  try {
    while (true) {
      final remaining = timeout - stopwatch.elapsed;
      if (remaining <= Duration.zero) {
        throw TimeoutException(
          'Timed out reading the response body after $timeout.',
          timeout,
        );
      }
      final hasNext = await iterator.moveNext().timeout(
            remaining,
            onTimeout: () => throw TimeoutException(
              'Timed out reading the response body after $timeout.',
              timeout,
            ),
          );
      if (!hasNext) {
        return utf8.decode(bytes.takeBytes());
      }

      final chunk = iterator.current;
      if (bytes.length + chunk.length > maxBytes) {
        throw StateError(
          'Response body exceeded the $maxBytes-byte limit.',
        );
      }
      bytes.add(chunk);
    }
  } finally {
    stopwatch.stop();
    await iterator.cancel();
  }
}
