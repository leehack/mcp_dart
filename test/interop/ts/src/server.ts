import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import type { StreamableHTTPServerTransportOptions } from '@modelcontextprotocol/sdk/server/streamableHttp.js';
import { StreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/streamableHttp.js';
import { CompleteRequestSchema } from '@modelcontextprotocol/sdk/types.js';
import { z } from 'zod';
import express from 'express';
import { randomUUID } from 'node:crypto'; // Correct import for UUID generation
import { InMemoryTaskStore } from '@modelcontextprotocol/sdk/experimental/tasks/stores/in-memory.js';

// Minimal EventStore interface and InMemoryEventStore implementation for testing
interface EventStore {
  storeEvent(sessionId: string, event: any): Promise<string>; // Returns event ID
  replayEventsAfter(
    lastEventId: string,
    options: { send: (eventId: string, message: any) => Promise<void> }
  ): Promise<string>; // Mock replay
  clearEvents(sessionId: string): Promise<void>;
}

class InMemoryEventStore implements EventStore {
  private sessions = new Map<string, any[]>();

  async storeEvent(sessionId: string, event: any): Promise<string> {
    if (!this.sessions.has(sessionId)) {
      this.sessions.set(sessionId, []);
    }
    const events = this.sessions.get(sessionId)!;
    const eventId = `event-${events.length + 1}`;
    events.push({ ...event, id: eventId });
    return eventId;
  }

  // Minimal mock for replayEventsAfter for testing purposes
  async replayEventsAfter(
    lastEventId: string,
    {
      send: _send,
    }: { send: (eventId: string, message: unknown) => Promise<void> }
  ): Promise<string> {
    // In a real implementation, this would iterate through stored events after lastEventId
    // and call `send` for each event.
    // For this test fixture, we'll just acknowledge the call and return the lastEventId.
    return lastEventId;
  }

  async clearEvents(sessionId: string): Promise<void> {
    this.sessions.delete(sessionId);
  }
}

function createInteropServer(): McpServer {
  const taskStore = new InMemoryTaskStore();

  const server = new McpServer(
    {
      name: 'ts-interop-server',
      version: '1.0.0',
    },
    {
      taskStore,
      capabilities: {
        completions: {},
        tasks: {
          requests: {
            tools: { call: {} },
          },
        },
      },
    }
  );

  server.registerTool(
    'echo',
    {
      inputSchema: { message: z.string() },
    },
    async ({ message }) => {
      return {
        content: [{ type: 'text', text: message }],
      };
    }
  );

  server.registerTool(
    'add',
    {
      inputSchema: { a: z.number(), b: z.number() },
    },
    async ({ a, b }) => {
      return {
        content: [{ type: 'text', text: String(a + b) }],
      };
    }
  );

  server.registerResource(
    'test-resource',
    'resource://test',
    {},
    async (uri) => {
      return {
        contents: [
          {
            uri: uri.href,
            text: 'This is a test resource',
            mimeType: 'text/plain',
          },
        ],
      };
    }
  );

  server.registerPrompt(
    'test_prompt',
    {
      argsSchema: {},
    },
    async () => {
      return {
        messages: [
          {
            role: 'user',
            content: { type: 'text', text: 'Test Prompt' },
          },
        ],
      };
    }
  );

  server.registerPrompt(
    'greeting',
    {
      description: 'A greeting prompt with a completable language argument',
      argsSchema: {
        language: z.string().describe('The language for the greeting'),
      },
    },
    async ({ language }) => {
      const greetings: Record<string, string> = {
        English: 'Hello!',
        Spanish: '¡Hola!',
        French: 'Bonjour!',
        German: 'Guten Tag!',
      };
      return {
        messages: [
          {
            role: 'user',
            content: {
              type: 'text',
              text: greetings[language] || `Hello in ${language}!`,
            },
          },
        ],
      };
    }
  );

  server.server.setRequestHandler(CompleteRequestSchema, async (request) => {
    const { ref, argument } = request.params;

    if (
      ref.type === 'ref/prompt' &&
      ref.name === 'greeting' &&
      argument.name === 'language'
    ) {
      const languages = ['English', 'Spanish', 'French', 'German'];
      const filtered = languages.filter((l) =>
        l.toLowerCase().startsWith(argument.value.toLowerCase())
      );
      return {
        completion: {
          values: filtered,
          hasMore: false,
        },
      };
    }

    return {
      completion: {
        values: [],
        hasMore: false,
      },
    };
  });

  server.registerTool(
    'get_roots',
    {
      description: 'Lists the roots provided by the client',
      inputSchema: {},
    },
    async () => {
      try {
        const result = await server.server.listRoots();
        return {
          content: [{ type: 'text', text: JSON.stringify(result.roots) }],
        };
      } catch (error) {
        return {
          content: [{ type: 'text', text: `Error getting roots: ${error}` }],
          isError: true,
        };
      }
    }
  );

  server.registerTool(
    'elicit_input',
    {
      description: 'Requests structured input from the client',
      inputSchema: {
        message: z.string().describe('The message to show the user'),
      },
    },
    async ({ message }) => {
      try {
        const result = await server.server.elicitInput({
          message,
          requestedSchema: {
            type: 'object',
            properties: {
              confirmed: { type: 'boolean', description: 'User confirmation' },
            },
            required: ['confirmed'],
          },
        });
        return {
          content: [{ type: 'text', text: JSON.stringify(result) }],
        };
      } catch (error) {
        return {
          content: [{ type: 'text', text: `Error eliciting input: ${error}` }],
          isError: true,
        };
      }
    }
  );

  server.registerTool(
    'sample_llm',
    {
      description: 'Requests an LLM completion from the client',
      inputSchema: {
        prompt: z.string().describe('The prompt to send to the LLM'),
      },
    },
    async ({ prompt }) => {
      try {
        const result = await server.server.createMessage({
          messages: [
            {
              role: 'user',
              content: { type: 'text', text: prompt },
            },
          ],
          maxTokens: 100,
        });
        const content = result.content;
        const text =
          content.type === 'text' ? content.text : JSON.stringify(content);
        return {
          content: [{ type: 'text', text }],
        };
      } catch (error) {
        return {
          content: [{ type: 'text', text: `Error sampling LLM: ${error}` }],
          isError: true,
        };
      }
    }
  );

  server.registerTool(
    'progress_demo',
    {
      description: 'Demonstrates progress notifications',
      inputSchema: {
        steps: z
          .number()
          .optional()
          .describe('Number of progress steps (default 4)'),
      },
    },
    async ({ steps = 4 }, extra) => {
      const totalSteps = Math.max(1, Math.min(steps, 10));
      const progressToken = extra._meta?.progressToken;

      for (let i = 0; i <= totalSteps; i++) {
        const progress = Math.round((i / totalSteps) * 100);

        if (progressToken !== undefined) {
          await server.server.notification({
            method: 'notifications/progress',
            params: {
              progressToken,
              progress,
              total: 100,
            },
          });
        }

        await new Promise((resolve) => setTimeout(resolve, 50));
      }

      return {
        content: [
          {
            type: 'text',
            text: `Completed ${totalSteps} steps with progress notifications`,
          },
        ],
      };
    }
  );

  server.experimental.tasks.registerToolTask(
    'long_running',
    {
      description: 'A task-enabled tool that simulates long-running work',
      inputSchema: { duration: z.number().optional() },
      execution: { taskSupport: 'required' },
    },
    {
      createTask: async ({ duration }, extra) => {
        const task = await extra.taskStore.createTask({
          ttl: 60000,
          pollInterval: 100,
        });

        const workDuration = duration ?? 100;
        setTimeout(async () => {
          await extra.taskStore.updateTaskStatus(
            task.taskId,
            'working',
            'Processing...'
          );
          setTimeout(async () => {
            await extra.taskStore.storeTaskResult(task.taskId, 'completed', {
              content: [
                { type: 'text', text: `Completed after ${workDuration}ms` },
              ],
            });
          }, workDuration / 2);
        }, workDuration / 2);

        return { task };
      },
      getTask: async (_args, extra) => {
        const task = await extra.taskStore.getTask(extra.taskId);
        return task;
      },
      getTaskResult: async (_args, extra) => {
        const result = await extra.taskStore.getTaskResult(extra.taskId);
        return result as { content: Array<{ type: 'text'; text: string }> };
      },
    }
  );

  return server;
}

async function main() {
  let transportName = 'stdio';
  let port = 3000;

  const args = process.argv.slice(2);
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--transport' && args[i + 1]) {
      transportName = args[i + 1];
      i++;
    } else if (args[i] === '--port' && args[i + 1]) {
      port = parseInt(args[i + 1], 10);
      i++;
    }
  }

  if (transportName === 'stdio') {
    const server = createInteropServer();
    const transport = new StdioServerTransport();
    await server.connect(transport);
    return;
  }

  if (transportName === 'http') {
    const app = express();
    const transports = new Map<string, StreamableHTTPServerTransport>();
    const servers = new Map<string, McpServer>();
    const eventStore = new InMemoryEventStore();

    const getHeaderValue = (
      value: string | string[] | undefined
    ): string | undefined => {
      if (typeof value === 'string' && value.length > 0) {
        return value;
      }
      if (Array.isArray(value) && value.length > 0) {
        return value[0];
      }
      return undefined;
    };

    const getSessionIdFromRequest = (
      req: express.Request
    ): string | undefined => {
      const headerSessionId = getHeaderValue(req.headers['mcp-session-id']);
      if (headerSessionId !== undefined) {
        return headerSessionId;
      }

      const legacyHeaderSessionId = getHeaderValue(
        req.headers['x-mcp-session-id']
      );
      if (legacyHeaderSessionId !== undefined) {
        return legacyHeaderSessionId;
      }

      const querySessionId = req.query.sessionId;
      if (typeof querySessionId === 'string' && querySessionId.length > 0) {
        return querySessionId;
      }

      return undefined;
    };

    const cleanupSession = (sessionId: string): void => {
      transports.delete(sessionId);
      const sessionServer = servers.get(sessionId);
      if (sessionServer !== undefined) {
        void sessionServer.close().catch((error) => {
          console.error(
            `[TS Server] Failed to close session server for ${sessionId}:`,
            error
          );
        });
        servers.delete(sessionId);
      }
    };

    app.get('/mcp', async (req, res) => {
      const sessionId = getSessionIdFromRequest(req);
      if (sessionId === undefined || !transports.has(sessionId)) {
        res.status(400).send('Invalid or missing session ID');
        return;
      }

      const transport = transports.get(sessionId)!;
      await transport.handleRequest(req, res);
    });

    app.get('/mcp/sse', async (req, res) => {
      const sessionId = getSessionIdFromRequest(req);
      if (sessionId === undefined || !transports.has(sessionId)) {
        res.status(400).send('Invalid or missing session ID');
        return;
      }

      const transport = transports.get(sessionId)!;
      await transport.handleRequest(req, res);
    });

    app.post('/mcp', async (req, res) => {
      const sessionId = getSessionIdFromRequest(req);

      if (sessionId !== undefined) {
        const transport = transports.get(sessionId);
        if (transport === undefined) {
          console.error(
            `[TS Server] Session not found for ID: ${sessionId}. Available: ${Array.from(transports.keys())}`
          );
          res.status(404).send('Session not found');
          return;
        }

        console.log(
          `[TS Server] POST /mcp received. Session ID: ${sessionId}. Req Body:`,
          req.body
        );
        await transport.handleRequest(req, res);
        return;
      }

      console.log(
        '[TS Server] Initial POST request without known session ID. Creating new session.'
      );

      const server = createInteropServer();
      let createdSessionId: string | undefined;
      const transport = new StreamableHTTPServerTransport({
        eventStore,
        sessionIdGenerator: () => randomUUID(),
        onsessioninitialized: (sid) => {
          createdSessionId = sid;
          transports.set(sid, transport);
          servers.set(sid, server);
          console.log(
            `[TS Server] New POST connection. Session ID: ${sid}. Total active sessions: ${transports.size}`
          );
        },
      } satisfies StreamableHTTPServerTransportOptions);

      transport.onclose = () => {
        const sid = transport.sessionId ?? createdSessionId;
        if (sid !== undefined) {
          cleanupSession(sid);
          console.log(
            `[TS Server] Transport closed: ${sid}. Remaining sessions: ${transports.size}`
          );
        }
      };

      await server.connect(transport);
      await transport.handleRequest(req, res);

      if (createdSessionId === undefined) {
        await server.close();
      }
    });

    app.delete('/mcp', async (req, res) => {
      const sessionId = getSessionIdFromRequest(req);
      if (sessionId === undefined || !transports.has(sessionId)) {
        res.status(400).send('Invalid or missing session ID');
        return;
      }

      const transport = transports.get(sessionId)!;
      await transport.handleRequest(req, res);
    });

    app.listen(port, () => {
      console.log(`TS McpServer running on port ${port} with /mcp base path`);
    });
  }
}

main().catch(console.error);
