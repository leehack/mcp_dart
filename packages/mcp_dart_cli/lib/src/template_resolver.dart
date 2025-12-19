import 'dart:io';

import 'package:mason/mason.dart';

/// Represents the resolved location of a template.
class TemplateLocation {
  final String? path;
  final String? gitUrl;
  final String? gitRef;
  final String? gitPath;

  const TemplateLocation({
    this.path,
    this.gitUrl,
    this.gitRef,
    this.gitPath,
  });

  /// Converts this location to a [Brick].
  Brick toBrick() {
    if (path != null) {
      return Brick.path(path!);
    }
    if (gitUrl != null) {
      return Brick.git(
        GitPath(
          gitUrl!,
          ref: gitRef,
          path: gitPath,
        ),
      );
    }
    throw StateError(
        'Invalid TemplateLocation: neither path nor gitUrl provided');
  }
}

/// A class responsible for resolving a [Brick] from a template argument.
///
/// The template argument can be:
/// - A local path
/// - A Git URL (url.git#ref:path)
/// - A GitHub tree URL (https://github.com/User/Repo/tree/Ref/Path)
/// - A GitHub short syntax (User/Repo/path/to/brick@ref)
class TemplateResolver {
  const TemplateResolver();

  /// Resolves the [template] string into a [TemplateLocation].
  TemplateLocation resolve(String template) {
    // 1. Check if it's a local path
    if (FileSystemEntity.typeSync(template) != FileSystemEntityType.notFound) {
      return TemplateLocation(path: template);
    }

    // 2. Parse Git URL syntax: url#ref:path or url.git#ref:path
    // If it contains a #, we treat it as an explicit git reference.
    if (template.contains('#')) {
      return _parseGitSyntax(template);
    }

    // 3. Parse GitHub Tree URL: https://github.com/User/Repo/tree/Ref/Path
    if (template.contains('github.com') && template.contains('/tree/')) {
      return _parseGitHubTree(template);
    }

    // 4. Parse GitHub Short Syntax: owner/repo/path/to/brick@ref
    // Heuristic: Must have at least one slash, no scheme (http/s), no .git
    if (!template.contains(':') &&
        !template.startsWith('/') &&
        !template.startsWith('.') &&
        template.contains('/')) {
      return _parseGitHubShortSyntax(template);
    }

    // Fallback: Treat as a Git URL (assuming root of repo)
    return TemplateLocation(gitUrl: template);
  }

  TemplateLocation _parseGitSyntax(String template) {
    // Syntax: url[?|.git]#ref[:path]
    var url = template;
    String? ref;
    String? path;

    if (template.contains('#')) {
      final parts = template.split('#');
      url = parts[0];
      final remainder = parts[1];

      final refParts = remainder.split(':');
      ref = refParts[0];
      if (refParts.length > 1) {
        path = refParts.sublist(1).join(':');
      }
    }

    return TemplateLocation(gitUrl: url, gitRef: ref, gitPath: path);
  }

  TemplateLocation _parseGitHubTree(String template) {
    // Format: https://github.com/User/Repo/tree/Ref/Path/To/Brick
    // Strategy: Split by '/tree/'.
    // Part 1: https://github.com/User/Repo
    // Part 2: Ref/Path/To/Brick
    // Ambiguity: "Ref" can contain slashes (e.g. feature/foo).
    // Heuristic: We try to assume the *first* segment is the Ref.
    // If that fails (complex refs), the user should use the explicit git syntax
    // handled by _parseGitSyntax (url#ref:path).

    final parts = template.split('/tree/');
    final repoUrl = '${parts[0]}.git'; // Add .git to make it a valid git url
    final rest = parts[1];

    final splitRest = rest.split('/');
    final ref = splitRest[0];
    final path = splitRest.sublist(1).join('/');

    return TemplateLocation(gitUrl: repoUrl, gitRef: ref, gitPath: path);
  }

  TemplateLocation _parseGitHubShortSyntax(String template) {
    // Format: owner/repo/path/to/brick@ref
    // 1. Split optional ref
    var pathStr = template;
    String? ref;
    if (template.contains('@')) {
      final parts = template.split('@');
      pathStr = parts[0];
      ref = parts[1];
    }

    // 2. Split owner/repo and path
    final fileParts = pathStr.split('/');
    if (fileParts.length < 2) {
      // Should have been caught by regex or caller, but fallback
      return TemplateLocation(
        gitUrl: 'https://github.com/$pathStr.git',
        gitRef: ref,
      );
    }

    final owner = fileParts[0];
    final repo = fileParts[1];
    final repoUrl = 'https://github.com/$owner/$repo.git';

    String? path;
    if (fileParts.length > 2) {
      path = fileParts.sublist(2).join('/');
    }

    return TemplateLocation(gitUrl: repoUrl, gitRef: ref, gitPath: path);
  }
}
