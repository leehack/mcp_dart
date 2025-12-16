# Testing GitHub MCP Server with OAuth

> **Quick start?** See [5-min guide](OAUTH_QUICK_START.md) | **Building OAuth server?** See [Server Guide](OAUTH_SERVER_GUIDE.md)

This guide walks you through setting up and testing the GitHub MCP server with OAuth authentication using the MCP Dart SDK.

## Prerequisites

- Dart SDK installed
- A GitHub account
- MCP Dart SDK installed

## Step 1: Create a GitHub OAuth App

1. **Go to GitHub Developer Settings**
   - Visit: https://github.com/settings/developers
   - Click on "OAuth Apps" in the left sidebar

2. **Create New OAuth App**
   - Click "New OAuth App"
   - Fill in the details:
     - **Application name**: `MCP Dart Test` (or any name you prefer)
     - **Homepage URL**: `http://localhost:8080`
     - **Authorization callback URL**: `http://localhost:8080/callback`
     - **Application description**: (optional) `Testing MCP Dart SDK with GitHub`

3. **Get Credentials**
   - After creation, you'll see your **Client ID**
   - Click "Generate a new client secret" to get your **Client Secret**
   - **Important**: Copy both values immediately - you won't be able to see the secret again!

## Step 2: Set Environment Variables

### macOS/Linux
```bash
export GITHUB_CLIENT_ID="your_client_id_here"
export GITHUB_CLIENT_SECRET="your_client_secret_here"
```

### Windows (PowerShell)
```powershell
$env:GITHUB_CLIENT_ID="your_client_id_here"
$env:GITHUB_CLIENT_SECRET="your_client_secret_here"
```

### Windows (Command Prompt)
```cmd
set GITHUB_CLIENT_ID=your_client_id_here
set GITHUB_CLIENT_SECRET=your_client_secret_here
```

**Alternative**: Create a `.env` file in your project root:
```bash
GITHUB_CLIENT_ID=your_client_id_here
GITHUB_CLIENT_SECRET=your_client_secret_here
```

**Note**: Add `.env` to your `.gitignore` to prevent committing secrets!

## Step 3: Run the Example

```bash
cd /path/to/mcp_dart
dart run example/authentication/github_oauth_example.dart
```

## Step 4: Complete OAuth Flow

1. **Browser Opens Automatically**
   - The example will automatically open GitHub's authorization page in your browser
   - If it doesn't open automatically, copy the URL from the terminal

2. **Authorize the Application**
   - Review the requested permissions (scopes):
     - `repo` - Access to repositories
     - `read:packages` - Read packages
     - `read:org` - Read organization membership
   - Click "Authorize" to grant access

3. **Return to Terminal**
   - You'll be redirected to `http://localhost:8080/callback`
   - The browser will show a success message
   - The terminal will display connection status

4. **Tokens Are Saved**
   - OAuth tokens are saved to `.github_oauth_tokens.json`
   - Next time you run the example, it will use the saved tokens
   - No need to re-authorize unless tokens expire

## What You'll See

### First Run (No Tokens)

```text
GitHub MCP Server - OAuth Authentication Example
Connecting to GitHub MCP server...
No existing tokens found. Starting OAuth flow...

Please authorize this application in your browser:
https://github.com/login/oauth/authorize?client_id=...

✓ Authorization successful!
✓ Connected to GitHub MCP server!
  Server: github-mcp-server | Version: 1.0.0

✓ Found X tools: create_or_update_file, search_repositories, get_file_contents...
```

### Subsequent Runs (Tokens Exist)

```text
✓ Using existing tokens from storage
✓ Connected to GitHub MCP server!
```

## OAuth Scopes Explained

The example requests these GitHub OAuth scopes:

| Scope | Purpose |
|-------|---------|
| `repo` | Full control of private repositories |
| `read:packages` | Download packages from GitHub Package Registry |
| `read:org` | Read organization membership |

**Modify scopes**: Edit the `scopes` parameter in the code.
**More scopes**: See [GitHub OAuth Scopes](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/scopes-for-oauth-apps) documentation.

## Troubleshooting

### Port 8080 Already in Use

Change the callback port in the code:

```dart
final config = GitHubOAuthConfig(
  clientId: clientId,
  clientSecret: clientSecret,
  callbackPort: 3000, // Use different port
);
```

Also update your GitHub OAuth App callback URL to: `http://localhost:3000/callback`

### Browser Doesn't Open Automatically

Copy the authorization URL from the terminal and paste it into your browser manually.

### Invalid Client Error

Double-check your `GITHUB_CLIENT_ID` and `GITHUB_CLIENT_SECRET` environment variables for extra spaces or quotes.

### Callback URL Mismatch

**Error**: `redirect_uri_mismatch`

**Solution**: Go to your GitHub OAuth App settings and ensure callback URL is exactly: `http://localhost:8080/callback` (no trailing slashes)

### Token Already Exists

To re-authorize, delete the token file: `rm .github_oauth_tokens.json`

### Connection Refused

Verify internet connectivity to:
- `https://github.com` (for authorization)
- `https://api.githubcopilot.com` (for MCP server)

## Security Notes

### ⚠️ Critical

- **Never commit** `.github_oauth_tokens.json` or Client Secret to version control
- **Add to .gitignore**: `.env`, `*.tokens.json`, `*.secret`, `*.key`
- **Rotate secrets** if accidentally exposed
- **Use minimal scopes** - only request what you need

### Production Token Storage

The example stores tokens in `.github_oauth_tokens.json` for convenience. In production:
- Use secure storage (system keychain, encrypted database)
- Encrypt tokens at rest
- Implement token rotation and expiration monitoring

See [OAUTH_SERVER_GUIDE.md](OAUTH_SERVER_GUIDE.md#security-considerations) for detailed security practices.

## Next Steps

### Using the GitHub MCP Client

Once connected, you can use the GitHub MCP server:

```dart
// Search for repositories
final searchResult = await client.callTool(
  CallToolRequest(
    name: 'search_repositories',
    arguments: {'query': 'mcp server'},
  ),
);

// Get file contents
final fileResult = await client.callTool(
  CallToolRequest(
    name: 'get_file_contents',
    arguments: {
      'owner': 'github',
      'repo': 'github-mcp-server',
      'path': 'README.md',
    },
  ),
);

// Create or update file
final updateResult = await client.callTool(
  CallToolRequest(
    name: 'create_or_update_file',
    arguments: {
      'owner': 'your-username',
      'repo': 'your-repo',
      'path': 'hello.txt',
      'content': 'Hello from MCP Dart!',
      'message': 'Add hello.txt via MCP',
    },
  ),
);
```

### Extending the Example

You can extend the example to:
- Add token refresh logic
- Implement token expiration tracking
- Add more error handling
- Create a CLI tool for GitHub operations
- Build a GitHub automation bot

## Resources

- [GitHub MCP Server Repo](https://github.com/github/github-mcp-server)
- [GitHub OAuth Documentation](https://docs.github.com/en/apps/oauth-apps)
- [MCP Specification](https://modelcontextprotocol.io/specification)
- [MCP Dart SDK](https://pub.dev/packages/mcp_dart)

## Support

If you encounter issues:
1. Check the [GitHub MCP Server Issues](https://github.com/github/github-mcp-server/issues)
2. Review [MCP Dart SDK Examples](../README.md)
3. Open an issue with detailed error messages and steps to reproduce
