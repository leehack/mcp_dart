/// Extracts the exact-version body used for a GitHub release.
///
/// The matching `## <version>` heading and the next visible level-two heading
/// are excluded. Headings inside HTML comments or fenced code blocks are
/// ignored. The returned Markdown has boundary blank lines removed and exactly
/// one trailing newline.
String extractReleaseNotes({
  required String changelog,
  required String version,
}) {
  final masked = maskMarkdownCommentsAndFences(changelog);
  final targetHeading = RegExp(
    '^##[ \\t]+${RegExp.escape(version)}[ \\t]*\\r?\$',
    multiLine: true,
  );
  final matches = targetHeading.allMatches(masked).toList(growable: false);
  if (matches.isEmpty) {
    throw FormatException('has no release heading for $version.');
  }
  if (matches.length > 1) {
    throw FormatException('has multiple release headings for $version.');
  }

  final heading = matches.single;
  final remainder = masked.substring(heading.end);
  final nextHeading = RegExp(
    r'^##[ \t]+\S.*\r?$',
    multiLine: true,
  ).firstMatch(remainder);
  final end =
      nextHeading == null ? changelog.length : heading.end + nextHeading.start;
  final body = changelog.substring(heading.end, end);

  if (!_hasSubstantiveReleaseNotes(body)) {
    throw FormatException(
      'release section for $version has no substantive release notes.',
    );
  }
  return _normalizeBoundaries(body);
}

bool _hasSubstantiveReleaseNotes(String section) {
  final masked = maskMarkdownCommentsAndFences(section);
  const placeholders = <String>{
    'coming soon',
    'n/a',
    'none',
    'tbd',
    'todo',
    'unreleased',
  };
  for (final line in masked.split(RegExp(r'\r\n?|\n'))) {
    var content = line.trim();
    if (content.isEmpty ||
        RegExp(r'^#{1,6}(?:[ \t]|$)').hasMatch(content) ||
        RegExp(r'^[-*_]{3,}$').hasMatch(content)) {
      continue;
    }
    content = content
        .replaceFirst(RegExp(r'^(?:[-*+]|\d+[.)])[ \t]+'), '')
        .replaceFirst(RegExp(r'^>[ \t]*'), '')
        .replaceAll(RegExp(r'[`*_~]'), '')
        .trim();
    final normalized =
        content.replaceFirst(RegExp(r'[.!?:;]+$'), '').trim().toLowerCase();
    if (normalized.isNotEmpty && !placeholders.contains(normalized)) {
      return true;
    }
  }
  return false;
}

String _normalizeBoundaries(String source) {
  final normalized = source.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final lines = normalized.split('\n');
  var start = 0;
  while (start < lines.length && lines[start].trim().isEmpty) {
    start += 1;
  }
  var end = lines.length;
  while (end > start && lines[end - 1].trim().isEmpty) {
    end -= 1;
  }
  return '${lines.sublist(start, end).join('\n')}\n';
}

/// Masks HTML comments and fenced code while preserving every source offset.
String maskMarkdownCommentsAndFences(String source) {
  final original = source.codeUnits;
  final masked = List<int>.of(original);
  var inComment = false;
  int? inlineBacktickLength;
  final fence = RegExp(r'^[ \t]*(`{3,}|~{3,})');
  int? fenceCharacter;
  var minimumFenceLength = 0;
  var lineStart = 0;
  while (lineStart < masked.length) {
    var lineEnd = lineStart;
    while (lineEnd < masked.length &&
        masked[lineEnd] != 0x0a &&
        masked[lineEnd] != 0x0d) {
      lineEnd += 1;
    }
    final originalLine = source.substring(lineStart, lineEnd);
    if (fenceCharacter != null) {
      final match = fence.firstMatch(originalLine);
      final marker = match?.group(1);
      _maskRange(masked, lineStart, lineEnd);
      if (marker != null &&
          marker.codeUnitAt(0) == fenceCharacter &&
          marker.length >= minimumFenceLength &&
          originalLine.substring(match!.end).trim().isEmpty) {
        fenceCharacter = null;
        minimumFenceLength = 0;
      }
    } else {
      var index = lineStart;
      while (index < lineEnd) {
        if (inComment) {
          if (_matchesAscii(original, index, '-->')) {
            _maskRange(masked, index, index + 3);
            index += 3;
            inComment = false;
          } else {
            masked[index] = 0x20;
            index += 1;
          }
          continue;
        }
        if (original[index] == 0x60) {
          final runLength = _backtickRunLength(original, index, lineEnd);
          if (inlineBacktickLength == null) {
            inlineBacktickLength = runLength;
          } else if (inlineBacktickLength == runLength) {
            inlineBacktickLength = null;
          }
          index += runLength;
          continue;
        }
        if (inlineBacktickLength == null &&
            _matchesAscii(original, index, '<!--')) {
          _maskRange(masked, index, index + 4);
          index += 4;
          inComment = true;
          continue;
        }
        index += 1;
      }

      final visibleLine = String.fromCharCodes(
        masked.sublist(lineStart, lineEnd),
      );
      final match = fence.firstMatch(visibleLine);
      final marker = match?.group(1);
      if (marker != null) {
        final markerStart = match!.end - marker.length;
        final originalPrefix = originalLine.substring(0, markerStart);
        if (originalPrefix.trim().isEmpty) {
          fenceCharacter = marker.codeUnitAt(0);
          minimumFenceLength = marker.length;
          inComment = false;
          inlineBacktickLength = null;
          _maskRange(masked, lineStart, lineEnd);
        }
      }
    }

    if (lineEnd < masked.length &&
        masked[lineEnd] == 0x0d &&
        lineEnd + 1 < masked.length &&
        masked[lineEnd + 1] == 0x0a) {
      lineStart = lineEnd + 2;
    } else {
      lineStart = lineEnd + 1;
    }
  }
  return String.fromCharCodes(masked);
}

int _backtickRunLength(List<int> source, int start, int end) {
  var index = start + 1;
  while (index < end && source[index] == 0x60) {
    index += 1;
  }
  return index - start;
}

bool _matchesAscii(List<int> source, int start, String value) {
  if (start + value.length > source.length) {
    return false;
  }
  for (var offset = 0; offset < value.length; offset += 1) {
    if (source[start + offset] != value.codeUnitAt(offset)) {
      return false;
    }
  }
  return true;
}

void _maskRange(List<int> source, int start, int end) {
  for (var index = start; index < end; index += 1) {
    if (source[index] != 0x0a && source[index] != 0x0d) {
      source[index] = 0x20;
    }
  }
}
