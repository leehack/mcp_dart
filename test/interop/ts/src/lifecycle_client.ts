import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';
import { StreamableHTTPClientTransport } from '@modelcontextprotocol/sdk/client/streamableHttp.js';

function getArg(name: string, required = true): string | undefined {
  const index = process.argv.indexOf(name);
  if (index >= 0 && index + 1 < process.argv.length) {
    return process.argv[index + 1];
  }
  if (required) {
    throw new Error(`Missing required argument: ${name}`);
  }
  return undefined;
}

async function main(): Promise<void> {
  const transportType = getArg('--transport', false) ?? 'stdio';

  let transport: StdioClientTransport | StreamableHTTPClientTransport;
  if (transportType === 'stdio') {
    const serverCommand = getArg('--server-command')!;
    const serverArgs = getArg('--server-args', false)?.split(' ') ?? [];
    transport = new StdioClientTransport({
      command: serverCommand,
      args: serverArgs,
    });
  } else if (transportType === 'http') {
    const url = getArg('--url')!;
    transport = new StreamableHTTPClientTransport(new URL(url));
  } else {
    throw new Error(`Unsupported transport: ${transportType}`);
  }

  const client = new Client(
    {
      name: 'ts-lifecycle-client',
      version: '1.0.0',
    },
    {
      capabilities: {},
    }
  );

  await client.connect(transport);
  try {
    const result = await client.listTools();
    const toolNames = result.tools.map((tool) => tool.name);
    if (!toolNames.includes('echo') || !toolNames.includes('add')) {
      throw new Error(`Missing expected tools. Found: ${toolNames.join(',')}`);
    }
  } finally {
    await client.close();
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
