# GitHub OAuth example setup

This guide configures [`github_oauth_example.dart`](github_oauth_example.dart)
for local testing.

> [!WARNING]
> The example stores tokens in plaintext at `.github_oauth_tokens.json`. Keep
> that file out of version control and replace the storage implementation in a
> real application.

## 1. Create an OAuth app

Open <https://github.com/settings/developers>, create an OAuth app, and use:

- Homepage URL: `http://localhost:8080`
- Authorization callback URL: `http://localhost:8080/callback`

Copy the client ID and newly generated client secret. Treat the secret like a
password.

## 2. Export credentials

The example reads the process environment directly; it does not load `.env`
files.

macOS or Linux:

```bash
export GITHUB_CLIENT_ID=your_client_id
export GITHUB_CLIENT_SECRET=your_client_secret
```

PowerShell:

```powershell
$env:GITHUB_CLIENT_ID="your_client_id"
$env:GITHUB_CLIENT_SECRET="your_client_secret"
```

Command Prompt:

```cmd
set GITHUB_CLIENT_ID=your_client_id
set GITHUB_CLIENT_SECRET=your_client_secret
```

## 3. Run

From the repository root:

```bash
dart run example/authentication/github_oauth_example.dart
```

On first use, the example:

1. Starts a callback listener on `localhost:8080`.
2. Opens the GitHub authorization page, or prints its URL if that fails.
3. Validates the callback state and exchanges the authorization code with PKCE
   S256.
4. Saves the token without printing it.
5. Connects to the configured MCP endpoint and lists its tools.

Later runs reuse the local token file. Delete `.github_oauth_tokens.json` to
authorize again.

## Scopes

The checked-in configuration requests `repo`, `read:packages`, and `read:org`
to demonstrate a broad tool surface. Narrow that list for your application.
Scopes grant access to the user's GitHub data; they are not harmless example
flags.

## Troubleshooting

### Callback mismatch

The OAuth app callback and `GitHubOAuthConfig.callbackPort` must describe the
same exact URI. The default is `http://localhost:8080/callback`.

### Port already in use

Change `callbackPort` in the example and update the OAuth app callback to match.

### Browser does not open

Copy the printed authorization URL into a browser. The localhost callback
listener still completes the flow.

### Stored token no longer works

Delete `.github_oauth_tokens.json` and authorize again. Confirm that the app
still has the required scopes and has not been revoked.

### Connection fails after authorization

Authorization success proves only that a token was issued. The configured MCP
endpoint can still reject its audience, scopes, account policy, or transport
requirements. Inspect the returned error instead of exposing the token.

## Security reminders

- Never commit client secrets or token files.
- Never print or paste access tokens into issue reports.
- Prefer secure OS-backed storage and minimal scopes.
- Rotate credentials immediately if they are exposed.
