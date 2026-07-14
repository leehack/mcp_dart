# Safe fetch server

This example exposes a `fetch` MCP tool over stdio. It returns a bounded slice
of text from a public HTTP or HTTPS URL.

## Requirements

- Dart 3.5 or later

```bash
dart pub get
dart run bin/fetch_server.dart
```

The example treats every tool argument as untrusted input. Its network policy:

- accepts only HTTP and HTTPS URLs without embedded credentials;
- resolves and rejects loopback, private, link-local, multicast, unspecified,
  documentation, and other non-public addresses;
- connects directly to the validated address while retaining the original host
  name for HTTPS certificate verification;
- disables automatic redirects and repeats validation for every redirect;
- limits the full operation to 10 seconds, five redirects, and 1 MiB of
  decompressed response data.

These controls make the demo safer to run, but they are not a complete
production egress policy. Production deployments should also enforce outbound
network rules outside the process, set an application-specific domain
allowlist, consider content-type restrictions, and apply authentication,
authorization, logging, and rate limits.
