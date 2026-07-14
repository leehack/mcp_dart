import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Resolves a host name to every address returned by DNS.
typedef HostResolver = Future<List<InternetAddress>> Function(String host);

/// A bounded HTTP response returned by [SafeFetcher].
class SafeFetchResponse {
  const SafeFetchResponse({
    required this.body,
    required this.statusCode,
    required this.uri,
    this.reasonPhrase,
  });

  final String body;
  final int statusCode;
  final Uri uri;
  final String? reasonPhrase;
}

/// An expected safety or policy failure while fetching a URL.
class SafeFetchException implements Exception {
  const SafeFetchException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Fetches public HTTP(S) URLs with limits suitable for this MCP example.
///
/// Every URL, including every redirect target, is resolved and checked before
/// a request is sent. The default client also connects to the checked address
/// directly, preventing a second DNS lookup from changing the destination
/// between validation and connection.
class SafeFetcher {
  /// Creates a public-network fetcher.
  ///
  /// [testClient] makes HTTP behavior deterministic in tests. Leave it `null`
  /// in real use so connections are pinned to the validated DNS addresses.
  SafeFetcher({
    http.Client? testClient,
    HostResolver? resolver,
    this.maxRedirects = 5,
    this.maxResponseBytes = 1024 * 1024,
    this.requestTimeout = const Duration(seconds: 10),
  })  : _testClient = testClient,
        _resolver = resolver ?? _defaultResolver {
    if (maxRedirects < 0) {
      throw ArgumentError.value(maxRedirects, 'maxRedirects');
    }
    if (maxResponseBytes <= 0) {
      throw ArgumentError.value(maxResponseBytes, 'maxResponseBytes');
    }
    if (requestTimeout <= Duration.zero) {
      throw ArgumentError.value(requestTimeout, 'requestTimeout');
    }
  }

  /// The maximum number of redirects followed for one fetch.
  final int maxRedirects;

  /// The maximum decompressed response-body size.
  final int maxResponseBytes;

  /// The total time budget for DNS, redirects, headers, and response bytes.
  final Duration requestTimeout;

  final http.Client? _testClient;
  final HostResolver _resolver;

  /// Fetches [initialUri] after validating every network destination.
  Future<SafeFetchResponse> fetch(Uri initialUri) async {
    final stopwatch = Stopwatch()..start();
    var currentUri = initialUri;
    var redirectCount = 0;

    while (true) {
      _validateUri(currentUri);
      final addresses = await _resolvePublicAddresses(currentUri, stopwatch);
      final ownsClient = _testClient == null;
      final client =
          _testClient ?? _createPinnedClient(currentUri, addresses, stopwatch);

      try {
        final request = http.Request('GET', currentUri)
          ..followRedirects = false
          ..persistentConnection = false
          ..headers['accept'] = 'text/*, application/json;q=0.9, */*;q=0.1'
          ..headers['user-agent'] = 'mcp-dart-fetch-example/1.0';
        final response = await _withinBudget(client.send(request), stopwatch);

        final location = response.headers['location'];
        if (_isRedirect(response.statusCode) && location != null) {
          if (!ownsClient) {
            await _withinBudget(_cancelBody(response.stream), stopwatch);
          }
          if (redirectCount >= maxRedirects) {
            throw SafeFetchException(
              'Fetch stopped after $maxRedirects redirects.',
            );
          }
          if (location.trim().isEmpty) {
            throw const SafeFetchException(
              'The server returned an empty redirect location.',
            );
          }

          try {
            currentUri = currentUri.resolve(location);
          } on FormatException {
            throw const SafeFetchException(
              'The server returned an invalid redirect location.',
            );
          }
          redirectCount++;
          continue;
        }

        final declaredLength = response.contentLength;
        if (declaredLength != null && declaredLength > maxResponseBytes) {
          await _withinBudget(_cancelBody(response.stream), stopwatch);
          throw SafeFetchException(
            'Response exceeds the $maxResponseBytes-byte limit.',
          );
        }

        final bodyBytes = await _readBoundedBody(response.stream, stopwatch);
        return SafeFetchResponse(
          body: _decodeBody(bodyBytes, response.headers),
          statusCode: response.statusCode,
          reasonPhrase: response.reasonPhrase,
          uri: currentUri,
        );
      } on TimeoutException {
        throw const SafeFetchException('Fetch timed out.');
      } finally {
        if (ownsClient) {
          client.close();
        }
      }
    }
  }

  Future<List<InternetAddress>> _resolvePublicAddresses(
    Uri uri,
    Stopwatch stopwatch,
  ) async {
    final literalAddress = InternetAddress.tryParse(uri.host);
    late final List<InternetAddress> addresses;
    if (literalAddress != null) {
      addresses = [literalAddress];
    } else {
      try {
        addresses = await _withinBudget(_resolver(uri.host), stopwatch);
      } on SafeFetchException {
        rethrow;
      } on TimeoutException {
        throw const SafeFetchException('Fetch timed out during DNS lookup.');
      } on SocketException {
        throw SafeFetchException('Could not resolve ${uri.host}.');
      }
    }

    if (addresses.isEmpty) {
      throw SafeFetchException('Could not resolve ${uri.host}.');
    }
    if (addresses.any((address) => !_isPublicAddress(address))) {
      throw SafeFetchException(
        'Blocked non-public network destination: ${uri.host}.',
      );
    }
    return addresses;
  }

  http.Client _createPinnedClient(
    Uri uri,
    List<InternetAddress> addresses,
    Stopwatch stopwatch,
  ) {
    final ioClient = HttpClient()
      ..autoUncompress = true
      ..connectionTimeout = _remaining(stopwatch)
      ..findProxy = (_) => 'DIRECT';
    ioClient.connectionFactory = (requestUri, proxyHost, proxyPort) async {
      if (proxyHost != null || proxyPort != null) {
        throw const SafeFetchException('HTTP proxies are disabled.');
      }
      if (requestUri.scheme != uri.scheme ||
          requestUri.host != uri.host ||
          requestUri.port != uri.port) {
        throw const SafeFetchException(
          'The HTTP client attempted an unvalidated destination.',
        );
      }

      Socket? activeSocket;
      var cancelled = false;
      void trackSocket(Socket socket) {
        activeSocket = socket;
        if (cancelled) {
          socket.destroy();
        }
      }

      return ConnectionTask.fromSocket(
        _connectPinned(uri, addresses, stopwatch, trackSocket),
        () {
          cancelled = true;
          activeSocket?.destroy();
        },
      );
    };
    return IOClient(ioClient);
  }

  Future<Socket> _connectPinned(
    Uri uri,
    List<InternetAddress> addresses,
    Stopwatch stopwatch,
    void Function(Socket socket) trackSocket,
  ) async {
    for (final address in addresses) {
      Socket? socket;
      try {
        socket = await Socket.connect(
          address,
          uri.port,
          timeout: _remaining(stopwatch),
        );
        trackSocket(socket);
        if (uri.scheme == 'https') {
          final secureSocket = await SecureSocket.secure(
            socket,
            host: uri.host,
            supportedProtocols: const ['http/1.1'],
          ).timeout(_remaining(stopwatch));
          trackSocket(secureSocket);
          return secureSocket;
        }
        return socket;
      } on SafeFetchException {
        socket?.destroy();
        rethrow;
      } on TimeoutException {
        socket?.destroy();
        throw const SafeFetchException('Fetch timed out.');
      } catch (_) {
        socket?.destroy();
      }
    }
    throw SafeFetchException(
      'Could not connect to the validated address for ${uri.host}.',
    );
  }

  Future<List<int>> _readBoundedBody(
    Stream<List<int>> stream,
    Stopwatch stopwatch,
  ) async {
    final iterator = StreamIterator<List<int>>(stream);
    final bytes = BytesBuilder(copy: false);
    var byteCount = 0;

    try {
      while (await _withinBudget(iterator.moveNext(), stopwatch)) {
        final chunk = iterator.current;
        byteCount += chunk.length;
        if (byteCount > maxResponseBytes) {
          throw SafeFetchException(
            'Response exceeds the $maxResponseBytes-byte limit.',
          );
        }
        bytes.add(chunk);
      }
      return bytes.takeBytes();
    } finally {
      unawaited(iterator.cancel());
    }
  }

  Future<T> _withinBudget<T>(Future<T> future, Stopwatch stopwatch) {
    return future.timeout(
      _remaining(stopwatch),
      onTimeout: () => throw const SafeFetchException('Fetch timed out.'),
    );
  }

  Duration _remaining(Stopwatch stopwatch) {
    final remaining = requestTimeout - stopwatch.elapsed;
    if (remaining <= Duration.zero) {
      throw const SafeFetchException('Fetch timed out.');
    }
    return remaining;
  }
}

Future<List<InternetAddress>> _defaultResolver(String host) {
  return InternetAddress.lookup(host);
}

Future<void> _cancelBody(Stream<List<int>> stream) async {
  final subscription = stream.listen(null);
  await subscription.cancel();
}

String _decodeBody(List<int> bytes, Map<String, String> headers) {
  try {
    return http.Response.bytes(bytes, HttpStatus.ok, headers: headers).body;
  } on FormatException {
    return utf8.decode(bytes, allowMalformed: true);
  }
}

bool _isRedirect(int statusCode) {
  return statusCode == HttpStatus.movedPermanently ||
      statusCode == HttpStatus.found ||
      statusCode == HttpStatus.seeOther ||
      statusCode == HttpStatus.temporaryRedirect ||
      statusCode == HttpStatus.permanentRedirect;
}

void _validateUri(Uri uri) {
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    throw const SafeFetchException('Only http and https URLs are allowed.');
  }
  if (!uri.hasAuthority || uri.host.isEmpty) {
    throw const SafeFetchException('The URL must include a host.');
  }
  if (uri.userInfo.isNotEmpty) {
    throw const SafeFetchException('URLs containing credentials are blocked.');
  }
}

bool _isPublicAddress(InternetAddress address) {
  if (address.type == InternetAddressType.unix ||
      address.isLoopback ||
      address.isLinkLocal ||
      address.isMulticast) {
    return false;
  }

  final bytes = address.rawAddress;
  if (address.type == InternetAddressType.IPv4 && bytes.length == 4) {
    return _isPublicIpv4(bytes);
  }
  if (address.type != InternetAddressType.IPv6 || bytes.length != 16) {
    return false;
  }

  if (bytes.every((byte) => byte == 0) ||
      (bytes[0] & 0xfe) == 0xfc ||
      (bytes[0] == 0xfe &&
          ((bytes[1] & 0xc0) == 0x80 || (bytes[1] & 0xc0) == 0xc0)) ||
      bytes[0] == 0xff) {
    return false;
  }

  // IPv4-compatible and IPv4-mapped forms must obey the IPv4 policy too.
  if (bytes.take(10).every((byte) => byte == 0) &&
      ((bytes[10] == 0 && bytes[11] == 0) ||
          (bytes[10] == 0xff && bytes[11] == 0xff))) {
    return _isPublicIpv4(bytes.sublist(12));
  }

  // Validate the embedded IPv4 address in the well-known NAT64 prefix.
  if (bytes[0] == 0x00 &&
      bytes[1] == 0x64 &&
      bytes[2] == 0xff &&
      bytes[3] == 0x9b &&
      bytes.sublist(4, 12).every((byte) => byte == 0)) {
    return _isPublicIpv4(bytes.sublist(12));
  }

  // Block non-public and transition ranges that can encode another target.
  if ((bytes[0] == 0x01 &&
          bytes[1] == 0x00 &&
          bytes.sublist(2, 8).every((byte) => byte == 0)) ||
      (bytes[0] == 0x20 &&
          bytes[1] == 0x01 &&
          bytes[2] == 0x00 &&
          bytes[3] == 0x00) ||
      (bytes[0] == 0x20 &&
          bytes[1] == 0x01 &&
          bytes[2] == 0x00 &&
          bytes[3] == 0x02 &&
          bytes[4] == 0x00 &&
          bytes[5] == 0x00) ||
      (bytes[0] == 0x20 &&
          bytes[1] == 0x01 &&
          bytes[2] == 0x00 &&
          bytes[3] >= 0x10 &&
          bytes[3] <= 0x2f) ||
      (bytes[0] == 0x20 &&
          bytes[1] == 0x01 &&
          bytes[2] == 0x0d &&
          bytes[3] == 0xb8) ||
      (bytes[0] == 0x20 && bytes[1] == 0x02) ||
      (bytes[0] == 0x3f && (bytes[1] & 0xf0) == 0xf0) ||
      (bytes[0] == 0x00 &&
          bytes[1] == 0x64 &&
          bytes[2] == 0xff &&
          bytes[3] == 0x9b &&
          bytes[4] == 0x00 &&
          bytes[5] == 0x01)) {
    return false;
  }

  return true;
}

bool _isPublicIpv4(List<int> bytes) {
  final first = bytes[0];
  final second = bytes[1];
  final third = bytes[2];

  return first != 0 &&
      first != 10 &&
      first != 127 &&
      !(first == 100 && second >= 64 && second <= 127) &&
      !(first == 169 && second == 254) &&
      !(first == 172 && second >= 16 && second <= 31) &&
      !(first == 192 && second == 0 && third == 0) &&
      !(first == 192 && second == 0 && third == 2) &&
      !(first == 192 && second == 88 && third == 99) &&
      !(first == 192 && second == 168) &&
      !(first == 198 && (second == 18 || second == 19)) &&
      !(first == 198 && second == 51 && third == 100) &&
      !(first == 203 && second == 0 && third == 113) &&
      first < 224;
}
