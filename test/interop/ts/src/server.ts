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

  // Task Store for task-enabled tools (placed early so it can be used in McpServer options)
  const taskStore = new InMemoryTaskStore();

  // 1. Create Server with task support
  const server = new McpServer({
    name: 'ts-interop-server',
    version: '1.0.0',
  }, {
    taskStore,
    capabilities: {
      completions: {},
      tasks: {
        requests: {
          tools: { call: {} },
        },
      },
    },
  });

  // 2. Register Features

  // Tool: echo
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

  // Tool: add
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

  // Resource: resource://test
  server.registerResource(
    'test-resource',
    'resource://test',
    {}, // No metadata
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

  // Prompt: test_prompt
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

  // Prompt: greeting - with completable language argument
  server.registerPrompt(
    'greeting',
    {
      description: 'A greeting prompt with a completable language argument',
      argsSchema: { language: z.string().describe('The language for the greeting') },
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
            content: { type: 'text', text: greetings[language] || `Hello in ${language}!` },
          },
        ],
      };
    }
  );

  // Completion handler for prompt arguments
  server.server.setRequestHandler(CompleteRequestSchema, async (request) => {
    const { ref, argument } = request.params;

    if (ref.type === 'ref/prompt' && ref.name === 'greeting' && argument.name === 'language') {
      const languages = ['English', 'Spanish', 'French', 'German'];
      const filtered = languages.filter((l) => l.toLowerCase().startsWith(argument.value.toLowerCase()));
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

  // Tool: get_roots - Lists client's roots
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

  // Tool: elicit_input - Requests user input from client
  server.registerTool(
    'elicit_input',
    {
      description: 'Requests structured input from the client',
      inputSchema: { message: z.string().describe('The message to show the user') },
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

  // Tool: sample_llm - Requests LLM completion from client
  server.registerTool(
    'sample_llm',
    {
      description: 'Requests an LLM completion from the client',
      inputSchema: { prompt: z.string().describe('The prompt to send to the LLM') },
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
        const text = content.type === 'text' ? content.text : JSON.stringify(content);
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

  // Tool: progress_demo - Sends progress notifications during execution
  server.registerTool(
    'progress_demo',
    {
      description: 'Demonstrates progress notifications',
      inputSchema: { steps: z.number().optional().describe('Number of progress steps (default 4)') },
    },
    async ({ steps = 4 }, extra) => {
      const totalSteps = Math.max(1, Math.min(steps, 10));
      const progressToken = extra._meta?.progressToken;

      for (let i = 0; i <= totalSteps; i++) {
        const progress = Math.round((i / totalSteps) * 100);

        // Send progress notification if we have a progress token
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

        // Simulate work
        await new Promise((resolve) => setTimeout(resolve, 50));
      }

      return {
        content: [{ type: 'text', text: `Completed ${totalSteps} steps with progress notifications` }],
      };
    }
  );

  // Tool: long_running (task-enabled)
  server.experimental.tasks.registerToolTask(
    'long_running',
    {
      description: 'A task-enabled tool that simulates long-running work',
      inputSchema: { duration: z.number().optional() },
      execution: { taskSupport: 'required' },
    },
    {
      createTask: async ({ duration }, extra) => {
        const task = await extra.taskStore.createTask(
          { ttl: 60000, pollInterval: 100 }
        );

        // Simulate background work
        const workDuration = duration ?? 100;
        setTimeout(async () => {
          await extra.taskStore.updateTaskStatus(task.taskId, 'working', 'Processing...');
          setTimeout(async () => {
            await extra.taskStore.storeTaskResult(task.taskId, 'completed', {
              content: [{ type: 'text', text: `Completed after ${workDuration}ms` }],
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
        // Cast to CallToolResult since we always store that shape
        return result as { content: Array<{ type: 'text'; text: string }>; };
      },
    }
  );

  // 3. Connect Transport
  if (transportName === 'stdio') {
    const transport = new StdioServerTransport();
    await server.connect(transport);
    // Keep process alive
  } else if (transportName === 'http') {
    const app = express();
    // app.use(express.json()); // Removed: StreamableHTTPServerTransport expects raw body

    const transports = new Map<string, StreamableHTTPServerTransport>();
    const eventStore = new InMemoryEventStore();

    // GET /mcp/sse for establishing the SSE connection
    app.get('/mcp/sse', async (req, res) => {
      // const newSessionId = (req.query.sessionId as string) || randomUUID(); // Let transport generate its own ID
      const options: StreamableHTTPServerTransportOptions = {
        eventStore,
      };
      const transport = new StreamableHTTPServerTransport(options);

      await server.connect(transport); // Connect the MCP server to this new transport

      const sessionId = transport.sessionId; // Get the generated session ID
      if (!sessionId) {
        console.error(
          '[TS Server] SSE Transport failed to generate session ID'
        );
        res.status(500).send('Server error: Could not establish session');
        return;
      }
      transports.set(sessionId, transport);
      console.log(
        `[TS Server] New SSE connection. Session ID: ${sessionId}. Total active sessions: ${transports.size}`
      );

      // Pass the request and response to the transport for message handling
      transport.handleRequest(req, res);

      transport.onclose = () => {
        console.log(
          `[TS Server] Transport closed: ${sessionId}. Remaining sessions: ${transports.size}`
        );
        transports.delete(sessionId);
      };
    });

    // POST /mcp for sending JSON-RPC messages
    app.post('/mcp', async (req, res) => {
      let sessionId =
        (req.query.sessionId as string) ||
        (req.headers['x-mcp-session-id'] as string);
      let transport: StreamableHTTPServerTransport | undefined;

      if (!sessionId || !transports.has(sessionId)) {
        // Treat as an initial connection for a new session if no session ID or not found
        console.log(
          '[TS Server] Initial POST request without known session ID. Creating new session.'
        );
        sessionId = randomUUID(); // Explicitly generate a UUID for this initial POST
        const options: StreamableHTTPServerTransportOptions = {
          eventStore,
        };
        const newTransport = new StreamableHTTPServerTransport(options);

        await server.connect(newTransport); // Connect the MCP server to this new transport

        // The newTransport.sessionId may not be available immediately, so we use our generated ID
        transports.set(sessionId, newTransport);
        transport = newTransport;

        console.log(
          `[TS Server] New POST connection. Session ID: ${sessionId}. Total active sessions: ${transports.size}`
        );

        // Set the session ID in the response header for the client
        res.setHeader('x-mcp-session-id', sessionId);

        newTransport.onclose = () => {
          console.log(
            `[TS Server] Transport closed: ${sessionId}. Remaining sessions: ${transports.size}`
          );
          transports.delete(sessionId);
        };
      } else {
        // Session ID is present and transport exists
        transport = transports.get(sessionId);
      }

      if (!transport) {
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
      // Pass the request and response to the transport for message handling
      transport.handleRequest(req, res);
    });

    app.listen(port, () => {
      console.log(`TS McpServer running on port ${port} with /mcp base path`);
    });
  }
}

main().catch(console.error);
