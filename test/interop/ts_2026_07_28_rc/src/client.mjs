import { Client, StreamableHTTPClientTransport } from '@modelcontextprotocol/client';

const PROTOCOL_VERSION = '2026-07-28';
const CLIENT_INFO = { name: 'mcp-dart-ts-2026-07-28-rc-client', version: '0.0.0' };

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

function firstText(result, label) {
  const content = Array.isArray(result.content) ? result.content : [];
  const first = content[0];
  assert(
    first && first.type === 'text',
    `${label} expected text content: ${JSON.stringify(result)}`,
  );
  return first.text;
}

function requestMeta(extra = {}) {
  return {
    'io.modelcontextprotocol/protocolVersion': PROTOCOL_VERSION,
    'io.modelcontextprotocol/clientInfo': CLIENT_INFO,
    'io.modelcontextprotocol/clientCapabilities': { elicitation: {} },
    ...extra,
  };
}

async function rawRpc(urlValue, {
  id,
  method,
  params = {},
  headers = {},
  removeHeaders = [],
  signal,
}) {
  const requestHeaders = new Headers({
    Accept: 'application/json, text/event-stream',
    'Content-Type': 'application/json',
    'MCP-Protocol-Version': PROTOCOL_VERSION,
    'Mcp-Method': method,
    ...headers,
  });
  for (const header of removeHeaders) {
    requestHeaders.delete(header);
  }

  return fetch(urlValue, {
    method: 'POST',
    headers: requestHeaders,
    body: JSON.stringify({
      jsonrpc: '2.0',
      id,
      method,
      params,
    }),
    signal,
  });
}

async function readJsonResponse(response, label) {
  const text = await response.text();
  try {
    return JSON.parse(text);
  } catch (error) {
    throw new Error(`${label} returned non-JSON body: ${text}`);
  }
}

async function expectHeaderMismatch(response, label) {
  assert(
    response.status === 400,
    `${label} expected HTTP 400, got ${response.status}`,
  );
  const body = await readJsonResponse(response, label);
  assert(
    body.error?.code === -32020,
    `${label} expected HeaderMismatch -32020, got ${JSON.stringify(body)}`,
  );
}

async function expectUnsupportedProtocolVersion(response, label) {
  assert(
    response.status === 400,
    `${label} expected HTTP 400, got ${response.status}`,
  );
  const body = await readJsonResponse(response, label);
  assert(
    body.error?.code === -32022,
    `${label} expected UnsupportedProtocolVersion -32022, got ${JSON.stringify(body)}`,
  );
  assert(
    body.error?.data?.requested === '1900-01-01',
    `${label} missing requested version in error data: ${JSON.stringify(body)}`,
  );
  assert(
    body.error?.data?.supported?.includes(PROTOCOL_VERSION),
    `${label} missing supported ${PROTOCOL_VERSION} in error data: ${JSON.stringify(body)}`,
  );
}

async function expectMethodNotFound(response, label) {
  assert(
    response.status === 404,
    `${label} expected HTTP 404, got ${response.status}`,
  );
  const body = await readJsonResponse(response, label);
  assert(
    body.error?.code === -32601,
    `${label} expected MethodNotFound -32601, got ${JSON.stringify(body)}`,
  );
}

async function assertRawHeaderValidation(urlValue) {
  await expectHeaderMismatch(
    await rawRpc(urlValue, {
      id: 'missing-protocol-version-header',
      method: 'server/discover',
      params: { _meta: requestMeta() },
      removeHeaders: ['MCP-Protocol-Version'],
    }),
    'missing MCP-Protocol-Version',
  );

  await expectHeaderMismatch(
    await rawRpc(urlValue, {
      id: 'missing-method-header',
      method: 'server/discover',
      params: { _meta: requestMeta() },
      removeHeaders: ['Mcp-Method'],
    }),
    'missing Mcp-Method',
  );

  await expectHeaderMismatch(
    await rawRpc(urlValue, {
      id: 'protocol-header-mismatch',
      method: 'server/discover',
      params: {
        _meta: requestMeta({
          'io.modelcontextprotocol/protocolVersion': '2025-11-25',
        }),
      },
    }),
    'MCP-Protocol-Version mismatch',
  );

  await expectUnsupportedProtocolVersion(
    await rawRpc(urlValue, {
      id: 'unsupported-protocol-version',
      method: 'server/discover',
      params: {
        _meta: requestMeta({
          'io.modelcontextprotocol/protocolVersion': '1900-01-01',
        }),
      },
      headers: { 'MCP-Protocol-Version': '1900-01-01' },
    }),
    'unsupported MCP-Protocol-Version',
  );

  await expectHeaderMismatch(
    await rawRpc(urlValue, {
      id: 'name-header-mismatch',
      method: 'tools/call',
      params: {
        name: 'a_header_probe',
        arguments: {},
        _meta: requestMeta(),
      },
      headers: { 'Mcp-Name': 'echo' },
    }),
    'Mcp-Name mismatch',
  );

  await expectHeaderMismatch(
    await rawRpc(urlValue, {
      id: 'param-header-mismatch',
      method: 'tools/call',
      params: {
        name: 'test_custom_headers_valid',
        arguments: {
          region: 'us-east1',
          count: 42,
          dryRun: false,
          auth: { tenant: 'tenant-a' },
        },
        _meta: requestMeta(),
      },
      headers: {
        'Mcp-Name': 'test_custom_headers_valid',
        'Mcp-Param-Region': 'us-east1',
        'Mcp-Param-Count': '43',
        'Mcp-Param-Dry-Run': 'false',
        'Mcp-Param-Tenant': 'tenant-a',
      },
    }),
    'Mcp-Param header mismatch',
  );
}

async function assertRemovedCoreRequests(urlValue) {
  await expectMethodNotFound(
    await rawRpc(urlValue, {
      id: 'removed-ping',
      method: 'ping',
      params: { _meta: requestMeta() },
    }),
    'removed ping',
  );
}

function parseSseFrames(buffer, messages) {
  let remaining = buffer;
  for (;;) {
    const separator = remaining.indexOf('\n\n');
    if (separator < 0) {
      return remaining;
    }

    const frame = remaining.slice(0, separator);
    remaining = remaining.slice(separator + 2);
    const data = frame
      .split('\n')
      .filter((line) => line.startsWith('data:'))
      .map((line) => line.slice(5).trimStart())
      .join('\n');
    if (data.length > 0) {
      messages.push(JSON.parse(data));
    }
  }
}

async function collectSseMessages(response, expectedCount, label) {
  assert(
    response.headers.get('content-type')?.includes('text/event-stream'),
    `${label} expected SSE response, got ${response.headers.get('content-type')}`,
  );
  assert(response.body, `${label} response did not expose a body stream`);

  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  const messages = [];
  let buffer = '';
  const deadline = Date.now() + 5000;

  try {
    while (messages.length < expectedCount) {
      const remainingMs = Math.max(1, deadline - Date.now());
      const read = await Promise.race([
        reader.read(),
        new Promise((_, reject) =>
          setTimeout(
            () => reject(new Error(`${label} timed out waiting for SSE`)),
            remainingMs,
          ),
        ),
      ]);
      if (read.done) {
        break;
      }
      buffer = parseSseFrames(
        buffer + decoder.decode(read.value, { stream: true }),
        messages,
      );
    }
  } finally {
    await reader.cancel().catch(() => {});
  }

  assert(
    messages.length >= expectedCount,
    `${label} expected ${expectedCount} SSE messages, got ${JSON.stringify(messages)}`,
  );
  return messages;
}

async function assertSubscriptionListen(urlValue) {
  const response = await rawRpc(urlValue, {
    id: 'listen-tools',
    method: 'subscriptions/listen',
    params: {
      notifications: { toolsListChanged: true },
      _meta: requestMeta(),
    },
  });
  assert(
    response.status === 200,
    `subscriptions/listen expected HTTP 200, got ${response.status}`,
  );

  const messages = await collectSseMessages(
    response,
    2,
    'subscriptions/listen',
  );
  assert(
    messages[0].method === 'notifications/subscriptions/acknowledged',
    `subscriptions/listen expected acknowledgment first, got ${JSON.stringify(messages[0])}`,
  );
  assert(
    messages[0].params?._meta?.['io.modelcontextprotocol/subscriptionId'] ===
      'listen-tools',
    `subscriptions/listen acknowledgment missing subscription id: ${JSON.stringify(messages[0])}`,
  );
  assert(
    messages[1].method === 'notifications/tools/list_changed',
    `subscriptions/listen expected tools list_changed notification, got ${JSON.stringify(messages[1])}`,
  );
  assert(
    messages[1].params?._meta?.['io.modelcontextprotocol/subscriptionId'] ===
      'listen-tools',
    `subscriptions/listen notification missing subscription id: ${JSON.stringify(messages[1])}`,
  );
}

async function cancellationCount(client) {
  const status = await client.callTool({
    name: 'test_stream_cancellation_status',
    arguments: {},
  });
  return Number.parseInt(firstText(status, 'cancellation status'), 10);
}

async function assertStreamCancellation(urlValue, client) {
  const before = await cancellationCount(client);
  const controller = new AbortController();
  const response = await rawRpc(urlValue, {
    id: 'cancel-stream',
    method: 'tools/call',
    params: {
      name: 'test_stream_cancellation',
      arguments: {},
      _meta: requestMeta({ progressToken: 'cancel-stream-progress' }),
    },
    headers: { 'Mcp-Name': 'test_stream_cancellation' },
    signal: controller.signal,
  });
  assert(
    response.status === 200,
    `stream cancellation expected HTTP 200, got ${response.status}`,
  );

  await collectSseMessages(response, 1, 'stream cancellation startup');
  controller.abort();

  const deadline = Date.now() + 5000;
  while (Date.now() < deadline) {
    const after = await cancellationCount(client);
    if (after > before) {
      return;
    }
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error('stream cancellation was not observed by the Dart server');
}

async function assertProgressNotifications(client) {
  const progressValues = [];
  const result = await client.callTool(
    {
      name: 'progress_demo',
      arguments: { steps: 3 },
    },
    {
      timeout: 10000,
      onprogress: (progress) => {
        progressValues.push(progress.progress);
      },
    },
  );

  requireText(
    result,
    'Completed 3 steps with progress notifications',
    'progress demo',
  );
  assert(
    progressValues.length >= 2,
    `progress demo expected multiple progress callbacks, got ${JSON.stringify(progressValues)}`,
  );
  assert(
    progressValues[0] === 0 && progressValues.at(-1) === 100,
    `progress demo expected 0..100 progress, got ${JSON.stringify(progressValues)}`,
  );
  for (let index = 1; index < progressValues.length; index++) {
    assert(
      progressValues[index] > progressValues[index - 1],
      `progress demo values did not strictly increase: ${JSON.stringify(progressValues)}`,
    );
  }
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
    requireTool(tools.tools, 'progress_demo');

    const message = 'from TypeScript 2026-07-28 RC';
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

    await assertRawHeaderValidation(urlValue);
    await assertRemovedCoreRequests(urlValue);
    await assertProgressNotifications(client);
    await assertSubscriptionListen(urlValue);
    await assertStreamCancellation(urlValue, client);

    console.log(
      JSON.stringify({
        protocolEra: era,
        protocolVersion: version,
        discoveredVersions: discover.supportedVersions,
        toolCount: toolNames.length,
        echo,
        customHeaders: 'ok',
        inputRequired: elicitationText,
        rawHeaderValidation: 'ok',
        removedCoreRequests: 'ok',
        progress: 'ok',
        subscriptionsListen: 'ok',
        streamCancellation: 'ok',
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
