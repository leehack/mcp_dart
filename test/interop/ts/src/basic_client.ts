import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';
import {
  CreateMessageRequestSchema,
  ElicitRequestSchema,
  ListRootsRequestSchema,
} from '@modelcontextprotocol/sdk/types.js';

function readArg(args: string[], name: string): string | undefined {
  const index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) {
    return undefined;
  }
  return args[index + 1];
}

function readServerArgs(args: string[]): string[] {
  const value = readArg(args, '--server-args');
  return value ? value.split(' ').filter((part) => part.length > 0) : [];
}

function hasFlag(args: string[], name: string): boolean {
  return args.includes(name);
}

async function main(): Promise<void> {
  const args = process.argv.slice(2);
  const command = readArg(args, '--server-command');
  const activeClientCapabilities = hasFlag(
    args,
    '--active-client-capabilities'
  );
  if (!command) {
    throw new Error('--server-command is required');
  }

  const transport = new StdioClientTransport({
    command,
    args: readServerArgs(args),
    cwd: readArg(args, '--server-cwd'),
  });
  const client = new Client(
    { name: 'ts-basic-client', version: '1.0.0' },
    {
      capabilities: activeClientCapabilities
        ? {
            roots: { listChanged: true },
            sampling: {},
            elicitation: { form: {} },
          }
        : {},
    }
  );

  if (activeClientCapabilities) {
    client.setRequestHandler(ListRootsRequestSchema, async () => ({
      roots: [{ uri: 'file:///tmp/mcp-inspector', name: 'Inspector Root' }],
    }));
    client.setRequestHandler(CreateMessageRequestSchema, async () => ({
      model: 'inspector-mock-model',
      role: 'assistant' as const,
      content: {
        type: 'text' as const,
        text: 'inspector sampling response',
      },
    }));
    client.setRequestHandler(ElicitRequestSchema, async () => ({
      action: 'accept' as const,
      content: { confirmed: true },
    }));
  }

  try {
    await client.connect(transport);

    const tools = await client.listTools();
    const toolNames = tools.tools.map((tool) => tool.name);
    if (!toolNames.includes('echo')) {
      throw new Error(`Expected echo tool, got ${toolNames.join(', ')}`);
    }

    const result = await client.callTool({
      name: 'echo',
      arguments: { message: 'from typescript client' },
    });
    const content = result.content as Array<{ type: string; text?: string }>;
    const text = content[0];
    if (text.type !== 'text' || text.text !== 'from typescript client') {
      throw new Error(`Unexpected echo result: ${JSON.stringify(result)}`);
    }

    if (hasFlag(args, '--expect-inspector-primitives')) {
      const resources = await client.listResources();
      const resourceUris = resources.resources.map((resource) => resource.uri);
      if (!resourceUris.includes('inspector://status')) {
        throw new Error(
          `Expected inspector://status resource, got ${resourceUris.join(', ')}`
        );
      }

      const prompts = await client.listPrompts();
      const promptNames = prompts.prompts.map((prompt) => prompt.name);
      if (!promptNames.includes('inspector-summary')) {
        throw new Error(
          `Expected inspector-summary prompt, got ${promptNames.join(', ')}`
        );
      }
    }

    console.log('typescript client interop passed');
  } finally {
    await client.close();
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
