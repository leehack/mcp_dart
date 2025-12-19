import 'package:mcp_dart_cli/src/template_resolver.dart';
import 'package:test/test.dart';

void main() {
  group('TemplateResolver', () {
    const resolver = TemplateResolver();

    test('resolves local path', () {
      final location = resolver.resolve('.');
      expect(location.path, isNotNull);
      expect(location.gitUrl, isNull);
    });

    test('resolves git url with explicit syntax (parsed as ref)', () {
      final location = resolver.resolve(
        'https://github.com/felangel/mason.git#path/to/brick',
      );
      expect(location.gitUrl, 'https://github.com/felangel/mason.git');
      // "path/to/brick" is parsed as the ref because there is no colon separator
      expect(location.gitRef, 'path/to/brick');
      expect(location.gitPath, isNull);
    });

    test('resolves git url with explicit syntax and ref', () {
      final location = resolver.resolve(
        'https://github.com/felangel/mason.git#ref:path/to/brick',
      );
      expect(location.gitUrl, 'https://github.com/felangel/mason.git');
      expect(location.gitPath, 'path/to/brick');
      expect(location.gitRef, 'ref');
    });

    test('resolves github tree url', () {
      final location = resolver.resolve(
        'https://github.com/leehack/mcp_dart/tree/main/packages/templates/simple',
      );
      expect(location.gitUrl, 'https://github.com/leehack/mcp_dart.git');
      expect(location.gitPath, 'packages/templates/simple');
      expect(location.gitRef, 'main');
    });

    test('resolves github tree url with complex ref', () {
      // Ideally we'd want this to work, but heuristic assumes first parts is ref
      // https://github.com/User/Repo/tree/feature/foo/Path/To/Brick
      // will likely parse ref='feature' path='foo/Path/To/Brick'
      // which is acceptable for now given the simple heuristic.

      final location = resolver.resolve(
        'https://github.com/user/repo/tree/feature/foo/path/to/brick',
      );
      expect(location.gitUrl, 'https://github.com/user/repo.git');
      expect(location.gitPath, 'foo/path/to/brick');
      expect(location.gitRef, 'feature');
    });

    test('resolves github short syntax', () {
      final location = resolver.resolve('felangel/mason/path/to/brick');
      expect(location.gitUrl, 'https://github.com/felangel/mason.git');
      expect(location.gitPath, 'path/to/brick');
      expect(location.gitRef, isNull);
    });

    test('resolves github short syntax with ref', () {
      final location = resolver.resolve('felangel/mason/path/to/brick@ref');
      expect(location.gitUrl, 'https://github.com/felangel/mason.git');
      expect(location.gitPath, 'path/to/brick');
      expect(location.gitRef, 'ref');
    });

    test('fallbacks to git url', () {
      final location =
          resolver.resolve('https://github.com/felangel/mason.git');
      expect(location.gitUrl, 'https://github.com/felangel/mason.git');
      expect(location.gitPath, isNull);
      expect(location.gitRef, isNull);
    });
  });
}
