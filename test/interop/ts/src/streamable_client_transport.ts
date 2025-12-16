import type { Transport } from '@modelcontextprotocol/sdk/shared/transport.js';
import type { JSONRPCMessage } from '@modelcontextprotocol/sdk/types.js';

export class StreamableHttpClientTransport implements Transport {
  private _sessionId?: string;
  private _endpoint: URL;
  private _errorHandler?: (error: Error) => void;
  private _messageHandler?: (message: JSONRPCMessage) => void;
  private _closeHandler?: () => void;
  private _abortController: AbortController;
  private _sseStarted = false;

  constructor(endpoint: URL) {
    this._endpoint = new URL(endpoint);
    this._abortController = new AbortController();
  }

  async start(): Promise<void> {
    // If sessionId is already in the URL (from constructor), extract it
    const urlSessionId = this._endpoint.searchParams.get('sessionId');
    if (urlSessionId) {
      this._sessionId = urlSessionId;
    }

    // Don't start SSE connection here - wait until after first POST request
    // The SSE connection is started after we receive the session ID from initialize
  }

  private _connectSSE(): void {
    const sseUrl = new URL(this._endpoint);
    // Remove custom check search param if present, as we send header
    // But keep it if the URL structure expects it.
    // The previous plan discussed tests passing it in URL query.
    // The SDK/Test interface might pass generic URLs.

    // We need to use fetch to support headers for SSE
    this._connectSSEWithFetch(sseUrl);
  }

  private async _connectSSEWithFetch(url: URL) {
    try {
      const headers: HeadersInit = {
        Accept: 'text/event-stream',
        'Cache-Control': 'no-cache',
      };

      if (this._sessionId) {
        headers['mcp-session-id'] = this._sessionId;
      }

      const response = await fetch(url, {
        method: 'GET',
        headers,
        signal: this._abortController.signal,
      });

      if (!response.ok) {
        throw new Error(
          `SSE connection failed: ${response.status} ${response.statusText}`
        );
      }

      if (!response.body) {
        throw new Error('No response body for SSE stream');
      }

      // Read the stream
      const reader = response.body.getReader();
      const decoder = new TextDecoder();
      let buffer = '';

      while (true) {
        const { done, value } = await reader.read();
        if (done) {
          break;
        }

        const chunk = decoder.decode(value, { stream: true });
        buffer += chunk;

        const lines = buffer.split(/\n\n/);
        buffer = lines.pop() || ''; // Keep the last partial chunk

        for (const block of lines) {
          this._processSSEBlock(block);
        }
      }
    } catch (error: unknown) {
      if (error instanceof Error && error.name === 'AbortError') {
        return;
      }
      if (!(error instanceof Error)) {
        return;
      }
      this._errorHandler?.(error);
    }
  }

  private _processSSEBlock(block: string) {
    const lines = block.split('\n');
    let eventType = 'message';
    let data = '';

    for (const line of lines) {
      if (line.startsWith('event: ')) {
        eventType = line.substring(7).trim();
      } else if (line.startsWith('data: ')) {
        data = line.substring(6);
      }
    }

    if (eventType === 'message' && data) {
      try {
        const message = JSON.parse(data);
        this._messageHandler?.(message);
      } catch (e) {
        console.error('Failed to parse SSE message', e);
      }
    }
  }

  async close(): Promise<void> {
    this._abortController.abort();
    this._closeHandler?.();
  }

  async send(message: JSONRPCMessage): Promise<void> {
    const headers: HeadersInit = {
      'Content-Type': 'application/json',
      Accept: 'application/json, text/event-stream',
    };

    if (this._sessionId) {
      headers['mcp-session-id'] = this._sessionId;
    }

    const response = await fetch(this._endpoint, {
      method: 'POST',
      headers,
      body: JSON.stringify(message),
      signal: this._abortController.signal,
    });

    if (!response.ok) {
      const text = await response.text();
      throw new Error(`HTTP error ${response.status}: ${text}`);
    }

    // Capture session ID from response headers
    const responseSessionId = response.headers.get('mcp-session-id');
    if (responseSessionId && !this._sessionId) {
      this._sessionId = responseSessionId;
    }

    // Start SSE connection after first successful POST (which will be initialize)
    if (!this._sseStarted && this._sessionId) {
      this._sseStarted = true;
      // Start SSE in background - don't await
      this._connectSSE();
    }

    const contentType = response.headers.get('content-type');
    if (contentType?.includes('application/json')) {
      // Safe to read as text first then parse, or just json()
      // Sometimes empty body 202 accepted?
      if (response.status === 202) {
        // Accepted, no body or empty body
        return;
      }

      const data = await response.json();
      if (Array.isArray(data)) {
        data.forEach((msg) => this._messageHandler?.(msg));
      } else {
        this._messageHandler?.(data as JSONRPCMessage);
      }
    } else if (contentType?.includes('text/event-stream')) {
      // Handle stream for this specific request
      // @ts-expect-error - response.body is ReadableStream
      const reader = response.body.getReader();
      const decoder = new TextDecoder();
      let buffer = '';

      while (true) {
        const { done, value } = await reader.read();
        if (done) {
          break;
        }
        const chunk = decoder.decode(value, { stream: true });
        buffer += chunk;
        const lines = buffer.split(/\n\n/);
        buffer = lines.pop() || '';
        for (const block of lines) {
          this._processSSEBlock(block);
        }
      }
    }
  }

  set onclose(handler: () => void) {
    this._closeHandler = handler;
  }

  set onerror(handler: (error: Error) => void) {
    this._errorHandler = handler;
  }

  set onmessage(handler: (message: JSONRPCMessage) => void) {
    this._messageHandler = handler;
  }
}
