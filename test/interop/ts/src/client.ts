import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';
import { StreamableHttpClientTransport } from './streamable_client_transport.js';
import {
  CallToolResultSchema,
  ListRootsRequestSchema,
  CreateMessageRequestSchema,
  ElicitRequestSchema,
  Progress,
} from '@modelcontextprotocol/sdk/types.js';

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
        sampling: {},
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
        { uri: 'file:///home/user/documents', name: 'Documents' },
        { uri: 'file:///home/user/projects', name: 'Projects' },
      ],
    };
  });

  // Sampling handler - return mock LLM response
  client.setRequestHandler(CreateMessageRequestSchema, async (request) => {
    // Extract the prompt from the request
    const messages = request.params?.messages || [];
    const firstMessage = messages[0];
    let promptText = 'unknown';
    if (firstMessage?.content) {
      const content = firstMessage.content;
      if (typeof content === 'object' && 'text' in content) {
        promptText = content.text as string;
      }
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
    if (!toolNames.includes('echo') || !toolNames.includes('add')) {
      throw new Error(`Missing tools. Found: ${toolNames}`);
    }

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
    for await (const message of stream) {
      switch (message.type) {
        case 'taskCreated':
          console.log(`Task created: ${message.task.taskId}`);
          break;
        case 'taskStatus':
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
    console.log(`progress_demo passed! Received ${progressUpdates.length} progress updates`);

    console.log('\nAll interop tests passed!');
    process.exit(0);
  } catch (error) {
    console.error('Interop test failed:', error);
    process.exit(1);
  }
}

main();
