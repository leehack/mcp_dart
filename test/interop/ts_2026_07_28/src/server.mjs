import { createServer } from 'node:http';

import {
  acceptedContent,
  createMcpHandler,
  inputRequired,
  McpServer,
} from '@modelcontextprotocol/server';
import { z } from 'zod';

const PROTOCOL_VERSION = '2026-07-28';
let streamCancellationCount = 0;

function readArg(args, name) {
  const index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) {
    return undefined;
  }
  return args[index + 1];
}

function createInteropServer() {
  const serverInfo = { name: 'ts-2026-07-28-interop-server', version: '0.0.0' };
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
      description: 'Echoes a message from the Dart 2026-07-28 client.',
      inputSchema: z.object({ message: z.string() }),
    },
    async ({ message }) => ({
      content: [{ type: 'text', text: message }],
    }),
  );

  server.registerTool(
    'ts_stream_cancellation',
    {
      description:
        'Keeps a streamed response open until the Dart client aborts it.',
      inputSchema: z.object({}),
    },
    async (_args, ctx) => {
      const progressToken = ctx.mcpReq._meta?.progressToken;
      if (progressToken === undefined) {
        throw new Error('ts_stream_cancellation requires a progress token');
      }
      await ctx.mcpReq.notify({
        method: 'notifications/progress',
        params: {
          progressToken,
          progress: 1,
          total: 1,
          message: 'TypeScript cancellation probe started',
        },
      });

      await new Promise((resolve) => {
        if (ctx.mcpReq.signal.aborted) {
          resolve();
          return;
        }
        ctx.mcpReq.signal.addEventListener('abort', resolve, { once: true });
      });
      streamCancellationCount += 1;
      return {
        content: [{ type: 'text', text: 'cancelled' }],
      };
    },
  );

  server.registerTool(
    'ts_stream_cancellation_status',
    {
      description: 'Reports response-stream cancellations observed by TS.',
      inputSchema: z.object({}),
    },
    async () => ({
      content: [{ type: 'text', text: String(streamCancellationCount) }],
    }),
  );

  server.registerTool(
    'ts_header_routed',
    {
      description:
        'Requires the Dart client to mirror an argument into an HTTP header.',
      inputSchema: z.object({
        region: z.string().meta({ 'x-mcp-header': 'Region' }),
      }),
    },
    async ({ region }) => ({
      content: [{ type: 'text', text: region }],
    }),
  );

  server.registerTool(
    'ts_input_required_elicitation',
    {
      description: 'Exercises a TypeScript server input_required elicitation retry.',
      inputSchema: z.object({}),
    },
    async (_args, ctx) => {
      const content = acceptedContent(ctx.mcpReq.inputResponses, 'user_name');
      const name = content?.name;
      if (typeof name === 'string') {
        return {
          content: [{ type: 'text', text: `Hello, ${name}!` }],
        };
      }

      return inputRequired({
        inputRequests: {
          user_name: inputRequired.elicit({
            message: 'What should the TypeScript fixture call you?',
            requestedSchema: {
              type: 'object',
              properties: { name: { type: 'string' } },
              required: ['name'],
            },
          }),
        },
      });
    },
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
  const handler = createMcpHandler(() => createInteropServer(), {
    legacy: 'reject',
  });

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
      const requestAbort = new AbortController();
      const abortRequest = () => requestAbort.abort();
      req.once('aborted', abortRequest);
      res.once('close', () => {
        if (!res.writableEnded) {
          abortRequest();
        }
      });
      init.signal = requestAbort.signal;
      let body;
      if (req.method !== 'GET' && req.method !== 'HEAD') {
        body = await readBody(req);
        init.body = body;
      }

      const webRequest = new Request(url, init);
      const webResponse = await handler.fetch(webRequest);
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
    `TS 2026-07-28 interop server listening on http://${host}:${boundPort}/mcp`,
  );

  const stop = async () => {
    await handler.close().catch(() => {});
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
