# Flutter MCP Client Demo

A cross-platform Flutter demonstration of the MCP Dart client library.

## Features

- 🚀 **Cross-Platform**: Works on Web and macOS
- ⚡ **Fast Native Performance**: Uses `dart:io` for optimal speed on native
  platforms
- 🌐 **Web Compatible**: Gracefully falls back to `package:http` for web
  browsers
- 🔐 **Secure Configuration**: Uses `--dart-define` to keep private URLs out of
  source code

## Quick Start

1. **Install dependencies:**
   ```bash
   flutter pub get
   ```

2. **Run the app:**
   ```bash
   # macOS
   flutter run -d macos

   # Web
   flutter run -d chrome

   # With custom Zapier URL
   flutter run -d macos --dart-define=ZAPIER_MCP_URL=https://mcp.zapier.com/api/mcp/s/YOUR_TOKEN_HERE==/mcp

   flutter run -d chrome --dart-define=ZAPIER_MCP_URL=https://mcp.zapier.com/api/mcp/s/YOUR_TOKEN_HERE==/mcp
   ```

## Supported MCP Servers

- **🤗 Hugging Face**: `https://huggingface.co/mcp` (public demo)
- **⚡ Zapier**: Requires your private token via `--dart-define` (see setup
  instructions below)
- **📚 DeepWiki**: `https://mcp.deepwiki.com/mcp`
- **Custom**: Any MCP-compliant server

## Environment Variables

### Command Line

Pass environment variables using `--dart-define`:

```bash
flutter run --dart-define=ZAPIER_MCP_URL=https://mcp.zapier.com/api/mcp/s/YOUR_TOKEN_HERE==/mcp
```

For multiple variables:

```bash
flutter run --dart-define=ZAPIER_MCP_URL=your_zapier_url --dart-define=OTHER_VAR=value
```

### VS Code Launch Configuration

Set environment variables in your shell, then use VS Code's launch
configuration:

```bash
export ZAPIER_MCP_URL=https://mcp.zapier.com/api/mcp/s/YOUR_TOKEN_HERE==/mcp
```

The launch configuration will automatically pick up the environment variable and
pass it via `--dart-define`.

### Getting a Zapier MCP URL

To get a `ZAPIER_MCP_URL`:

1. First set up a "MCP CLI Proxy MCP Server" on Zapier (https://mcp.zapier.com/)
2. You want the Server URL for Streamable HTTP
3. The URL format will be:
   `https://mcp.zapier.com/api/mcp/s/YOUR_TOKEN_HERE==/mcp`

## Web Limitations

When running on web browsers, the app cannot directly connect to *some* MCP
servers due to CORS policies. For access to those MCP servers on the web, you
should consider:

- A CORS proxy server
- Server-side API that forwards requests to MCP servers
- MCP servers that explicitly support browser clients

## Development

This demo showcases the MCP Dart library's conditional compilation feature:

- **Native platforms**: Uses high-performance `dart:io.HttpClient` with
  streaming SSE
- **Web platform**: Uses `package:http` for compatibility

The same code runs everywhere with optimal performance for each platform.
