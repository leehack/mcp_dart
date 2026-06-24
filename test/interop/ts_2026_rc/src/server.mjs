import { createServer } from 'node:http';

import {
  McpServer,
  WebStandardStreamableHTTPServerTransport,
} from '@modelcontextprotocol/server';
import { z } from 'zod';

const PROTOCOL_VERSION = '2026-07-28';

function readArg(args, name) {
  const index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) {
    return undefined;
  }
  return args[index + 1];
}

function createInteropServer() {
  const serverInfo = { name: 'ts-2026-rc-interop-server', version: '0.0.0' };
  const server = new McpServer(
    serverInfo,
    {
      supportedProtocolVersions: [PROTOCOL_VERSION],
      capabilities: { tools: {} },
    },
  );

  server.registerTool(
    'ts_echo',
    {
      description: 'Echoes a message from the Dart 2026 RC client.',
      inputSchema: z.object({ message: z.string() }),
    },
    async ({ message }) => ({
      content: [{ type: 'text', text: message }],
    }),
  );

  return server;
}

async function readBody(req) {
  const chunks = [];
  for await (const chunk of req) {
    chunks.push(Buffer.from(chunk));
  }
  return Buffer.concat(chunks);
}

function requestHeaders(req) {
  const headers = new Headers();
  for (const [name, value] of Object.entries(req.headers)) {
    if (Array.isArray(value)) {
      for (const item of value) {
        headers.append(name, item);
      }
    } else if (value !== undefined) {
      headers.set(name, value);
    }
  }
  return headers;
}

function discoveryResponse(id) {
  // Keep discovery local to the diagnostic fixture while the TypeScript preview
  // server path remains behind the draft-shaped stateless result behavior.
  return new Response(
    JSON.stringify({
      jsonrpc: '2.0',
      id,
      result: {
        resultType: 'complete',
        supportedVersions: [PROTOCOL_VERSION],
        capabilities: { tools: {} },
        serverInfo: {
          name: 'ts-2026-rc-interop-server',
          version: '0.0.0',
        },
        ttlMs: 1000,
        cacheScope: 'public',
      },
    }),
    {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    },
  );
}

async function writeWebResponse(webResponse, res) {
  res.writeHead(
    webResponse.status,
    Object.fromEntries(webResponse.headers.entries()),
  );
  if (!webResponse.body) {
    res.end();
    return;
  }

  const reader = webResponse.body.getReader();
  try {
    for (;;) {
      const { value, done } = await reader.read();
      if (done) {
        break;
      }
      res.write(Buffer.from(value));
    }
  } finally {
    res.end();
  }
}

async function main() {
  const args = process.argv.slice(2);
  const host = readArg(args, '--host') ?? '127.0.0.1';
  const port = Number.parseInt(readArg(args, '--port') ?? '0', 10);
  const mcpServer = createInteropServer();
  const transport = new WebStandardStreamableHTTPServerTransport({
    sessionIdGenerator: undefined,
    enableJsonResponse: false,
    supportedProtocolVersions: [PROTOCOL_VERSION],
  });
  await mcpServer.connect(transport);

  const httpServer = createServer(async (req, res) => {
    try {
      const url = new URL(req.url ?? '/', `http://${req.headers.host}`);
      if (url.pathname !== '/mcp') {
        res.writeHead(404).end('Not found');
        return;
      }

      const init = {
        method: req.method,
        headers: requestHeaders(req),
      };
      let body;
      if (req.method !== 'GET' && req.method !== 'HEAD') {
        body = await readBody(req);
        init.body = body;
      }

      const webRequest = new Request(url, init);
      if (body && body.length > 0) {
        const message = JSON.parse(body.toString('utf8'));
        if (message.method === 'server/discover') {
          await writeWebResponse(discoveryResponse(message.id), res);
          return;
        }
      }

      const webResponse = await transport.handleRequest(webRequest);
      await writeWebResponse(webResponse, res);
    } catch (error) {
      console.error(error);
      if (!res.headersSent) {
        res.writeHead(500);
      }
      res.end(String(error));
    }
  });

  await new Promise((resolve) => httpServer.listen(port, host, resolve));
  const address = httpServer.address();
  const boundPort = typeof address === 'object' && address ? address.port : port;
  console.log(
    `TS 2026 RC interop server listening on http://${host}:${boundPort}/mcp`,
  );

  const stop = async () => {
    await mcpServer.close().catch(() => {});
    await new Promise((resolve) => httpServer.close(resolve));
  };
  process.once('SIGTERM', () => {
    stop().finally(() => process.exit(0));
  });
  process.once('SIGINT', () => {
    stop().finally(() => process.exit(0));
  });
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
