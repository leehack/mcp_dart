# OAuth Quick Start Guide

> **Quick 5-minute guide** | Need details? See [GitHub Setup](GITHUB_SETUP.md) | Building a server? See [Server Guide](OAUTH_SERVER_GUIDE.md)

Get started with OAuth authentication in MCP Dart SDK in 5 minutes.

## Overview

This guide shows you how to quickly set up both an OAuth-protected MCP server and a client that connects to it.

## Prerequisites

- Dart SDK 3.0 or later
- OAuth provider credentials (GitHub or Google)
- Basic understanding of OAuth 2.0

## Setup (5 minutes)

### Step 1: Get OAuth Credentials

**GitHub OAuth App**: Follow detailed instructions in [GitHub Setup Guide](GITHUB_SETUP.md#step-1-create-a-github-oauth-app)

Quick version:

1. Go to <https://github.com/settings/developers>
2. Create "New OAuth App" with callback: `http://localhost:8080/callback`
3. Copy Client ID and Secret

### Step 2: Set Environment Variables

```bash
# For GitHub
export GITHUB_CLIENT_ID=your_github_client_id
export GITHUB_CLIENT_SECRET=your_github_client_secret
```

See [GitHub Setup Guide](GITHUB_SETUP.md#step-2-set-environment-variables) for platform-specific instructions.

### Step 3: Start the OAuth Server

```bash
dart run example/authentication/oauth_server_example.dart github
```

Server will start on `http://localhost:3000/mcp`

> **Note**: This starts your own OAuth-protected MCP server, not the GitHub MCP server.

### Step 4: Get Access Token

In a new terminal, run the OAuth flow:

```bash
dart run example/authentication/github_oauth_example.dart
```

This opens your browser, authorizes the app, and displays your access token. Copy it for Step 5.

### Step 5: Test the Connection

```bash
# Test with curl
curl -H "Authorization: Bearer YOUR_ACCESS_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{
       "jsonrpc": "2.0",
       "method": "initialize",
       "params": {
         "protocolVersion": "2024-11-05",
         "capabilities": {},
         "clientInfo": {"name": "test", "version": "1.0.0"}
       },
       "id": 1
     }' \
     http://localhost:3000/mcp
```

Success response:

```json
{
  "jsonrpc": "2.0",
  "result": {
    "protocolVersion": "2024-11-05",
    "capabilities": {...},
    "serverInfo": {...}
  },
  "id": 1
}
```

## Next Steps

For production deployment and advanced features, see:

- **Production Setup**: [OAUTH_SERVER_GUIDE.md](OAUTH_SERVER_GUIDE.md#security-considerations)
- **Token Refresh**: [OAUTH_SERVER_GUIDE.md](OAUTH_SERVER_GUIDE.md#token-refresh-flow)
- **Scope-Based Access**: [OAUTH_SERVER_GUIDE.md](OAUTH_SERVER_GUIDE.md#scope-based-access-control)
- **Custom Providers**: [OAUTH_SERVER_GUIDE.md](OAUTH_SERVER_GUIDE.md#custom-oauth-provider)

## Troubleshooting

See [OAUTH_SERVER_GUIDE.md](OAUTH_SERVER_GUIDE.md#troubleshooting) for detailed troubleshooting.

**Common issues**:

- **Unauthorized**: Check token format (`Bearer <token>`)
- **Port conflict**: Ensure ports 3000 and 8080 are available
- **Connection failed**: Verify server is running

## Support

- GitHub Issues: [mcp_dart/issues](https://github.com/leehack/mcp_dart/issues)
- MCP Specification: <https://modelcontextprotocol.io/>
- OAuth 2.0 Spec: <https://oauth.net/2/>
