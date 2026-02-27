import 'package:mcp_dart/src/types.dart';
import 'package:test/test.dart';

void main() {
  group('ResourceAnnotations', () {
    test('fromJson with all fields', () {
      final json = {
        'title': 'Test Resource',
        'audience': ['user', 'assistant'],
        'priority': 0.8,
        'lastModified': '2025-01-12T15:00:58Z',
      };

      final annotations = ResourceAnnotations.fromJson(json);
      expect(annotations.title, equals('Test Resource'));
      expect(annotations.audience, equals(['user', 'assistant']));
      expect(annotations.priority, equals(0.8));
      expect(annotations.lastModified, equals('2025-01-12T15:00:58Z'));
    });

    test('fromJson with null fields', () {
      final json = <String, dynamic>{};
      final annotations = ResourceAnnotations.fromJson(json);
      expect(annotations.title, isNull);
      expect(annotations.audience, isNull);
      expect(annotations.priority, isNull);
      expect(annotations.lastModified, isNull);
    });

    test('toJson serializes correctly', () {
      const annotations = ResourceAnnotations(
        title: 'My Title',
        audience: ['user'],
        priority: 0.5,
        lastModified: '2025-01-12T15:00:58Z',
      );

      final json = annotations.toJson();
      expect(json['title'], equals('My Title'));
      expect(json['audience'], equals(['user']));
      expect(json['priority'], equals(0.5));
      expect(json['lastModified'], equals('2025-01-12T15:00:58Z'));
    });

    test('toJson excludes null fields', () {
      const annotations = ResourceAnnotations(title: 'Only Title');
      final json = annotations.toJson();
      expect(json.containsKey('title'), isTrue);
      expect(json.containsKey('audience'), isFalse);
      expect(json.containsKey('priority'), isFalse);
      expect(json.containsKey('lastModified'), isFalse);
    });
  });

  group('Resource', () {
    test('fromJson with required fields only', () {
      final json = {
        'uri': 'file:///test.txt',
        'name': 'Test File',
      };

      final resource = Resource.fromJson(json);
      expect(resource.uri, equals('file:///test.txt'));
      expect(resource.name, equals('Test File'));
      expect(resource.description, isNull);
      expect(resource.mimeType, isNull);
      expect(resource.icon, isNull);
      expect(resource.annotations, isNull);
    });

    test('fromJson with all fields', () {
      final json = {
        'uri': 'file:///test.txt',
        'name': 'Test File',
        'description': 'A test file resource',
        'mimeType': 'text/plain',
        'icon': {
          'type': 'image',
          'data': 'base64data',
          'mimeType': 'image/png',
        },
        'annotations': {
          'title': 'Alt Title',
          'priority': 0.9,
        },
        'icons': [
          {
            'src': 'https://example.com/icon.png',
            'mimeType': 'image/png',
            'theme': 'dark',
          },
        ],
      };

      final resource = Resource.fromJson(json);
      expect(resource.uri, equals('file:///test.txt'));
      expect(resource.name, equals('Test File'));
      expect(resource.description, equals('A test file resource'));
      expect(resource.mimeType, equals('text/plain'));
      expect(resource.icon, isNotNull);
      expect(resource.icon!.data, equals('base64data'));
      expect(resource.icons, isNotNull);
      expect(
        resource.icons!.single.src,
        equals('https://example.com/icon.png'),
      );
      expect(resource.annotations, isNotNull);
      expect(resource.annotations!.priority, equals(0.9));
    });

    test('fromJson with meta', () {
      final json = {
        'uri': 'ui://weather/dashboard',
        'name': 'Weather Dashboard',
        '_meta': {
          'ui': {
            'prefersBorder': true,
          },
        },
      };

      final resource = Resource.fromJson(json);
      expect(resource.meta, isNotNull);
      expect(resource.meta!['ui']['prefersBorder'], isTrue);
    });

    test('toJson serializes correctly with all fields', () {
      const resource = Resource(
        uri: 'file:///example.txt',
        name: 'Example',
        description: 'Example description',
        mimeType: 'text/plain',
        annotations: ResourceAnnotations(priority: 0.7),
      );

      final json = resource.toJson();
      expect(json['uri'], equals('file:///example.txt'));
      expect(json['name'], equals('Example'));
      expect(json['description'], equals('Example description'));
      expect(json['mimeType'], equals('text/plain'));
      expect(json['annotations'], isNotNull);
    });

    test('toJson excludes null optional fields', () {
      const resource = Resource(
        uri: 'file:///minimal.txt',
        name: 'Minimal',
      );

      final json = resource.toJson();
      expect(json.containsKey('uri'), isTrue);
      expect(json.containsKey('name'), isTrue);
      expect(json.containsKey('description'), isFalse);
      expect(json.containsKey('mimeType'), isFalse);
      expect(json.containsKey('icon'), isFalse);
      expect(json.containsKey('icons'), isFalse);
      expect(json.containsKey('annotations'), isFalse);
      expect(json.containsKey('_meta'), isFalse);
    });

    test('toJson includes meta', () {
      const resource = Resource(
        uri: 'ui://dashboard',
        name: 'Dashboard',
        meta: {
          'ui': {
            'domain': 'ui.example.com',
          },
        },
      );

      final json = resource.toJson();
      expect(json['_meta'], isNotNull);
      expect(json['_meta']['ui']['domain'], equals('ui.example.com'));
    });
  });

  group('ResourceTemplate', () {
    test('fromJson with required fields only', () {
      final json = {
        'uriTemplate': 'file:///{path}',
        'name': 'File Template',
      };

      final template = ResourceTemplate.fromJson(json);
      expect(template.uriTemplate, equals('file:///{path}'));
      expect(template.name, equals('File Template'));
      expect(template.description, isNull);
      expect(template.mimeType, isNull);
    });

    test('fromJson with all fields', () {
      final json = {
        'uriTemplate': 'db://users/{id}',
        'name': 'User Database',
        'description': 'Access user records',
        'mimeType': 'application/json',
        'icon': {
          'type': 'image',
          'data': 'icondata',
          'mimeType': 'image/svg+xml',
        },
        'annotations': {
          'audience': ['user'],
        },
        'icons': [
          {
            'src': 'data:image/svg+xml;base64,PHN2Zy8+',
            'mimeType': 'image/svg+xml',
            'sizes': ['any'],
            'theme': 'light',
          },
        ],
      };

      final template = ResourceTemplate.fromJson(json);
      expect(template.uriTemplate, equals('db://users/{id}'));
      expect(template.name, equals('User Database'));
      expect(template.description, equals('Access user records'));
      expect(template.mimeType, equals('application/json'));
      expect(template.icon, isNotNull);
      expect(template.icons, isNotNull);
      expect(template.icons!.single.theme, equals(IconTheme.light));
      expect(template.annotations, isNotNull);
    });

    test('fromJson with meta', () {
      final json = {
        'uriTemplate': 'ui://weather/{location}',
        'name': 'Weather UI',
        '_meta': {
          'ui': {
            'csp': {
              'connectDomains': ['https://api.example.com'],
            },
          },
        },
      };

      final template = ResourceTemplate.fromJson(json);
      expect(template.meta, isNotNull);
      expect(
        template.meta!['ui']['csp']['connectDomains'],
        equals(['https://api.example.com']),
      );
    });

    test('toJson serializes correctly', () {
      const template = ResourceTemplate(
        uriTemplate: 'api://v1/{resource}',
        name: 'API Resource',
        description: 'API endpoint',
      );

      final json = template.toJson();
      expect(json['uriTemplate'], equals('api://v1/{resource}'));
      expect(json['name'], equals('API Resource'));
      expect(json['description'], equals('API endpoint'));
    });

    test('toJson excludes null fields', () {
      const template = ResourceTemplate(
        uriTemplate: 'minimal://{x}',
        name: 'Minimal',
      );

      final json = template.toJson();
      expect(json.containsKey('uriTemplate'), isTrue);
      expect(json.containsKey('name'), isTrue);
      expect(json.containsKey('description'), isFalse);
      expect(json.containsKey('mimeType'), isFalse);
      expect(json.containsKey('_meta'), isFalse);
    });

    test('toJson includes meta', () {
      const template = ResourceTemplate(
        uriTemplate: 'ui://widget/{id}',
        name: 'Widget UI',
        meta: {
          'ui': {
            'prefersBorder': false,
          },
        },
      );

      final json = template.toJson();
      expect(json['_meta'], isNotNull);
      expect(json['_meta']['ui']['prefersBorder'], isFalse);
    });
  });

  group('ListResourcesRequest', () {
    test('fromJson with cursor', () {
      final json = {'cursor': 'abc123'};
      final request = ListResourcesRequest.fromJson(json);
      expect(request.cursor, equals('abc123'));
    });

    test('fromJson without cursor', () {
      final json = <String, dynamic>{};
      final request = ListResourcesRequest.fromJson(json);
      expect(request.cursor, isNull);
    });

    test('toJson with cursor', () {
      const request = ListResourcesRequest(cursor: 'page2');
      final json = request.toJson();
      expect(json['cursor'], equals('page2'));
    });

    test('toJson without cursor excludes field', () {
      const request = ListResourcesRequest();
      final json = request.toJson();
      expect(json.containsKey('cursor'), isFalse);
    });
  });

  group('JsonRpcListResourcesRequest', () {
    test('creates request with method resources/list', () {
      final request = JsonRpcListResourcesRequest(id: 1);
      expect(request.method, equals('resources/list'));
      expect(request.id, equals(1));
    });

    test('creates request with params', () {
      final request = JsonRpcListResourcesRequest(
        id: 2,
        params: const ListResourcesRequest(cursor: 'next'),
      );
      expect(request.listParams.cursor, equals('next'));
      expect(request.params?['cursor'], equals('next'));
    });

    test('fromJson parses correctly', () {
      final json = {
        'id': 3,
        'method': 'resources/list',
        'params': {'cursor': 'xyz'},
      };

      final request = JsonRpcListResourcesRequest.fromJson(json);
      expect(request.id, equals(3));
      expect(request.listParams.cursor, equals('xyz'));
    });

    test('fromJson without params', () {
      final json = {
        'id': 4,
        'method': 'resources/list',
      };

      final request = JsonRpcListResourcesRequest.fromJson(json);
      expect(request.id, equals(4));
      expect(request.listParams.cursor, isNull);
    });
  });

  group('ListResourcesResult', () {
    test('fromJson with resources', () {
      final json = {
        'resources': [
          {'uri': 'file:///a.txt', 'name': 'A'},
          {'uri': 'file:///b.txt', 'name': 'B'},
        ],
        'nextCursor': 'page2',
      };

      final result = ListResourcesResult.fromJson(json);
      expect(result.resources.length, equals(2));
      expect(result.resources[0].uri, equals('file:///a.txt'));
      expect(result.resources[1].name, equals('B'));
      expect(result.nextCursor, equals('page2'));
    });

    test('fromJson with empty resources', () {
      final json = <String, dynamic>{};
      final result = ListResourcesResult.fromJson(json);
      expect(result.resources, isEmpty);
      expect(result.nextCursor, isNull);
    });

    test('fromJson with meta', () {
      final json = {
        'resources': <dynamic>[],
        '_meta': {'customKey': 'customValue'},
      };

      final result = ListResourcesResult.fromJson(json);
      expect(result.meta, isNotNull);
      expect(result.meta!['customKey'], equals('customValue'));
    });

    test('toJson serializes correctly', () {
      const result = ListResourcesResult(
        resources: [
          Resource(uri: 'file:///x.txt', name: 'X'),
        ],
        nextCursor: 'more',
      );

      final json = result.toJson();
      expect(json['resources'], isA<List>());
      expect((json['resources'] as List).length, equals(1));
      expect(json['nextCursor'], equals('more'));
    });
  });

  group('ListResourceTemplatesRequest', () {
    test('fromJson with cursor', () {
      final json = {'cursor': 'tmpl_cursor'};
      final request = ListResourceTemplatesRequest.fromJson(json);
      expect(request.cursor, equals('tmpl_cursor'));
    });

    test('toJson serializes correctly', () {
      const request = ListResourceTemplatesRequest(cursor: 'next_tmpl');
      final json = request.toJson();
      expect(json['cursor'], equals('next_tmpl'));
    });
  });

  group('JsonRpcListResourceTemplatesRequest', () {
    test('creates request with correct method', () {
      final request = JsonRpcListResourceTemplatesRequest(id: 10);
      expect(request.method, equals('resources/templates/list'));
    });

    test('fromJson parses correctly', () {
      final json = {
        'id': 11,
        'method': 'resources/templates/list',
        'params': {'cursor': 'tmpl_page'},
      };

      final request = JsonRpcListResourceTemplatesRequest.fromJson(json);
      expect(request.id, equals(11));
      expect(request.listParams.cursor, equals('tmpl_page'));
    });
  });

  group('ListResourceTemplatesResult', () {
    test('fromJson with templates', () {
      final json = {
        'resourceTemplates': [
          {'uriTemplate': 'file:///{name}', 'name': 'File'},
        ],
        'nextCursor': 'tmpl_next',
      };

      final result = ListResourceTemplatesResult.fromJson(json);
      expect(result.resourceTemplates.length, equals(1));
      expect(result.resourceTemplates[0].uriTemplate, equals('file:///{name}'));
      expect(result.nextCursor, equals('tmpl_next'));
    });

    test('fromJson with empty templates', () {
      final json = <String, dynamic>{};
      final result = ListResourceTemplatesResult.fromJson(json);
      expect(result.resourceTemplates, isEmpty);
    });

    test('toJson serializes correctly', () {
      const result = ListResourceTemplatesResult(
        resourceTemplates: [
          ResourceTemplate(uriTemplate: 'db://{id}', name: 'DB'),
        ],
      );

      final json = result.toJson();
      expect(json['resourceTemplates'], isA<List>());
      expect((json['resourceTemplates'] as List).length, equals(1));
    });
  });

  group('ReadResourceRequest', () {
    test('fromJson parses uri', () {
      final json = {'uri': 'file:///data.json'};
      final request = ReadResourceRequest.fromJson(json);
      expect(request.uri, equals('file:///data.json'));
    });

    test('toJson serializes correctly', () {
      const request = ReadResourceRequest(uri: 'file:///output.txt');
      final json = request.toJson();
      expect(json['uri'], equals('file:///output.txt'));
    });
  });

  group('JsonRpcReadResourceRequest', () {
    test('creates request with correct method', () {
      final request = JsonRpcReadResourceRequest(
        id: 20,
        readParams: const ReadResourceRequest(uri: 'file:///read.txt'),
      );
      expect(request.method, equals('resources/read'));
      expect(request.readParams.uri, equals('file:///read.txt'));
    });

    test('fromJson parses correctly', () {
      final json = {
        'id': 21,
        'method': 'resources/read',
        'params': {'uri': 'file:///parsed.txt'},
      };

      final request = JsonRpcReadResourceRequest.fromJson(json);
      expect(request.id, equals(21));
      expect(request.readParams.uri, equals('file:///parsed.txt'));
    });

    test('fromJson throws on missing params', () {
      final json = {
        'id': 22,
        'method': 'resources/read',
      };

      expect(
        () => JsonRpcReadResourceRequest.fromJson(json),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('ReadResourceResult', () {
    test('fromJson with contents', () {
      final json = {
        'contents': [
          {
            'uri': 'file:///content.txt',
            'text': 'Hello World',
          },
        ],
      };

      final result = ReadResourceResult.fromJson(json);
      expect(result.contents.length, equals(1));
      expect(result.contents[0].uri, equals('file:///content.txt'));
    });

    test('fromJson with empty contents', () {
      final json = <String, dynamic>{};
      final result = ReadResourceResult.fromJson(json);
      expect(result.contents, isEmpty);
    });

    test('toJson serializes correctly', () {
      final result = const ReadResourceResult(
        contents: [
          TextResourceContents(uri: 'file:///out.txt', text: 'Content'),
        ],
      );

      final json = result.toJson();
      expect(json['contents'], isA<List>());
    });

    test('resource contents preserve metadata and unknown fields', () {
      final result = ReadResourceResult.fromJson({
        'contents': [
          {
            'uri': 'ui://weather/dashboard',
            'mimeType': 'text/html;profile=mcp-app',
            'text': '<!doctype html><html></html>',
            '_meta': {
              'ui': {
                'domain': 'apps.example.com',
              },
            },
            'customField': {
              'enabled': true,
            },
          },
        ],
      });

      final content = result.contents.single;
      expect(content, isA<TextResourceContents>());
      expect(content.meta, isNotNull);
      expect(content.meta!['ui']['domain'], equals('apps.example.com'));
      expect(content.extra, isNotNull);
      expect(content.extra!['customField']['enabled'], isTrue);

      final json = result.toJson();
      final roundTripped = (json['contents'] as List).single;
      expect(roundTripped['_meta']['ui']['domain'], equals('apps.example.com'));
      expect(roundTripped['customField']['enabled'], isTrue);
    });

    test('unknown resource content preserves passthrough fields', () {
      final result = ReadResourceResult.fromJson({
        'contents': [
          {
            'uri': 'ui://weather/raw',
            'mimeType': 'application/vnd.custom+json',
            '_meta': {
              'ui': {
                'prefersBorder': true,
              },
            },
            'payload': {
              'kind': 'custom',
            },
          },
        ],
      });

      final content = result.contents.single;
      expect(content, isA<UnknownResourceContents>());
      expect(content.meta!['ui']['prefersBorder'], isTrue);
      expect(content.extra!['payload']['kind'], equals('custom'));

      final json = result.toJson();
      final roundTripped = (json['contents'] as List).single;
      expect(roundTripped['payload']['kind'], equals('custom'));
      expect(roundTripped['_meta']['ui']['prefersBorder'], isTrue);
    });
  });

  group('JsonRpcResourceListChangedNotification', () {
    test('creates notification with correct method', () {
      const notification = JsonRpcResourceListChangedNotification();
      expect(
        notification.method,
        equals('notifications/resources/list_changed'),
      );
    });

    test('fromJson creates notification', () {
      final json = {
        'method': 'notifications/resources/list_changed',
      };

      final notification =
          JsonRpcResourceListChangedNotification.fromJson(json);
      expect(
        notification.method,
        equals('notifications/resources/list_changed'),
      );
    });
  });

  group('SubscribeRequest', () {
    test('fromJson parses uri', () {
      final json = {'uri': 'file:///watch.txt'};
      final request = SubscribeRequest.fromJson(json);
      expect(request.uri, equals('file:///watch.txt'));
    });

    test('toJson serializes correctly', () {
      const request = SubscribeRequest(uri: 'file:///subscribe.txt');
      final json = request.toJson();
      expect(json['uri'], equals('file:///subscribe.txt'));
    });
  });

  group('JsonRpcSubscribeRequest', () {
    test('creates request with correct method', () {
      final request = JsonRpcSubscribeRequest(
        id: 30,
        subParams: const SubscribeRequest(uri: 'file:///sub.txt'),
      );
      expect(request.method, equals('resources/subscribe'));
    });

    test('fromJson parses correctly', () {
      final json = {
        'id': 31,
        'method': 'resources/subscribe',
        'params': {'uri': 'file:///subscribed.txt'},
      };

      final request = JsonRpcSubscribeRequest.fromJson(json);
      expect(request.id, equals(31));
      expect(request.subParams.uri, equals('file:///subscribed.txt'));
    });

    test('fromJson throws on missing params', () {
      final json = {
        'id': 32,
        'method': 'resources/subscribe',
      };

      expect(
        () => JsonRpcSubscribeRequest.fromJson(json),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('UnsubscribeRequest', () {
    test('fromJson parses uri', () {
      final json = {'uri': 'file:///unwatch.txt'};
      final request = UnsubscribeRequest.fromJson(json);
      expect(request.uri, equals('file:///unwatch.txt'));
    });

    test('toJson serializes correctly', () {
      const request = UnsubscribeRequest(uri: 'file:///unsub.txt');
      final json = request.toJson();
      expect(json['uri'], equals('file:///unsub.txt'));
    });
  });

  group('JsonRpcUnsubscribeRequest', () {
    test('creates request with correct method', () {
      final request = JsonRpcUnsubscribeRequest(
        id: 40,
        unsubParams: const UnsubscribeRequest(uri: 'file:///unsub.txt'),
      );
      expect(request.method, equals('resources/unsubscribe'));
    });

    test('fromJson parses correctly', () {
      final json = {
        'id': 41,
        'method': 'resources/unsubscribe',
        'params': {'uri': 'file:///unsubscribed.txt'},
      };

      final request = JsonRpcUnsubscribeRequest.fromJson(json);
      expect(request.id, equals(41));
      expect(request.unsubParams.uri, equals('file:///unsubscribed.txt'));
    });

    test('fromJson throws on missing params', () {
      final json = {
        'id': 42,
        'method': 'resources/unsubscribe',
      };

      expect(
        () => JsonRpcUnsubscribeRequest.fromJson(json),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('ResourceUpdatedNotification', () {
    test('fromJson parses uri', () {
      final json = {'uri': 'file:///updated.txt'};
      final notification = ResourceUpdatedNotification.fromJson(json);
      expect(notification.uri, equals('file:///updated.txt'));
    });

    test('toJson serializes correctly', () {
      const notification =
          ResourceUpdatedNotification(uri: 'file:///changed.txt');
      final json = notification.toJson();
      expect(json['uri'], equals('file:///changed.txt'));
    });
  });

  group('JsonRpcResourceUpdatedNotification', () {
    test('creates notification with correct method', () {
      final notification = JsonRpcResourceUpdatedNotification(
        updatedParams:
            const ResourceUpdatedNotification(uri: 'file:///notify.txt'),
      );
      expect(
        notification.method,
        equals('notifications/resources/updated'),
      );
      expect(notification.updatedParams.uri, equals('file:///notify.txt'));
    });

    test('fromJson parses correctly', () {
      final json = {
        'method': 'notifications/resources/updated',
        'params': {'uri': 'file:///parsed_notify.txt'},
      };

      final notification = JsonRpcResourceUpdatedNotification.fromJson(json);
      expect(
        notification.updatedParams.uri,
        equals('file:///parsed_notify.txt'),
      );
    });

    test('fromJson throws on missing params', () {
      final json = {
        'method': 'notifications/resources/updated',
      };

      expect(
        () => JsonRpcResourceUpdatedNotification.fromJson(json),
        throwsA(isA<FormatException>()),
      );
    });

    test('fromJson with meta', () {
      final json = {
        'method': 'notifications/resources/updated',
        'params': {
          'uri': 'file:///with_meta.txt',
          '_meta': {'key': 'value'},
        },
      };

      final notification = JsonRpcResourceUpdatedNotification.fromJson(json);
      expect(notification.meta, isNotNull);
      expect(notification.meta!['key'], equals('value'));
    });
  });
}
