import { Client, StreamableHTTPClientTransport } from '@modelcontextprotocol/client';

function readArg(args, name) {
  const index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) {
    return undefined;
  }
  return args[index + 1];
}

async function main() {
  const urlValue = readArg(process.argv.slice(2), '--url');
  if (!urlValue) {
    throw new Error('--url is required');
  }

  const client = new Client(
    { name: 'mcp-dart-ts-2026-rc-client', version: '0.0.0' },
    {
      capabilities: {},
      versionNegotiation: { mode: { pin: '2026-07-28' } },
    },
  );
  const transport = new StreamableHTTPClientTransport(new URL(urlValue));

  try {
    await client.connect(transport);

    const era = client.getProtocolEra();
    const version = client.getNegotiatedProtocolVersion();
    if (era !== 'modern' || version !== '2026-07-28') {
      throw new Error(`Expected modern 2026-07-28, got ${era}/${version}`);
    }

    const tools = await client.listTools();
    const toolNames = tools.tools.map((tool) => tool.name);
    if (!toolNames.includes('echo')) {
      throw new Error(`Expected echo tool, got ${toolNames.join(', ')}`);
    }

    const message = 'from TypeScript 2026 RC preview';
    const result = await client.callTool({
      name: 'echo',
      arguments: { message },
    });
    const content = Array.isArray(result.content) ? result.content : [];
    const first = content[0];
    if (!first || first.type !== 'text' || first.text !== message) {
      throw new Error(`Unexpected echo result: ${JSON.stringify(result)}`);
    }

    console.log(
      JSON.stringify({
        protocolEra: era,
        protocolVersion: version,
        toolCount: toolNames.length,
        echo: first.text,
      }),
    );
  } finally {
    await client.close();
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});

