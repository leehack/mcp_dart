import { Client, StreamableHTTPClientTransport } from '@modelcontextprotocol/client';

const PROTOCOL_VERSION = '2026-07-28';
const CLIENT_INFO = { name: 'mcp-dart-ts-2026-rc-client', version: '0.0.0' };

function readArg(args, name) {
  const index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) {
    return undefined;
  }
  return args[index + 1];
}

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function assertCacheMetadata(result, method) {
  assert(
    Number.isInteger(result.ttlMs) && result.ttlMs >= 0,
    `${method} expected non-negative integer ttlMs, got ${JSON.stringify(result)}`,
  );
  assert(
    result.cacheScope === 'public' || result.cacheScope === 'private',
    `${method} expected cacheScope public/private, got ${JSON.stringify(result)}`,
  );
}

function requireTool(tools, name) {
  const tool = tools.find((candidate) => candidate.name === name);
  assert(
    tool,
    `Expected ${name} tool, got ${tools.map((item) => item.name).join(', ')}`,
  );
  return tool;
}

function requireText(result, expected, label) {
  const content = Array.isArray(result.content) ? result.content : [];
  const first = content[0];
  assert(
    first && first.type === 'text' && first.text === expected,
    `${label} unexpected result: ${JSON.stringify(result)}`,
  );
  return first.text;
}

function assertCustomHeaderSchema(tool) {
  const properties = tool.inputSchema?.properties ?? {};
  assert(
    properties.region?.['x-mcp-header'] === 'Region',
    `region x-mcp-header missing from ${tool.name}`,
  );
  assert(
    properties.count?.['x-mcp-header'] === 'Count',
    `count x-mcp-header missing from ${tool.name}`,
  );
  assert(
    properties.dryRun?.['x-mcp-header'] === 'Dry-Run',
    `dryRun x-mcp-header missing from ${tool.name}`,
  );
  assert(
    properties.auth?.properties?.tenant?.['x-mcp-header'] === 'Tenant',
    `nested tenant x-mcp-header missing from ${tool.name}`,
  );
}

async function main() {
  const urlValue = readArg(process.argv.slice(2), '--url');
  if (!urlValue) {
    throw new Error('--url is required');
  }

  const client = new Client(
    CLIENT_INFO,
    {
      capabilities: { elicitation: {} },
      versionNegotiation: { mode: { pin: PROTOCOL_VERSION } },
    },
  );
  client.setRequestHandler('elicitation/create', async (request) => {
    assert(
      request.params?.mode === 'form' || request.params?.mode === undefined,
      `Expected form elicitation, got ${JSON.stringify(request)}`,
    );
    return {
      action: 'accept',
      content: { name: 'TypeScript Tester' },
    };
  });

  const transport = new StreamableHTTPClientTransport(new URL(urlValue));

  try {
    await client.connect(transport);

    const era = client.getProtocolEra();
    const version = client.getNegotiatedProtocolVersion();
    assert(
      era === 'modern' && version === PROTOCOL_VERSION,
      `Expected modern ${PROTOCOL_VERSION}, got ${era}/${version}`,
    );

    const discover = await client.discover();
    assertCacheMetadata(discover, 'server/discover');
    assert(
      discover.supportedVersions?.includes(PROTOCOL_VERSION),
      `server/discover did not advertise ${PROTOCOL_VERSION}: ${JSON.stringify(discover)}`,
    );
    assert(
      discover.serverInfo?.name === 'dart-test-server',
      `server/discover returned unexpected serverInfo: ${JSON.stringify(discover.serverInfo)}`,
    );

    const tools = await client.listTools();
    assertCacheMetadata(tools, 'tools/list');
    const toolNames = tools.tools.map((tool) => tool.name);
    requireTool(tools.tools, 'echo');
    assertCustomHeaderSchema(
      requireTool(tools.tools, 'test_custom_headers_valid'),
    );
    requireTool(tools.tools, 'test_input_required_result_elicitation');

    const message = 'from TypeScript 2026 RC preview';
    const result = await client.callTool({
      name: 'echo',
      arguments: { message },
    });
    const echo = requireText(result, message, 'echo');

    const customHeaders = await client.callTool({
      name: 'test_custom_headers_valid',
      arguments: {
        region: 'us-east1',
        count: 42,
        dryRun: false,
        auth: { tenant: ' padded ' },
      },
    });
    requireText(customHeaders, 'custom-header-ok', 'custom header mirroring');

    const elicitation = await client.callTool({
      name: 'test_input_required_result_elicitation',
      arguments: {},
    });
    const elicitationText = requireText(
      elicitation,
      'Hello, TypeScript Tester!',
      'input_required elicitation',
    );

    console.log(
      JSON.stringify({
        protocolEra: era,
        protocolVersion: version,
        discoveredVersions: discover.supportedVersions,
        toolCount: toolNames.length,
        echo,
        customHeaders: 'ok',
        inputRequired: elicitationText,
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
