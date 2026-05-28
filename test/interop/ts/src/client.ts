import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';
import { StreamableHttpClientTransport } from './streamable_client_transport.js';
import {
  CallToolResultSchema,
  ListRootsRequestSchema,
  CreateMessageRequestSchema,
  ElicitRequestSchema,
} from '@modelcontextprotocol/sdk/types.js';
import type { Progress } from '@modelcontextprotocol/sdk/types.js';
import { z } from 'zod';

type TaskWireShape = {
  taskId?: unknown;
  status?: unknown;
  ttl?: unknown;
  pollInterval?: unknown;
  createdAt?: unknown;
  lastUpdatedAt?: unknown;
};

type RelatedTaskMetaShape = {
  _meta?: {
    'io.modelcontextprotocol/related-task'?: { taskId?: unknown };
    relatedTask?: { taskId?: unknown };
  };
};

function assertTaskWireShape(task: unknown, label: string): void {
  if (typeof task !== 'object' || task === null) {
    throw new Error(`${label} was not an object: ${JSON.stringify(task)}`);
  }

  const taskShape = task as TaskWireShape;
  if (typeof taskShape.taskId !== 'string' || taskShape.taskId.length === 0) {
    throw new Error(`${label} missing string taskId: ${JSON.stringify(task)}`);
  }
  if (typeof taskShape.status !== 'string' || taskShape.status.length === 0) {
    throw new Error(`${label} missing string status: ${JSON.stringify(task)}`);
  }
  if (!Object.prototype.hasOwnProperty.call(taskShape, 'ttl')) {
    throw new Error(
      `${label} missing required ttl key: ${JSON.stringify(task)}`
    );
  }
  if (taskShape.ttl !== null && typeof taskShape.ttl !== 'number') {
    throw new Error(`${label} has invalid ttl: ${JSON.stringify(task)}`);
  }
  if (
    taskShape.pollInterval !== undefined &&
    typeof taskShape.pollInterval !== 'number'
  ) {
    throw new Error(
      `${label} has invalid pollInterval: ${JSON.stringify(task)}`
    );
  }
  if (typeof taskShape.createdAt !== 'string') {
    throw new Error(
      `${label} missing string createdAt: ${JSON.stringify(task)}`
    );
  }
  if (typeof taskShape.lastUpdatedAt !== 'string') {
    throw new Error(
      `${label} missing string lastUpdatedAt: ${JSON.stringify(task)}`
    );
  }
}

function assertRelatedTaskMeta(
  result: unknown,
  expectedTaskId: string,
  label: string
): void {
  if (typeof result !== 'object' || result === null) {
    throw new Error(`${label} was not an object: ${JSON.stringify(result)}`);
  }

  const meta = (result as RelatedTaskMetaShape)._meta;
  const relatedTask = meta?.['io.modelcontextprotocol/related-task'];
  const legacyRelatedTask = meta?.relatedTask;

  if (relatedTask?.taskId !== expectedTaskId) {
    throw new Error(
      `${label} missing related-task metadata for ${expectedTaskId}: ${JSON.stringify(result)}`
    );
  }
  if (legacyRelatedTask?.taskId !== expectedTaskId) {
    throw new Error(
      `${label} missing legacy relatedTask metadata for ${expectedTaskId}: ${JSON.stringify(result)}`
    );
  }
}

function requireRecord(value: unknown, label: string): Record<string, unknown> {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    throw new Error(`${label} was not an object: ${JSON.stringify(value)}`);
  }
  return value as Record<string, unknown>;
}

function assertTitledEnumSchema(tools: unknown): void {
  const toolsResult = requireRecord(tools, 'tools/list result');
  const toolList = toolsResult.tools;
  if (!Array.isArray(toolList)) {
    throw new Error(
      `tools/list result missing tools array: ${JSON.stringify(tools)}`
    );
  }

  const chooseModeTool = toolList
    .map((tool) => requireRecord(tool, 'tool'))
    .find((tool) => tool.name === 'choose_mode');
  if (!chooseModeTool) {
    throw new Error('choose_mode tool was not listed');
  }

  const inputSchema = requireRecord(
    chooseModeTool.inputSchema,
    'choose_mode inputSchema'
  );
  const properties = requireRecord(
    inputSchema.properties,
    'choose_mode properties'
  );
  const mode = requireRecord(properties.mode, 'choose_mode mode schema');
  const modeChoices = mode.oneOf;
  if (!Array.isArray(modeChoices)) {
    throw new Error(`mode schema missing oneOf: ${JSON.stringify(mode)}`);
  }
  const complexChoice = modeChoices
    .map((choice) => requireRecord(choice, 'mode choice'))
    .find((choice) => choice.const === 'complex');
  if (complexChoice?.title !== 'Complex Option') {
    throw new Error(
      `mode schema missing const/title choice: ${JSON.stringify(mode)}`
    );
  }

  const permissions = requireRecord(
    properties.permissions,
    'choose_mode permissions schema'
  );
  const permissionItems = requireRecord(
    permissions.items,
    'choose_mode permissions items schema'
  );
  const permissionChoices = permissionItems.anyOf;
  if (!Array.isArray(permissionChoices)) {
    throw new Error(
      `permissions item schema missing anyOf: ${JSON.stringify(permissionItems)}`
    );
  }
  const writeChoice = permissionChoices
    .map((choice) => requireRecord(choice, 'permission choice'))
    .find((choice) => choice.const === 'write');
  if (writeChoice?.title !== 'Write') {
    throw new Error(
      `permissions schema missing const/title choice: ${JSON.stringify(permissionItems)}`
    );
  }
}

function requireArray(value: unknown, label: string): unknown[] {
  if (!Array.isArray(value)) {
    throw new Error(`${label} was not an array: ${JSON.stringify(value)}`);
  }
  return value;
}

function hasOwn(value: Record<string, unknown>, key: string): boolean {
  return Object.prototype.hasOwnProperty.call(value, key);
}

function assertNoField(
  value: Record<string, unknown>,
  key: string,
  label: string
): void {
  if (hasOwn(value, key)) {
    throw new Error(
      `${label} unexpectedly included ${key}: ${JSON.stringify(value)}`
    );
  }
}

function assertIconList(value: unknown, label: string): void {
  const icons = requireArray(value, `${label} icons`);
  if (icons.length === 0) {
    throw new Error(`${label} icons was empty`);
  }

  const icon = requireRecord(icons[0], `${label} icon`);
  if (
    typeof icon.src !== 'string' ||
    !icon.src.startsWith('data:image/png;base64,')
  ) {
    throw new Error(
      `${label} icon src was not a data URI: ${JSON.stringify(icon)}`
    );
  }
  if (icon.mimeType !== 'image/png') {
    throw new Error(`${label} icon mimeType mismatch: ${JSON.stringify(icon)}`);
  }
  if (icon.theme !== 'dark') {
    throw new Error(`${label} icon theme mismatch: ${JSON.stringify(icon)}`);
  }
}

async function assertRawDartServerWireShapes(client: Client): Promise<void> {
  const capabilities = client.getServerCapabilities() as
    | Record<string, unknown>
    | undefined;
  if (capabilities) {
    assertNoField(capabilities, 'elicitation', 'server capabilities');
    const taskCapabilities = capabilities.tasks;
    if (taskCapabilities !== undefined) {
      assertNoField(
        requireRecord(taskCapabilities, 'server task capabilities'),
        'listChanged',
        'server task capabilities'
      );
    }
  }

  const rawTools = (await client.request(
    { method: 'tools/list' } as any,
    z.any()
  )) as unknown;
  const toolList = requireArray(
    requireRecord(rawTools, 'raw tools/list result').tools,
    'raw tools/list tools'
  ).map((tool) => requireRecord(tool, 'raw tool'));
  for (const tool of toolList) {
    const inputSchema = requireRecord(tool.inputSchema, 'raw tool inputSchema');
    if (inputSchema.type !== 'object') {
      throw new Error(
        `tool inputSchema was not object-root: ${JSON.stringify(tool)}`
      );
    }
    if (tool.outputSchema !== undefined) {
      const outputSchema = requireRecord(
        tool.outputSchema,
        'raw tool outputSchema'
      );
      if (outputSchema.type !== 'object') {
        throw new Error(
          `tool outputSchema was not object-root: ${JSON.stringify(tool)}`
        );
      }
    }
  }

  const chooseModeTool = toolList.find((tool) => tool.name === 'choose_mode');
  if (!chooseModeTool) {
    throw new Error('raw tools/list missing choose_mode');
  }
  const annotations = requireRecord(
    chooseModeTool.annotations,
    'choose_mode annotations'
  );
  if (annotations.title !== 'Mode chooser') {
    throw new Error(
      `choose_mode title missing: ${JSON.stringify(annotations)}`
    );
  }
  assertNoField(annotations, 'priority', 'choose_mode annotations');
  assertNoField(annotations, 'audience', 'choose_mode annotations');

  const rawResources = (await client.request(
    { method: 'resources/list' } as any,
    z.any()
  )) as unknown;
  const resources = requireArray(
    requireRecord(rawResources, 'raw resources/list result').resources,
    'raw resources/list resources'
  ).map((resource) => requireRecord(resource, 'raw resource'));
  const iconResource = resources.find(
    (resource) => resource.uri === 'resource://legacy-icon'
  );
  if (!iconResource) {
    throw new Error('raw resources/list missing legacy icon resource');
  }
  if (iconResource.title !== 'Legacy Icon Resource Title') {
    throw new Error(`resource title missing: ${JSON.stringify(iconResource)}`);
  }
  assertIconList(iconResource.icons, 'legacy icon resource');
  assertNoField(iconResource, 'icon', 'legacy icon resource');

  const rawPrompts = (await client.request(
    { method: 'prompts/list' } as any,
    z.any()
  )) as unknown;
  const prompts = requireArray(
    requireRecord(rawPrompts, 'raw prompts/list result').prompts,
    'raw prompts/list prompts'
  ).map((prompt) => requireRecord(prompt, 'raw prompt'));
  const iconPrompt = prompts.find(
    (prompt) => prompt.name === 'legacy_icon_prompt'
  );
  if (!iconPrompt) {
    throw new Error('raw prompts/list missing legacy icon prompt');
  }
  assertIconList(iconPrompt.icons, 'legacy icon prompt');
  assertNoField(iconPrompt, 'icon', 'legacy icon prompt');
}

async function main() {
  const args = process.argv.slice(2);
  let transportType = 'stdio';
  let serverCommand = '';
  let serverArgs: string[] = [];
  let url = '';

  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--transport' && i + 1 < args.length) {
      transportType = args[i + 1];
    } else if (args[i] === '--server-command' && i + 1 < args.length) {
      serverCommand = args[i + 1];
    } else if (args[i] === '--server-args' && i + 1 < args.length) {
      serverArgs = args[i + 1].split(' ');
    } else if (args[i] === '--url' && i + 1 < args.length) {
      url = args[i + 1];
    }
  }

  let transport;
  if (transportType === 'stdio') {
    if (!serverCommand) {
      console.error('Error: --server-command is required for stdio transport');
      process.exit(1);
    }
    transport = new StdioClientTransport({
      command: serverCommand,
      args: serverArgs,
    });
  } else if (transportType === 'http') {
    if (!url) {
      console.error('Error: --url is required for http transport');
      process.exit(1);
    }
    transport = new StreamableHttpClientTransport(new URL(url));
  } else {
    console.error(`Unknown transport: ${transportType}`);
    process.exit(1);
  }

  const client = new Client(
    {
      name: 'ts-test-client',
      version: '1.0.0',
    },
    {
      capabilities: {
        roots: {
          listChanged: true,
        },
        sampling: {
          tools: {},
        },
        elicitation: {
          form: {
            applyDefaults: true,
          },
        },
      },
    }
  );

  // Register handlers for server-initiated requests

  // Roots handler - return mock roots
  client.setRequestHandler(ListRootsRequestSchema, async () => {
    return {
      roots: [
        {
          uri: 'file:///home/user/documents',
          name: 'Documents',
          _meta: { source: 'ts-client' },
        },
        { uri: 'file:///home/user/projects', name: 'Projects' },
      ],
    };
  });

  const extractPromptText = (content: unknown): string => {
    if (Array.isArray(content)) {
      const firstTextBlock = content.find((item) => {
        if (typeof item !== 'object' || item === null) {
          return false;
        }

        const maybeBlock = item as { type?: unknown; text?: unknown };
        return (
          maybeBlock.type === 'text' && typeof maybeBlock.text === 'string'
        );
      }) as { text?: string } | undefined;

      if (typeof firstTextBlock?.text === 'string') {
        return firstTextBlock.text;
      }

      return JSON.stringify(content);
    }

    if (typeof content === 'object' && content !== null) {
      const maybeBlock = content as { text?: unknown };
      if (typeof maybeBlock.text === 'string') {
        return maybeBlock.text;
      }
    }

    return 'unknown';
  };

  // Sampling handler - return mock LLM response
  client.setRequestHandler(CreateMessageRequestSchema, async (request) => {
    // Extract the prompt from the request
    const messages = request.params?.messages || [];
    const firstMessage = messages[0];
    const promptText = extractPromptText(firstMessage?.content);

    if (promptText.includes('[multi]')) {
      return {
        model: 'mock-llm-model',
        role: 'assistant' as const,
        content: [
          {
            type: 'text' as const,
            text: `Mock LLM response to: ${promptText}`,
          },
          {
            type: 'text' as const,
            text: 'Mock LLM follow-up block',
          },
        ],
      };
    }

    return {
      model: 'mock-llm-model',
      role: 'assistant' as const,
      content: {
        type: 'text' as const,
        text: `Mock LLM response to: ${promptText}`,
      },
    };
  });

  // Elicitation handler - return mock acceptance
  client.setRequestHandler(ElicitRequestSchema, async () => {
    return {
      action: 'accept' as const,
      content: {
        confirmed: true,
      },
    };
  });

  try {
    await client.connect(transport);

    // 1. List Tools
    const tools = await client.listTools();
    const toolNames = tools.tools.map((t) => t.name);
    if (
      !toolNames.includes('echo') ||
      !toolNames.includes('add') ||
      !toolNames.includes('choose_mode')
    ) {
      throw new Error(`Missing tools. Found: ${toolNames}`);
    }
    assertTitledEnumSchema(tools);
    await assertRawDartServerWireShapes(client);

    // 2. Call Tool 'echo'
    const echoResult = await client.callTool({
      name: 'echo',
      arguments: { message: 'hello from ts' },
    });
    // @ts-expect-error - accessing content array element
    const echoText = echoResult.content[0].text;
    if (echoText !== 'hello from ts') {
      throw new Error(
        `Echo failed. Expected 'hello from ts', got '${echoText}'`
      );
    }

    // 3. Call Tool 'add'
    const addResult = await client.callTool({
      name: 'add',
      arguments: { a: 10, b: 20 },
    });
    // @ts-expect-error - accessing content array element
    const addText = addResult.content[0].text;
    if (addText !== '30' && addText !== 30) {
      throw new Error(`Add failed. Expected '30', got '${addText}'`);
    }

    // 4. Read Resource
    const resourceResult = await client.readResource({
      uri: 'resource://test',
    });
    // @ts-expect-error - accessing contents array element
    const resourceText = resourceResult.contents[0].text;
    if (resourceText !== 'This is a test resource') {
      throw new Error(
        `Read resource failed. Expected 'This is a test resource', got '${resourceText}'`
      );
    }

    // 5. Get Prompt
    const promptResult = await client.getPrompt({
      name: 'test_prompt',
    });
    // @ts-expect-error - accessing messages array element
    const promptText = promptResult.messages[0].content.text;
    if (promptText !== 'Test Prompt') {
      throw new Error(
        `Get prompt failed. Expected 'Test Prompt', got '${promptText}'`
      );
    }

    // 6. Test Tasks (using experimental API)
    console.log('Testing Tasks...');

    // List Tasks
    const listTasksResult = await client.experimental.tasks.listTasks();
    if (!listTasksResult.tasks) {
      throw new Error("tasks/list response missing 'tasks' array");
    }
    listTasksResult.tasks.forEach((task, index) => {
      assertTaskWireShape(task, `tasks/list task ${index}`);
    });
    console.log(`Tasks listed: ${listTasksResult.tasks.length}`);

    // Call delayed_echo using callToolStream
    console.log('Calling delayed_echo with callToolStream...');
    const stream = client.experimental.tasks.callToolStream(
      {
        name: 'delayed_echo',
        arguments: { message: 'task echo', delay: 100 },
      },
      CallToolResultSchema,
      { task: {} }
    );

    let taskRawResult;
    let createdTaskId: string | undefined;
    for await (const message of stream) {
      switch (message.type) {
        case 'taskCreated':
          assertTaskWireShape(message.task, 'taskCreated message task');
          createdTaskId = message.task.taskId;
          console.log(`Task created: ${message.task.taskId}`);
          break;
        case 'taskStatus':
          assertTaskWireShape(message.task, 'taskStatus message task');
          console.log(
            `Task status: ${message.task.status} (${message.task.statusMessage})`
          );
          break;
        case 'result':
          taskRawResult = message.result;
          break;
        case 'error':
          throw new Error(`Task error: ${JSON.stringify(message.error)}`);
      }
    }

    if (!taskRawResult) {
      throw new Error('Did not receive a result from callToolStream');
    }
    if (!createdTaskId) {
      throw new Error('Did not receive a taskCreated message');
    }
    assertRelatedTaskMeta(taskRawResult, createdTaskId, 'tasks/result result');

    // @ts-expect-error - content is a union type, text property not guaranteed
    const resultText = taskRawResult.content?.[0]?.text;
    if (resultText !== 'task echo') {
      throw new Error(
        `Task result mismatch. Expected 'task echo', got '${resultText}'`
      );
    }

    console.log('All basic interop tests passed!');

    // 7. Test new features: roots, sampling, elicitation, completion, progress
    console.log('\nTesting new features...');

    // Test get_roots tool (server lists client roots)
    console.log('Testing get_roots...');
    const rootsResult = await client.callTool({
      name: 'get_roots',
      arguments: {},
    });
    // @ts-expect-error - accessing content array element
    const rootsText = rootsResult.content[0].text;
    const roots = JSON.parse(rootsText);
    if (!Array.isArray(roots) || roots.length !== 2) {
      throw new Error(`get_roots failed. Expected 2 roots, got: ${rootsText}`);
    }
    if (roots[0]?._meta?.source !== 'ts-client') {
      throw new Error(`get_roots did not preserve Root._meta: ${rootsText}`);
    }
    console.log('get_roots passed!');

    // Test sample_llm tool (server requests LLM completion)
    console.log('Testing sample_llm...');
    const sampleResult = await client.callTool({
      name: 'sample_llm',
      arguments: { prompt: 'Hello, world!' },
    });
    // @ts-expect-error - accessing content array element
    const sampleText = sampleResult.content[0].text;
    if (!sampleText.includes('Mock LLM response')) {
      throw new Error(`sample_llm failed. Got: ${sampleText}`);
    }
    console.log('sample_llm passed!');

    // Test sample_llm again to verify repeated sampling requests
    console.log('Testing sample_llm repeat call...');
    const sampleRepeatResult = await client.callTool({
      name: 'sample_llm',
      arguments: { prompt: 'Hello again!' },
    });
    // @ts-expect-error - accessing content array element
    const sampleRepeatText = sampleRepeatResult.content[0].text;
    if (!sampleRepeatText.includes('Mock LLM response')) {
      throw new Error(`sample_llm repeat failed. Got: ${sampleRepeatText}`);
    }
    console.log('sample_llm repeat passed!');

    // Test sample_llm with multi-block sampling response
    console.log('Testing sample_llm multi-block response...');
    const sampleMultiResult = await client.callTool({
      name: 'sample_llm',
      arguments: { prompt: 'Hello [multi] world!' },
    });
    // @ts-expect-error - accessing content array element
    const sampleMultiText = sampleMultiResult.content[0].text;

    let sampleMultiBlocks: unknown;
    try {
      sampleMultiBlocks = JSON.parse(sampleMultiText);
    } catch (error) {
      throw new Error(
        `sample_llm multi-block failed to parse JSON output: ${error}`
      );
    }

    if (!Array.isArray(sampleMultiBlocks) || sampleMultiBlocks.length < 2) {
      throw new Error(
        `sample_llm multi-block failed. Expected at least 2 blocks, got: ${sampleMultiText}`
      );
    }

    const firstBlock = sampleMultiBlocks[0] as { type?: string; text?: string };
    const secondBlock = sampleMultiBlocks[1] as {
      type?: string;
      text?: string;
    };

    if (firstBlock.type !== 'text' || secondBlock.type !== 'text') {
      throw new Error(
        `sample_llm multi-block returned unexpected block types: ${sampleMultiText}`
      );
    }

    if (
      !firstBlock.text?.includes('Mock LLM response') ||
      secondBlock.text !== 'Mock LLM follow-up block'
    ) {
      throw new Error(
        `sample_llm multi-block returned unexpected text: ${sampleMultiText}`
      );
    }
    console.log('sample_llm multi-block passed!');

    // Test elicit_input tool (server requests user input)
    console.log('Testing elicit_input...');
    const elicitResult = await client.callTool({
      name: 'elicit_input',
      arguments: { message: 'Please confirm' },
    });
    // @ts-expect-error - accessing content array element
    const elicitText = elicitResult.content[0].text;
    const elicitParsed = JSON.parse(elicitText);
    if (elicitParsed.action !== 'accept') {
      throw new Error(`elicit_input failed. Got: ${elicitText}`);
    }
    console.log('elicit_input passed!');

    // Test completion API
    console.log('Testing completion...');
    const completionResult = await client.complete({
      ref: {
        type: 'ref/prompt',
        name: 'greeting',
      },
      argument: {
        name: 'language',
        value: 'En',
      },
    });
    if (!completionResult.completion.values.includes('English')) {
      throw new Error(
        `completion failed. Expected 'English' in values, got: ${completionResult.completion.values}`
      );
    }
    console.log('completion passed!');

    // Test progress_demo tool
    console.log('Testing progress_demo...');
    const progressUpdates: number[] = [];
    const progressResult = await client.callTool(
      {
        name: 'progress_demo',
        arguments: { steps: 4 },
      },
      undefined,
      {
        onprogress: (progress: Progress) => {
          if (progress.progress !== undefined) {
            progressUpdates.push(progress.progress);
          }
        },
      }
    );
    // @ts-expect-error - accessing content array element
    const progressText = progressResult.content[0].text;
    if (!progressText.includes('Completed')) {
      throw new Error(`progress_demo failed. Got: ${progressText}`);
    }
    console.log(
      `progress_demo passed! Received ${progressUpdates.length} progress updates`
    );

    console.log('\nAll interop tests passed!');
    process.exit(0);
  } catch (error) {
    console.error('Interop test failed:', error);
    process.exit(1);
  }
}

main();
