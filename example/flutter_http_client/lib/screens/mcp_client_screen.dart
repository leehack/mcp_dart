import 'package:flutter/material.dart';
import 'package:flutter_http_client/services/streamable_mcp_service.dart';

class McpClientScreen extends StatefulWidget {
  final StreamableMcpService mcpService;

  const McpClientScreen({super.key, required this.mcpService});

  @override
  McpClientScreenState createState() => McpClientScreenState();
}

class McpClientScreenState extends State<McpClientScreen> {
  final _scrollController = ScrollController();
  final _inputController = TextEditingController();

  String _responseText = '';
  bool _isLoading = false;
  String? _selectedTool;
  String _selectedPrompt = '';

  @override
  void initState() {
    super.initState();

    // Set default response text
    _responseText =
        'Welcome to the MCP Client.\nClick Connect to connect to the server.';

    // Initialize default tools with empty list
    if (widget.mcpService.availableTools == null && _selectedTool == null) {
      _selectedTool = null;
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _inputController.dispose();
    super.dispose();
  }

  Widget _buildCommandButton(
    String label,
    VoidCallback onPressed, {
    bool requiresConnection = true,
    ButtonStyle? style,
  }) {
    return ElevatedButton(
      onPressed:
          (!requiresConnection || widget.mcpService.isConnected)
              ? onPressed
              : null,
      style:
          style ?? ElevatedButton.styleFrom(minimumSize: const Size(120, 40)),
      child: Text(label),
    );
  }

  void _showLoading(bool isLoading) {
    setState(() {
      _isLoading = isLoading;
    });
  }

  void _setResponse(String text) {
    setState(() {
      _responseText = text;
    });
  }

  // Connect to the MCP server
  Future<void> _connect() async {
    _showLoading(true);
    try {
      final result = await widget.mcpService.connect();
      _setResponse(
        result
            ? 'Connected to MCP server'
            : 'Failed to connect: ${widget.mcpService.connectionError}',
      );
    } catch (e) {
      _setResponse('Error connecting: $e');

      // Show detailed error dialog for connection failures
      await _showErrorDialog(
        'Connection Failed',
        'Failed to connect to the MCP server.\n\nPlease check:\n'
            '• Server is running\n'
            '• URL is correct\n'
            '• Network connection is stable',
        error: e,
      );
    } finally {
      _showLoading(false);
    }
  }

  // Disconnect from the MCP server
  Future<void> _disconnect() async {
    _showLoading(true);
    try {
      await widget.mcpService.disconnect();
      _setResponse('Disconnected from server');
    } catch (e) {
      _setResponse('Error disconnecting: $e');
    } finally {
      _showLoading(false);
    }
  }

  // Terminate the session
  Future<void> _terminateSession() async {
    _showLoading(true);
    try {
      await widget.mcpService.terminateSession();
      _setResponse('Session terminated');
    } catch (e) {
      _setResponse('Error terminating session: $e');
    } finally {
      _showLoading(false);
    }
  }

  // Reconnect to the server
  Future<void> _reconnect() async {
    _showLoading(true);
    try {
      final result = await widget.mcpService.reconnect();
      _setResponse(
        result
            ? 'Reconnected to server'
            : 'Failed to reconnect: ${widget.mcpService.connectionError}',
      );
    } catch (e) {
      _setResponse('Error reconnecting: $e');
    } finally {
      _showLoading(false);
    }
  }

  // List available tools
  Future<void> _listTools() async {
    _showLoading(true);
    try {
      await widget.mcpService.listTools();
      final tools = widget.mcpService.availableTools;

      if (tools == null || tools.isEmpty) {
        _setResponse('No tools available');
      } else {
        final toolsText = tools
            .map((t) => '- ${t.name}: ${t.description}')
            .join('\n');
        _setResponse('Available tools:\n$toolsText');

        // Set default tool if none is selected
        if (_selectedTool == null && tools.isNotEmpty) {
          // Check for common tools or use the first one
          final commonTools = ['greet', 'echo', 'multi-greet'];
          final commonTool = tools.firstWhere(
            (t) => commonTools.contains(t.name),
            orElse: () => tools.first,
          );

          setState(() {
            _selectedTool = commonTool.name;
          });
        }
      }
    } catch (e) {
      _setResponse('Error listing tools: $e');
    } finally {
      _showLoading(false);
    }
  }

  // Call the selected tool
  Future<void> _callTool() async {
    if (_selectedTool == null) {
      _setResponse('Please select a tool first');
      return;
    }

    _showLoading(true);

    try {
      // Parse arguments based on the selected tool
      Map<String, dynamic> args = {};
      final inputText = _inputController.text.trim();

      if (_selectedTool == 'greet') {
        // For greet tool, the input is the name
        args = {'name': inputText.isEmpty ? 'MCP User' : inputText};
      } else if (_selectedTool == 'multi-greet') {
        // For multi-greet, same as greet
        args = {'name': inputText.isEmpty ? 'MCP User' : inputText};
      } else {
        // For other tools, basic text input
        args = {'text': inputText};
      }

      // Call the tool
      final result = await widget.mcpService.callTool(_selectedTool!, args);

      // Display the result
      if (result == null) {
        _setResponse('No response from tool');
      } else {
        try {
          final content = result.content?.first;
          if (content?.text != null) {
            _setResponse(content?.text ?? '');
          } else {
            _setResponse('Received response: $result');
          }
        } catch (e) {
          _setResponse('Error parsing result: $e\nRaw: $result');
        }
      }
    } catch (e) {
      _setResponse('Error calling tool: $e');

      // Show detailed error dialog for tool failures
      await _showErrorDialog(
        'Tool Execution Failed',
        'Failed to execute $_selectedTool.\n\nThis could indicate a connection issue or a problem with the tool implementation.',
        error: e,
      );
    } finally {
      _showLoading(false);
    }
  }

  // List available prompts
  Future<void> _listPrompts() async {
    _showLoading(true);
    try {
      await widget.mcpService.listPrompts();
      final prompts = widget.mcpService.availablePrompts;

      if (prompts == null || prompts.isEmpty) {
        _setResponse('No prompts available');
      } else {
        final promptsText = prompts
            .map((p) => '- ${p.name}: ${p.description}')
            .join('\n');
        _setResponse('Available prompts:\n$promptsText');

        // Update dropdown with first prompt
        if (prompts.isNotEmpty) {
          setState(() {
            _selectedPrompt = prompts.first.name;
          });
        }
      }
    } catch (e) {
      _setResponse('Error listing prompts: $e');
    } finally {
      _showLoading(false);
    }
  }

  // Get a prompt
  Future<void> _getPrompt() async {
    if (_selectedPrompt.isEmpty) {
      _setResponse('No prompt selected. Use List Prompts first.');
      return;
    }

    _showLoading(true);
    try {
      final inputText = _inputController.text.trim();
      final args = {'text': inputText};

      final result = await widget.mcpService.getPrompt(_selectedPrompt, args);

      if (result == null) {
        _setResponse('No response for prompt: $_selectedPrompt');
      } else {
        final messages = result.messages;
        if (messages == null || messages.isEmpty) {
          _setResponse('No messages in prompt response');
        } else {
          final buffer = StringBuffer('Prompt template:\n');
          for (int i = 0; i < messages.length; i++) {
            final msg = messages[i];
            if (msg.content?.text != null) {
              buffer.write('[${i + 1}] ${msg.role}: ${msg.content?.text}\n');
            } else {
              buffer.write('[${i + 1}] ${msg.role}: [Non-text content]\n');
            }
          }
          _setResponse(buffer.toString());
        }
      }
    } catch (e) {
      _setResponse('Error getting prompt: $e');
    } finally {
      _showLoading(false);
    }
  }

  // List available resources
  Future<void> _listResources() async {
    _showLoading(true);
    try {
      await widget.mcpService.listResources();
      final resources = widget.mcpService.availableResources;

      if (resources == null || resources.isEmpty) {
        _setResponse('No resources available');
      } else {
        final resourcesText = resources
            .map((r) => '- ${r.name}: ${r.uri}')
            .join('\n');
        _setResponse('Available resources:\n$resourcesText');
      }
    } catch (e) {
      _setResponse('Error listing resources: $e');
    } finally {
      _showLoading(false);
    }
  }

  // Clear notifications and reset counters
  void _clearNotifications() {
    setState(() {
      widget.mcpService.notifications.clear();

      // Reset the notification counter in the service
      try {
        (widget.mcpService as dynamic)._notificationCount = 0;
      } catch (_) {
        // Ignore if the field is not accessible
      }

      widget.mcpService
          .refresh(); // Use refresh method instead of directly calling notifyListeners
    });
  }

  // Method removed (web-specific functionality)

  // Show server configuration dialog
  void _showServerConfigDialog() {
    final serverController = TextEditingController(
      text: widget.mcpService.serverUrl,
    );

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Server Configuration'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: serverController,
                  decoration: const InputDecoration(
                    labelText: 'Server URL',
                    hintText: 'e.g., http://10.0.2.2:3000/mcp',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Note: For physical devices, use the actual IP address instead of localhost. '
                  'For Android emulators, use 10.0.2.2 instead of localhost.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  final newUrl = serverController.text.trim();
                  if (newUrl.isNotEmpty) {
                    widget.mcpService.updateServerUrl(newUrl);
                    _setResponse('Server URL updated to: $newUrl');
                  }
                  Navigator.pop(context);
                },
                child: const Text('Update'),
              ),
            ],
          ),
    );
  }

  // Show an error dialog with detailed information
  Future<void> _showErrorDialog(
    String title,
    String message, {
    Object? error,
  }) async {
    final errorDetails = error != null ? '\n\nError details: $error' : '';

    await showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(title),
            content: SingleChildScrollView(
              child: Text('$message$errorDetails'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Dismiss'),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MCP Client'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _showServerConfigDialog,
            tooltip: 'Configure Server',
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Chip(
              label: Text(
                widget.mcpService.isConnected ? 'Connected' : 'Disconnected',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              backgroundColor:
                  widget.mcpService.isConnected ? Colors.green : Colors.red,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Command buttons
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Wrap(
                spacing: 8.0,
                runSpacing: 8.0,
                children: [
                  _buildCommandButton(
                    'Connect',
                    _connect,
                    requiresConnection: false,
                  ),
                  _buildCommandButton('Disconnect', _disconnect),
                  _buildCommandButton('Terminate Session', _terminateSession),
                  _buildCommandButton(
                    'Reconnect',
                    _reconnect,
                    requiresConnection: false,
                  ),
                  _buildCommandButton('List Tools', _listTools),
                  _buildCommandButton('List Prompts', _listPrompts),
                  _buildCommandButton('List Resources', _listResources),
                  _buildCommandButton(
                    'Clear Notifications',
                    _clearNotifications,
                    requiresConnection: false,
                  ),
                ],
              ),
            ),

            // Tool selection area
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Builder(
                      builder: (context) {
                        final availableTools = <DropdownMenuItem<String>>[];

                        // Only add items if connected and tools are available
                        if (widget.mcpService.isConnected &&
                            widget.mcpService.availableTools != null &&
                            widget.mcpService.availableTools!.isNotEmpty) {
                          // Map all available tools from the service to dropdown items
                          availableTools.addAll(
                            widget.mcpService.availableTools!.map(
                              (t) => DropdownMenuItem(
                                value: t.name,
                                child: Text(t.name),
                              ),
                            ),
                          );
                        }

                        // Make sure there's a valid selection or reset to null
                        if (_selectedTool != null &&
                            !availableTools.any(
                              (item) => item.value == _selectedTool,
                            )) {
                          _selectedTool = null;
                        }

                        return DropdownButtonFormField<String>(
                          decoration: const InputDecoration(
                            labelText: 'Tool',
                            border: OutlineInputBorder(),
                          ),
                          initialValue: _selectedTool,
                          items: availableTools,
                          onChanged:
                              widget.mcpService.isConnected
                                  ? (value) {
                                    if (value != null) {
                                      setState(() {
                                        _selectedTool = value;
                                      });
                                    }
                                  }
                                  : null,
                          hint: const Text('Select a tool'),
                          isExpanded: true,
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: OutlinedButton(
                      onPressed:
                          widget.mcpService.isConnected ? _callTool : null,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(120, 58),
                      ),
                      child: const Text('Call Tool'),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Prompt selection area (if prompts are available)
            if (widget.mcpService.availablePrompts != null &&
                widget.mcpService.availablePrompts!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<String>(
                        decoration: const InputDecoration(
                          labelText: 'Prompt',
                          border: OutlineInputBorder(),
                        ),
                        initialValue:
                            _selectedPrompt.isEmpty &&
                                    widget
                                        .mcpService
                                        .availablePrompts!
                                        .isNotEmpty
                                ? widget.mcpService.availablePrompts!.first.name
                                : _selectedPrompt,
                        items:
                            widget.mcpService.availablePrompts!
                                .map(
                                  (p) => DropdownMenuItem(
                                    value: p.name,
                                    child: Text(p.name),
                                  ),
                                )
                                .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              _selectedPrompt = value;
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: OutlinedButton(
                        onPressed:
                            widget.mcpService.isConnected ? _getPrompt : null,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(120, 58),
                        ),
                        child: const Text('Get Prompt'),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 16),

            // Input field
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: TextField(
                controller: _inputController,
                decoration: InputDecoration(
                  labelText:
                      _selectedTool == 'greet' || _selectedTool == 'multi-greet'
                          ? 'Enter name (e.g. MCP User)'
                          : 'Enter input text',
                  border: const OutlineInputBorder(),
                  hintText: 'Input arguments for tool or prompt',
                ),
                enabled: widget.mcpService.isConnected,
              ),
            ),

            const SizedBox(height: 16),

            // Response area
            Expanded(
              flex: 2,
              child: Container(
                padding: const EdgeInsets.all(16.0),
                margin: const EdgeInsets.symmetric(horizontal: 16.0),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8.0),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Response:',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: Stack(
                        children: [
                          if (_isLoading)
                            const Center(child: CircularProgressIndicator())
                          else
                            SingleChildScrollView(
                              controller: _scrollController,
                              child: SelectableText(_responseText),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Notifications area
            Expanded(
              flex: 1,
              child: Container(
                padding: const EdgeInsets.all(16.0),
                margin: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8.0),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            'Notifications (${widget.mcpService.notifications.length}):',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.clear_all, size: 20),
                          tooltip: 'Clear notifications',
                          onPressed: _clearNotifications,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Expanded(
                      child: ListView.builder(
                        itemCount: widget.mcpService.notifications.length,
                        reverse: true, // Show newest notifications first
                        itemBuilder: (context, index) {
                          final notification =
                              widget.mcpService.notifications[widget
                                      .mcpService
                                      .notifications
                                      .length -
                                  1 -
                                  index];

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(
                                color:
                                    notification.level.contains('error')
                                        ? Colors.red
                                        : notification.level.contains('warn')
                                        ? Colors.orange
                                        : Colors.grey.shade300,
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      '#${notification.count}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      notification.formattedTimestamp,
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color:
                                            notification.level.contains('error')
                                                ? Colors.red
                                                : notification.level.contains(
                                                  'warn',
                                                )
                                                ? Colors.orange
                                                : notification.level.contains(
                                                  'info',
                                                )
                                                ? Colors.blue
                                                : Colors.grey,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        notification.level,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  notification.message,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
