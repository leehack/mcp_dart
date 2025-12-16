import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
import { SSEClientTransport } from "@modelcontextprotocol/sdk/client/sse.js";
import { StreamableHttpClientTransport } from "./streamable_client_transport.js";
import {
  CallToolResultSchema,
  ListToolsResultSchema,
  ReadResourceResultSchema,
  GetPromptResultSchema,
} from "@modelcontextprotocol/sdk/types.js";

async function main() {
  const args = process.argv.slice(2);
  let transportType = "stdio";
  let serverCommand = "";
  let serverArgs: string[] = [];
  let url = "";

  for (let i = 0; i < args.length; i++) {
    if (args[i] === "--transport" && i + 1 < args.length) {
      transportType = args[i + 1];
    } else if (args[i] === "--server-command" && i + 1 < args.length) {
      serverCommand = args[i + 1];
    } else if (args[i] === "--server-args" && i + 1 < args.length) {
      serverArgs = args[i + 1].split(" ");
    } else if (args[i] === "--url" && i + 1 < args.length) {
      url = args[i + 1];
    }
  }

  let transport;
  if (transportType === "stdio") {
    if (!serverCommand) {
      console.error("Error: --server-command is required for stdio transport");
      process.exit(1);
    }
    transport = new StdioClientTransport({
      command: serverCommand,
      args: serverArgs,
    });
  } else if (transportType === "http") {
    if (!url) {
      console.error("Error: --url is required for http transport");
      process.exit(1);
    }
    transport = new StreamableHttpClientTransport(new URL(url));
  } else {
    console.error(`Unknown transport: ${transportType}`);
    process.exit(1);
  }

  const client = new Client(
    {
      name: "ts-test-client",
      version: "1.0.0",
    },
    {
      capabilities: {},
    }
  );

  try {
    if (transportType === "http") {
      // Connect transport explicitly and wait for 'endpoint' event to be processed
      // This is needed because the SDK might send 'initialize' before receiving the updated endpoint
      // which contains the session ID.
      await transport.start();
      await new Promise((resolve) => setTimeout(resolve, 1000));
      // Hack: prevent client.connect from throwing 'already started'
      transport.start = async () => { };
    }
    await client.connect(transport);

    // 1. List Tools
    const tools = await client.listTools();
    const toolNames = tools.tools.map((t) => t.name);
    if (!toolNames.includes("echo") || !toolNames.includes("add")) {
      throw new Error(`Missing tools. Found: ${toolNames}`);
    }

    // 2. Call Tool 'echo'
    const echoResult = await client.callTool({
      name: "echo",
      arguments: { message: "hello from ts" },
    });
    // @ts-ignore
    const echoText = echoResult.content[0].text;
    if (echoText !== "hello from ts") {
      throw new Error(`Echo failed. Expected 'hello from ts', got '${echoText}'`);
    }

    // 3. Call Tool 'add'
    const addResult = await client.callTool({
      name: "add",
      arguments: { a: 10, b: 20 },
    });
    // @ts-ignore
    const addText = addResult.content[0].text;
    if (addText !== "30" && addText !== 30) {
      throw new Error(`Add failed. Expected '30', got '${addText}'`);
    }

    // 4. Read Resource
    const resourceResult = await client.readResource({
      uri: "resource://test",
    });
    // @ts-ignore
    const resourceText = resourceResult.contents[0].text;
    if (resourceText !== "This is a test resource") {
      throw new Error(
        `Read resource failed. Expected 'This is a test resource', got '${resourceText}'`
      );
    }

    // 5. Get Prompt
    const promptResult = await client.getPrompt({
      name: "test_prompt",
    });
    // @ts-ignore
    const promptText = promptResult.messages[0].content.text;
    if (promptText !== "Test Prompt") {
      throw new Error(
        `Get prompt failed. Expected 'Test Prompt', got '${promptText}'`
      );
    }

    console.log("All interop tests passed!");
    process.exit(0);
  } catch (error) {
    console.error("Interop test failed:", error);
    process.exit(1);
  }
}

main();
