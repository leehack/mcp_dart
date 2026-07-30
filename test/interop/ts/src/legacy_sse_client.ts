import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { SSEClientTransport } from '@modelcontextprotocol/sdk/client/sse.js';

class ProtocolTrackingSSEClientTransport extends SSEClientTransport {
  protocolVersion?: string;

  override setProtocolVersion(version: string): void {
    this.protocolVersion = version;
    super.setProtocolVersion(version);
  }
}

function readArg(args: string[], name: string): string | undefined {
  const index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) {
    return undefined;
  }
  return args[index + 1];
}

async function main(): Promise<void> {
  const url = readArg(process.argv.slice(2), '--url');
  if (!url) {
    throw new Error('--url is required');
  }

  const client = new Client(
    { name: 'ts-legacy-sse-client', version: '1.0.0' },
    { capabilities: {} }
  );
  const transport = new ProtocolTrackingSSEClientTransport(new URL(url));

  try {
    await client.connect(transport);
    if (transport.protocolVersion !== '2025-11-25') {
      throw new Error(
        `Unexpected negotiated protocol: ${transport.protocolVersion}`
      );
    }
    const server = client.getServerVersion();
    if (server?.name !== 'example-dart-server') {
      throw new Error(
        `Unexpected Dart server identity: ${JSON.stringify(server)}`
      );
    }

    const tools = await client.listTools();
    if (!tools.tools.some((tool) => tool.name === 'calculate')) {
      throw new Error(
        `Dart server did not advertise calculate: ${JSON.stringify(tools)}`
      );
    }

    const result = await client.callTool({
      name: 'calculate',
      arguments: { operation: 'add', a: 20, b: 22 },
    });
    const content = result.content as Array<{ type: string; text?: string }>;
    if (content[0]?.type !== 'text' || content[0].text !== 'Result: 42') {
      throw new Error(`Unexpected calculate result: ${JSON.stringify(result)}`);
    }

    console.log('TypeScript legacy SSE client interop passed: Result: 42');
  } finally {
    await client.close();
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
