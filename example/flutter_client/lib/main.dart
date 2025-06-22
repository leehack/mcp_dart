import 'dart:developer' as dev;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:mcp_dart/mcp_dart.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    dev.log('Warning: Could not load .env file: $e');
  }

  runApp(const McpCrossPlatformDemo());
}

class McpCrossPlatformDemo extends StatelessWidget {
  const McpCrossPlatformDemo({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MCP Dart Cross-Platform Demo',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const McpClientPage(),
    );
  }
}

class McpClientPage extends StatefulWidget {
  const McpClientPage({super.key});

  @override
  State<McpClientPage> createState() => _McpClientPageState();
}

class _McpClientPageState extends State<McpClientPage> {
  Client? _client;
  StreamableHttpClientTransport? _transport;

  final TextEditingController _serverUrlController = TextEditingController(
    text: 'https://api.example.com/mcp',
  );
  final ScrollController _scrollController = ScrollController();

  final List<String> _messages = [];
  bool _isConnected = false;
  bool _isConnecting = false;

  @override
  void initState() {
    super.initState();
    _addMessage("🚀 MCP Dart client works on ALL platforms!");
    _addMessage("✅ VM • Mobile • Desktop • Web - same code!");
    if (kIsWeb) {
      _addMessage("🌐 Web mode: Some servers may be blocked by CORS policy");
      _addMessage("💡 Tip: Check Chrome Dev Console (F12) for detailed errors");
    }
  }

  void _addMessage(String message) {
    setState(() {
      _messages.add(message);
    });

    // Auto-scroll to bottom to show newest message
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _connect() async {
    if (_isConnecting) return;

    setState(() => _isConnecting = true);

    try {
      final serverUrl = _serverUrlController.text.trim();

      // Validate URL format before attempting to parse
      if (serverUrl.isEmpty) {
        throw Exception("Server URL cannot be empty");
      }

      // Check if it looks like just a base64 string (common mistake with Zapier URLs)
      if (!serverUrl.startsWith('http') && serverUrl.length > 50) {
        throw Exception(
            "Invalid URL format. Please use the full URL starting with https://\nExample: https://mcp.zapier.com/api/mcp/s/YOUR_TOKEN_HERE");
      }

      final parsedUri = Uri.parse(serverUrl);
      if (!parsedUri.hasScheme || parsedUri.host.isEmpty) {
        throw Exception(
            "Invalid URL: must include scheme (https://) and host\nExample: https://mcp.zapier.com/api/mcp/s/YOUR_TOKEN");
      }

      _addMessage("🔌 Connecting to: $serverUrl");

      // Create the MCP Client with capabilities
      _client = Client(
        const Implementation(name: "flutter-demo", version: "1.0.0"),
        options: const ClientOptions(
          capabilities: ClientCapabilities(
            roots: ClientCapabilitiesRoots(listChanged: true),
            sampling: {},
          ),
        ),
      );

      // This transport works on ALL Dart platforms!
      _transport = StreamableHttpClientTransport(
        parsedUri,
        opts: const StreamableHttpClientTransportOptions(
          reconnectionOptions: StreamableHttpReconnectionOptions(
            initialReconnectionDelay: 1000,
            maxReconnectionDelay: 30000,
            reconnectionDelayGrowFactor: 1.5,
            maxRetries: 3,
          ),
        ),
      );

      // Set up event handlers
      _transport!.onmessage = (message) {
        _addMessage("📥 Received: ${message.runtimeType}");
      };

      _transport!.onerror = (error) {
        _addMessage("❌ Error: $error");
        if (kIsWeb) {
          _addMessage(
              "🔍 For detailed error info, open Chrome Dev Console (F12)");
        }
      };

      _transport!.onclose = () {
        _addMessage("🔌 Connection closed");
        setState(() => _isConnected = false);
      };

      // Connect the client - this handles initialization automatically
      await _client!.connect(_transport!);

      setState(() => _isConnected = true);
      _addMessage("✅ Connected! MCP Client initialized successfully!");

      // Show server info
      final serverInfo = _client!.getServerVersion();
      final serverCaps = _client!.getServerCapabilities();
      if (serverInfo != null) {
        _addMessage("🖥️ Server: ${serverInfo.name} v${serverInfo.version}");
      }
      if (serverCaps != null) {
        final caps = [];
        if (serverCaps.tools != null) caps.add("tools");
        if (serverCaps.resources != null) caps.add("resources");
        if (serverCaps.prompts != null) caps.add("prompts");
        if (caps.isNotEmpty) {
          _addMessage("🎯 Server capabilities: ${caps.join(', ')}");
        }
      }
    } catch (e) {
      _addMessage("❌ Connect failed: $e");
      setState(() => _isConnected = false);
    } finally {
      setState(() => _isConnecting = false);
    }
  }

  Future<void> _disconnect() async {
    await _client?.close();
    _client = null;
    _transport = null;
    setState(() => _isConnected = false);
    _addMessage("🔌 Disconnected");
  }

  Future<void> _testMessage() async {
    if (!_isConnected || _client == null) return;
    try {
      _addMessage("📤 Sending ping request using Client...");
      await _client!.ping();
      _addMessage("✅ Ping successful!");

      // Try to list available tools
      try {
        _addMessage("📤 Listing available tools...");
        final toolsResult = await _client!.listTools();
        _addMessage("🔧 Found ${toolsResult.tools.length} tools");
        for (final tool in toolsResult.tools) {
          _addMessage("  • ${tool.name}: ${tool.description}");
        }
      } catch (e) {
        _addMessage("⚠️ List tools failed (server may not support): $e");
      }
    } catch (e) {
      _addMessage("❌ Test failed: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('MCP Dart - Cross Platform Demo')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Connection Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      '🌐 MCP Server Connection',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _serverUrlController,
                      decoration: const InputDecoration(
                        labelText: 'Server URL',
                        border: OutlineInputBorder(),
                        hintText: 'https://example.com/mcp',
                      ),
                      enabled: !_isConnected && !_isConnecting,
                    ),
                    const SizedBox(height: 8),
                    // Quick preset buttons
                    Wrap(
                      spacing: 8,
                      children: [
                        ElevatedButton(
                          onPressed: _isConnected || _isConnecting
                              ? null
                              : () {
                                  _serverUrlController.text =
                                      'https://huggingface.co/mcp';
                                },
                          child: const Text('🤗 HF'),
                        ),
                        ElevatedButton(
                          onPressed: _isConnected || _isConnecting
                              ? null
                              : () {
                                  final zapierUrl =
                                      dotenv.env['ZAPIER_MCP_URL'] ?? '';
                                  if (zapierUrl.isEmpty) {
                                    _addMessage(
                                        '❌ ZAPIER_MCP_URL not configured in .env file');
                                    _addMessage(
                                        '🔧 First set up a "MCP CLI Proxy MCP Server" on Zapier (https://mcp.zapier.com/)');
                                    _addMessage(
                                        '📋 You want the Server URL for Streamable HTTP');
                                    _addMessage(
                                        '💾 Then add ZAPIER_MCP_URL=your_url_here to your .env file');
                                  } else {
                                    _serverUrlController.text = zapierUrl;
                                  }
                                },
                          child: const Text('⚡ Zapier'),
                        ),
                        ElevatedButton(
                          onPressed: _isConnected || _isConnecting
                              ? null
                              : () {
                                  _serverUrlController.text =
                                      'https://mcp.deepwiki.com/mcp';
                                },
                          child: const Text('📚 DeepWiki'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed:
                              _isConnected || _isConnecting ? null : _connect,
                          icon: _isConnecting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.connect_without_contact),
                          label: Text(
                            _isConnecting ? 'Connecting...' : 'Connect',
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: _isConnected ? _disconnect : null,
                          icon: const Icon(Icons.close),
                          label: const Text('Disconnect'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: _isConnected ? _testMessage : null,
                          icon: const Icon(Icons.send),
                          label: const Text('Test Client'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Messages
            Expanded(
              child: Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text(
                        '📝 Messages',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Expanded(
                      child: _messages.isEmpty
                          ? const Center(child: Text('No messages yet'))
                          : ListView.builder(
                              controller: _scrollController,
                              itemCount: _messages.length,
                              itemBuilder: (context, index) => ListTile(
                                dense: true,
                                title: Text(
                                  _messages[index],
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.all(16),
              child: const Text(
                '🎉 MCP Dart Client works on ALL platforms!\n'
                '✅ Uses high-level Client class with automatic initialization\n'
                '🚀 Same code: VM • Mobile • Desktop • Web - zero platform code!',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    _scrollController.dispose();
    _disconnect();
    super.dispose();
  }
}
