import { McpServer, ResourceTemplate } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { StreamableHTTPServerTransport, StreamableHTTPServerTransportOptions } from "@modelcontextprotocol/sdk/server/streamableHttp.js";
import { z } from "zod";
import express from "express";
import { randomUUID } from 'node:crypto'; // Correct import for UUID generation

// Minimal EventStore interface and InMemoryEventStore implementation for testing
interface EventStore {
  storeEvent(sessionId: string, event: any): Promise<string>; // Returns event ID
  replayEventsAfter(lastEventId: string, options: { send: (eventId: string, message: any) => Promise<void>; }): Promise<string>; // Mock replay
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
  async replayEventsAfter(lastEventId: string, { send }: { send: (eventId: string, message: any) => Promise<void>; }): Promise<string> {
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
  let transportName = "stdio";
  let port = 3000;

  const args = process.argv.slice(2);
  for (let i = 0; i < args.length; i++) {
    if (args[i] === "--transport" && args[i + 1]) {
      transportName = args[i + 1];
      i++;
    } else if (args[i] === "--port" && args[i + 1]) {
      port = parseInt(args[i + 1], 10);
      i++;
    }
  }

  // 1. Create Server
  const server = new McpServer({
    name: "ts-interop-server",
    version: "1.0.0",
  });

  // 2. Register Features

  // Tool: echo
  server.registerTool(
    "echo",
    {
      inputSchema: { message: z.string() }
    },
    async ({ message }) => {
      return {
        content: [{ type: "text", text: message }]
      };
    }
  );

  // Tool: add
  server.registerTool(
    "add",
    {
      inputSchema: { a: z.number(), b: z.number() }
    },
    async ({ a, b }) => {
      return {
        content: [{ type: "text", text: String(a + b) }]
      };
    }
  );

  // Resource: resource://test
  server.registerResource(
    "test-resource",
    "resource://test",
    {}, // No metadata
    async (uri) => {
      return {
        contents: [{
          uri: uri.href,
          text: "This is a test resource",
          mimeType: "text/plain"
        }]
      };
    }
  );

  // Prompt: test_prompt
  server.registerPrompt(
    "test_prompt",
    {
      argsSchema: {}
    },
    async () => {
      return {
        messages: [{
          role: "user",
          content: { type: "text", text: "Test Prompt" }
        }]
      };
    }
  );

  // 3. Connect Transport
  if (transportName === "stdio") {
    const transport = new StdioServerTransport();
    await server.connect(transport);
    // Keep process alive
  } else if (transportName === "http") {
    const app = express();
    // app.use(express.json()); // Removed: StreamableHTTPServerTransport expects raw body

    const transports = new Map<string, StreamableHTTPServerTransport>();
    const eventStore = new InMemoryEventStore();

    // GET /mcp/sse for establishing the SSE connection
    app.get("/mcp/sse", async (req, res) => {
      // const newSessionId = (req.query.sessionId as string) || randomUUID(); // Let transport generate its own ID
      const options: StreamableHTTPServerTransportOptions = {
        eventStore: eventStore,
      };
      const transport = new StreamableHTTPServerTransport(options);

      await server.connect(transport); // Connect the MCP server to this new transport

      const sessionId = transport.sessionId; // Get the generated session ID
      if (!sessionId) {
        console.error("[TS Server] SSE Transport failed to generate session ID");
        res.status(500).send("Server error: Could not establish session");
        return;
      }
      transports.set(sessionId, transport);
      console.log(`[TS Server] New SSE connection. Session ID: ${sessionId}. Total active sessions: ${transports.size}`);

      // Pass the request and response to the transport for message handling
      transport.handleRequest(req, res);

      transport.onclose = () => {
        console.log(`[TS Server] Transport closed: ${sessionId}. Remaining sessions: ${transports.size}`);
        transports.delete(sessionId);
      };
    });

    // POST /mcp for sending JSON-RPC messages
    app.post("/mcp", async (req, res) => {
      let sessionId = (req.query.sessionId as string) || (req.headers["x-mcp-session-id"] as string);
      let transport: StreamableHTTPServerTransport | undefined;

      if (!sessionId || !transports.has(sessionId)) {
        // Treat as an initial connection for a new session if no session ID or not found
        console.log("[TS Server] Initial POST request without known session ID. Creating new session.");
        sessionId = randomUUID(); // Explicitly generate a UUID for this initial POST
        const options: StreamableHTTPServerTransportOptions = {
          eventStore: eventStore,
        };
        const newTransport = new StreamableHTTPServerTransport(options);

        await server.connect(newTransport); // Connect the MCP server to this new transport

        // The newTransport.sessionId may not be available immediately, so we use our generated ID
        transports.set(sessionId, newTransport);
        transport = newTransport;

        console.log(`[TS Server] New POST connection. Session ID: ${sessionId}. Total active sessions: ${transports.size}`);

        // Set the session ID in the response header for the client
        res.setHeader("x-mcp-session-id", sessionId);

        newTransport.onclose = () => {
          console.log(`[TS Server] Transport closed: ${sessionId}. Remaining sessions: ${transports.size}`);
          transports.delete(sessionId);
        };

      } else { // Session ID is present and transport exists
        transport = transports.get(sessionId);
      }

      if (!transport) {
        console.error(`[TS Server] Session not found for ID: ${sessionId}. Available: ${Array.from(transports.keys())}`);
        res.status(404).send("Session not found");
        return;
      }

      console.log(`[TS Server] POST /mcp received. Session ID: ${sessionId}. Req Body:`, req.body);
      // Pass the request and response to the transport for message handling
      transport.handleRequest(req, res);
    });

    app.listen(port, () => {
      console.log(`TS McpServer running on port ${port} with /mcp base path`);
    });
  }
}

main().catch(console.error);
