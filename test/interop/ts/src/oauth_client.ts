import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import type { OAuthClientProvider } from '@modelcontextprotocol/sdk/client/auth.js';
import { UnauthorizedError } from '@modelcontextprotocol/sdk/client/auth.js';
import { StreamableHTTPClientTransport } from '@modelcontextprotocol/sdk/client/streamableHttp.js';
import type {
  OAuthClientInformation,
  OAuthClientMetadata,
  OAuthTokens,
} from '@modelcontextprotocol/sdk/shared/auth.js';

function getArg(name: string): string {
  const index = process.argv.indexOf(name);
  if (index >= 0 && index + 1 < process.argv.length) {
    return process.argv[index + 1];
  }
  throw new Error(`Missing required argument: ${name}`);
}

function hasFlag(name: string): boolean {
  return process.argv.includes(name);
}

class TestOAuthProvider implements OAuthClientProvider {
  private _tokens?: OAuthTokens;
  private _codeVerifier?: string;
  private _authorizationUrl?: URL;

  get redirectUrl(): string {
    return 'http://127.0.0.1:9876/oauth/callback';
  }

  get clientMetadata(): OAuthClientMetadata {
    return {
      client_name: 'mcp_dart TS OAuth interop client',
      redirect_uris: [this.redirectUrl],
      grant_types: ['authorization_code'],
      response_types: ['code'],
      token_endpoint_auth_method: 'none',
      scope: 'tools:read',
    };
  }

  state(): string {
    return 'ts-oauth-state';
  }

  clientInformation(): OAuthClientInformation {
    return {
      client_id: 'ts-oauth-client',
    };
  }

  tokens(): OAuthTokens | undefined {
    return this._tokens;
  }

  saveTokens(tokens: OAuthTokens): void {
    this._tokens = tokens;
  }

  redirectToAuthorization(authorizationUrl: URL): void {
    this._authorizationUrl = authorizationUrl;
  }

  saveCodeVerifier(codeVerifier: string): void {
    this._codeVerifier = codeVerifier;
  }

  codeVerifier(): string {
    if (!this._codeVerifier) {
      throw new Error('PKCE code verifier was not saved');
    }
    return this._codeVerifier;
  }

  assertAuthorizationRedirect(
    expectedResource: string,
    expectedScope = 'tools:read'
  ): void {
    if (!this._authorizationUrl) {
      throw new Error('Authorization redirect was not requested');
    }

    const params = this._authorizationUrl.searchParams;
    const codeChallenge = params.get('code_challenge');
    if (!codeChallenge) {
      throw new Error('Missing code_challenge');
    }
    if (params.get('response_type') !== 'code') {
      throw new Error(
        `Unexpected response_type: ${params.get('response_type')}`
      );
    }
    if (params.get('client_id') !== 'ts-oauth-client') {
      throw new Error(`Unexpected client_id: ${params.get('client_id')}`);
    }
    if (params.get('redirect_uri') !== this.redirectUrl) {
      throw new Error(`Unexpected redirect_uri: ${params.get('redirect_uri')}`);
    }
    if (params.get('code_challenge_method') !== 'S256') {
      throw new Error(
        `Unexpected code_challenge_method: ${params.get('code_challenge_method')}`
      );
    }
    if (params.get('resource') !== expectedResource) {
      throw new Error(`Unexpected resource: ${params.get('resource')}`);
    }
    if (params.get('scope') !== expectedScope) {
      throw new Error(`Unexpected scope: ${params.get('scope')}`);
    }
    if (params.get('state') !== 'ts-oauth-state') {
      throw new Error(`Unexpected state: ${params.get('state')}`);
    }
  }
}

async function connectAndListTools(
  url: string,
  provider: TestOAuthProvider
): Promise<string[]> {
  const transport = new StreamableHTTPClientTransport(new URL(url), {
    authProvider: provider,
  });
  const client = new Client(
    {
      name: 'ts-oauth-client',
      version: '1.0.0',
    },
    {
      capabilities: {},
    }
  );

  let connected = false;
  try {
    await client.connect(transport);
    connected = true;
    const result = await client.listTools();
    return result.tools.map((tool) => tool.name);
  } finally {
    if (connected) {
      await client.close();
    } else {
      await transport.close();
    }
  }
}

async function expectAuthorizationRequired(
  operation: () => Promise<unknown>,
  label: string
): Promise<void> {
  try {
    await operation();
  } catch (error) {
    if (error instanceof UnauthorizedError) {
      return;
    }
    throw error;
  }
  throw new Error(`${label} unexpectedly succeeded`);
}

async function finishAuthorization(
  url: string,
  provider: TestOAuthProvider,
  code: string
): Promise<void> {
  const authTransport = new StreamableHTTPClientTransport(new URL(url), {
    authProvider: provider,
  });
  await authTransport.start();
  try {
    await authTransport.finishAuth(code);
  } finally {
    await authTransport.close();
  }
}

async function main(): Promise<void> {
  const url = getArg('--url');
  const expectUpscope = hasFlag('--expect-upscope');
  const provider = new TestOAuthProvider();

  await expectAuthorizationRequired(
    () => connectAndListTools(url, provider),
    'Initial protected request'
  );

  provider.assertAuthorizationRedirect(url, 'tools:read');

  await finishAuthorization(url, provider, 'valid-code');

  if (expectUpscope) {
    await expectAuthorizationRequired(
      () => connectAndListTools(url, provider),
      'Insufficient-scope protected request'
    );
    provider.assertAuthorizationRedirect(url, 'tools:write');
    await finishAuthorization(url, provider, 'upscope-code');
  }

  const toolNames = await connectAndListTools(url, provider);
  if (!toolNames.includes('echo') || !toolNames.includes('add')) {
    throw new Error(`Missing expected tools. Found: ${toolNames.join(',')}`);
  }

  console.log('TS OAuth interop passed');
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
