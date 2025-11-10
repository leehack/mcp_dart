/// Example: Connecting to GitHub MCP Server with Personal Access Token (PAT)
///
/// This example demonstrates a simpler authentication method using GitHub PAT
/// instead of OAuth, which is easier for testing and personal use.
///
/// ⚠️ SECURITY WARNING:
/// - Never commit your PAT to version control
/// - Use environment variables or secure storage
/// - Rotate your PAT regularly
/// - Use minimal scopes
///
/// Setup:
/// 1. Create a GitHub PAT at https://github.com/settings/tokens
/// 2. Select scopes: repo, read:packages, read:org
/// 3. Set environment variable or pass as argument
///
/// Run:
/// export GITHUB_TOKEN=your_pat_here
/// dart run example/authentication/github_pat_example.dart
library;

import 'dart:io';
import 'package:mcp_dart/mcp_dart.dart';

/// Simple PAT-based authentication provider
class GitHubPATAuthProvider implements OAuthClientProvider {
  final String personalAccessToken;

  GitHubPATAuthProvider(this.personalAccessToken);

  @override
  Future<OAuthTokens?> tokens() async {
    // GitHub PAT is used directly as the access token
    return OAuthTokens(accessToken: personalAccessToken);
  }

  @override
  Future<void> redirectToAuthorization() async {
    throw UnauthorizedError(
      'PAT authentication failed. Please check your token.\n'
      'Create a new token at: https://github.com/settings/tokens',
    );
  }
}

Future<void> main(List<String> args) async {
  print('=' * 70);
  print('GitHub MCP Server - Personal Access Token Example');
  print('=' * 70);
  print('');

  // Get PAT from environment or command line argument
  String? githubToken;

  if (args.isNotEmpty) {
    githubToken = args[0];
    print('✓ Using token from command line argument');
  } else {
    githubToken = Platform.environment['GITHUB_TOKEN'];
    if (githubToken != null) {
      print('✓ Using token from GITHUB_TOKEN environment variable');
    }
  }

  if (githubToken == null || githubToken.isEmpty) {
    print('❌ Error: GitHub Personal Access Token not found!');
    print('');
    print('Please provide your token using one of these methods:');
    print('');
    print('Method 1 - Environment Variable (Recommended):');
    print('  export GITHUB_TOKEN=your_token_here');
    print('  dart run example/authentication/github_pat_example.dart');
    print('');
    print('Method 2 - Command Line Argument:');
    print('  dart run example/authentication/github_pat_example.dart your_token_here');
    print('');
    print('To create a GitHub PAT:');
    print('  1. Visit: https://github.com/settings/tokens');
    print('  2. Click "Generate new token (classic)"');
    print('  3. Select scopes: repo, read:packages, read:org');
    print('  4. Copy the generated token');
    print('');
    exit(1);
  }

  // Create MCP client
  final client = Client(
    Implementation(name: 'github-mcp-pat-client', version: '1.0.0'),
  );

  try {
    print('');
    print('Connecting to GitHub MCP server...');

    // Create transport with PAT authentication
    final transport = StreamableHttpClientTransport(
      Uri.parse('https://api.githubcopilot.com/mcp/'),
      opts: StreamableHttpClientTransportOptions(
        authProvider: GitHubPATAuthProvider(githubToken),
      ),
    );

    // Connect to GitHub MCP server
    await client.connect(transport);

    print('✓ Connected successfully!\n');
    print('Server Information:');
    print('  Name: ${client.getServerVersion()?.name ?? 'Unknown'}');
    print('  Version: ${client.getServerVersion()?.version ?? 'Unknown'}');

    // Get server instructions if available
    final instructions = client.getInstructions();
    if (instructions != null) {
      print('  Instructions: $instructions');
    }

    print('');
    print('-' * 70);
    print('Available Capabilities:');
    print('-' * 70);

    final capabilities = client.getServerCapabilities();
    if (capabilities != null) {
      if (capabilities.tools != null) {
        print('✓ Tools: Supported');
      }
      if (capabilities.resources != null) {
        print('✓ Resources: Supported');
      }
      if (capabilities.prompts != null) {
        print('✓ Prompts: Supported');
      }
      if (capabilities.logging != null) {
        print('✓ Logging: Supported');
      }
    }

    print('');
    print('-' * 70);
    print('Listing Available Tools:');
    print('-' * 70);

    // List available tools
    try {
      final toolsResult = await client.listTools();
      print('');
      print('Found ${toolsResult.tools.length} tools:');
      print('');

      for (final tool in toolsResult.tools) {
        print('📦 ${tool.name}');
        if (tool.description != null && tool.description!.isNotEmpty) {
          final description = tool.description!;
          // Wrap long descriptions
          if (description.length > 70) {
            print('   ${description.substring(0, 67)}...');
          } else {
            print('   $description');
          }
        }
        print('');
      }
    } catch (e) {
      print('⚠️  Could not list tools: $e');
    }

    print('-' * 70);
    print('Connection Test Complete!');
    print('-' * 70);
    print('');
    print('✅ GitHub MCP server is working correctly with your PAT');
    print('');
    print('Next steps:');
    print('  • Use client.callTool() to invoke GitHub operations');
    print('  • Use client.listResources() to see available resources');
    print('  • Use client.listPrompts() to see available prompts');
    print('');

    // Close connection
    await client.close();
    print('✓ Connection closed');
  } catch (e) {
    print('');
    print('❌ Connection failed!');
    print('');
    print('Error: $e');
    print('');

    if (e.toString().contains('401') || e.toString().contains('Unauthorized')) {
      print('This appears to be an authentication error.');
      print('');
      print('Troubleshooting:');
      print('  1. Verify your token is correct');
      print('  2. Check token has required scopes: repo, read:packages, read:org');
      print('  3. Ensure token has not expired');
      print('  4. Create a new token at: https://github.com/settings/tokens');
    } else if (e.toString().contains('404') || e.toString().contains('Not Found')) {
      print('The GitHub MCP server endpoint may not be available.');
      print('Verify the URL: https://api.githubcopilot.com/mcp/');
    } else if (e.toString().contains('network') || e.toString().contains('connection')) {
      print('Network connection issue. Check your internet connection.');
    }

    print('');
    exit(1);
  }
}
