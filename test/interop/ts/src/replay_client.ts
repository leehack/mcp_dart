import { StreamableHTTPClientTransport } from '@modelcontextprotocol/sdk/client/streamableHttp.js';
import type { JSONRPCMessage } from '@modelcontextprotocol/sdk/types.js';

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

function getNotificationParams(message: JSONRPCMessage): Record<string, unknown> | undefined {
  if (!('method' in message) || message.method !== 'notifications/message') {
    return undefined;
  }

  const params = message.params;
  if (typeof params !== 'object' || params === null || Array.isArray(params)) {
    return undefined;
  }

  return params as Record<string, unknown>;
}

async function main(): Promise<void> {
  const url = getArg('--url')!;
  const sessionId = getArg('--session-id')!;
  const lastEventId = getArg('--last-event-id')!;
  const expectedSeq = Number(getArg('--expect-seq')!);
  const expectedToken = getArg('--expect-token', false);
  const rejectedToken = getArg('--reject-token', false);
  const timeoutMs = Number(getArg('--timeout-ms', false) ?? '5000');

  const transport = new StreamableHTTPClientTransport(new URL(url), {
    sessionId,
    reconnectionOptions: {
      initialReconnectionDelay: 100,
      maxReconnectionDelay: 100,
      reconnectionDelayGrowFactor: 1,
      maxRetries: 0,
    },
  });

  const tokens: string[] = [];

  const receivedExpected = new Promise<void>((resolve, reject) => {
    const timeout = setTimeout(() => {
      reject(
        new Error(
          `Timed out waiting for notifications/message with seq=${expectedSeq}; tokens=${tokens.join(',')}`
        )
      );
    }, timeoutMs);

    transport.onerror = (error) => {
      clearTimeout(timeout);
      reject(error);
    };

    transport.onmessage = (message) => {
      const params = getNotificationParams(message);
      if (params?.seq !== expectedSeq) {
        return;
      }
      clearTimeout(timeout);
      resolve();
    };
  });

  await transport.start();
  try {
    await transport.resumeStream(lastEventId, {
      onresumptiontoken: (token) => {
        tokens.push(token);
      },
    });

    await receivedExpected;

    if (expectedToken !== undefined && !tokens.includes(expectedToken)) {
      throw new Error(
        `Expected replay token ${expectedToken}, got ${tokens.join(',')}`
      );
    }

    if (rejectedToken !== undefined && tokens.includes(rejectedToken)) {
      throw new Error(`Unexpected replay token ${rejectedToken}`);
    }
  } finally {
    await transport.close();
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
