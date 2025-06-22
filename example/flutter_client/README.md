# Flutter MCP Client Demo

A cross-platform Flutter demonstration of the MCP Dart client library.

## Features

- 🚀 **Cross-Platform**: Works on Web, Desktop (macOS, Windows, Linux), and Mobile
- ⚡ **Fast Native Performance**: Uses `dart:io` for optimal speed on native platforms
- 🌐 **Web Compatible**: Gracefully falls back to `package:http` for web browsers
- 🔐 **Secure Configuration**: Uses `.env` files to keep private URLs out of source code

## Quick Start

1. **Install dependencies:**
   ```bash
   flutter pub get
   ```

2. **Set up environment (optional for Zapier):**
   ```bash
   cp .env.example .env
   # Edit .env and set your ZAPIER_MCP_URL
   ```

3. **Run the app:**
   ```bash
   # Desktop
   flutter run -d macos
   flutter run -d windows  
   flutter run -d linux

   # Web
   flutter run -d chrome

   # Mobile
   flutter run -d ios
   flutter run -d android
   ```

## Supported MCP Servers

- **🤗 Hugging Face**: `https://huggingface.co/mcp` (public demo)
- **⚡ Zapier**: Requires your private token in `.env` file
- **📚 DeepWiki**: `https://mcp.deepwiki.com/mcp`
- **Custom**: Any MCP-compliant server

## Environment Variables

Create a `.env` file from the example:

```bash
cp .env.example .env
```

Then edit `.env` with your values:

```env
ZAPIER_MCP_URL=https://mcp.zapier.com/api/mcp/s/YOUR_TOKEN_HERE==/mcp
```

## Web Limitations

When running on web browsers, the app cannot directly connect to MCP servers due to CORS policies. For production web deployment, you'll need:

- A CORS proxy server
- Server-side API that forwards requests to MCP servers
- MCP servers that explicitly support browser clients

## Development

This demo showcases the MCP Dart library's conditional compilation feature:

- **Native platforms**: Uses high-performance `dart:io.HttpClient` with streaming SSE
- **Web platform**: Uses `package:http` for compatibility

The same code runs everywhere with optimal performance for each platform.
