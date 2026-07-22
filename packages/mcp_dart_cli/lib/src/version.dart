const packageVersion = '0.2.0-dev.3';

/// SDK constraint written by this CLI when it creates a project.
const generatedSdkConstraint = '^2.3.0-dev.3';

/// Immutable template paired with this CLI release.
const defaultTemplateUrl =
    'https://github.com/leehack/mcp_dart/tree/'
    'mcp_dart_cli-v$packageVersion/packages/templates/simple';

/// Whether [version] identifies a prerelease build.
bool isPrereleaseVersion(String version) =>
    version.split('+').first.contains('-');
