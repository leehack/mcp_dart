/// Returns whether [value] satisfies the JSON Schema format named [format].
///
/// Unknown formats are annotations and therefore always succeed. The
/// implementation intentionally uses only Dart SDK primitives so schema
/// validation behaves the same on the VM and the web.
bool jsonSchemaFormatIsValid(String format, String value) {
  return switch (format) {
    'date' => _isDate(value),
    'time' => _isTime(value),
    'date-time' => _isDateTime(value),
    'duration' => _duration.hasMatch(value),
    'email' => _isEmail(value, international: false),
    'idn-email' => _isEmail(value, international: true),
    'hostname' => _isHostname(value, international: false),
    'idn-hostname' => _isHostname(value, international: true),
    'ipv4' => _isIpv4(value),
    'ipv6' => _isIpv6(value),
    'regex' || 'ecmascript-regex' => _isRegex(value),
    'json-pointer' => _jsonPointer.hasMatch(value),
    'relative-json-pointer' => _relativeJsonPointer.hasMatch(value),
    'uri' => _isUri(value, requireScheme: true, international: false),
    'uri-reference' => _isUri(
        value,
        requireScheme: false,
        international: false,
      ),
    'iri' => _isUri(value, requireScheme: true, international: true),
    'iri-reference' => _isUri(value, requireScheme: false, international: true),
    'uri-template' => _isUriTemplate(value),
    'uuid' => _uuid.hasMatch(value),
    _ => true,
  };
}

const _draft7AssertionFormats = {
  'date',
  'date-time',
  'email',
  'hostname',
  'idn-email',
  'idn-hostname',
  'ipv4',
  'ipv6',
  'iri',
  'iri-reference',
  'json-pointer',
  'regex',
  'relative-json-pointer',
  'time',
  'uri',
  'uri-reference',
  'uri-template',
};

/// Applies only the format assertions defined by JSON Schema Draft 7.
bool jsonSchemaDraft7FormatIsValid(String format, String value) {
  return !_draft7AssertionFormats.contains(format) ||
      jsonSchemaFormatIsValid(format, value);
}

/// Returns whether [value] is a strict RFC 3986 URI-reference.
bool jsonSchemaUriReferenceIsValid(String value) {
  return _isUri(value, requireScheme: false, international: false);
}

final RegExp _date = RegExp(r'^([0-9]{4})-([0-9]{2})-([0-9]{2})$');
final RegExp _time = RegExp(
  r'^([0-9]{2}):([0-9]{2}):([0-9]{2})(?:\.[0-9]+)?'
  r'(Z|z|([+-])([0-9]{2}):([0-9]{2}))$',
);
final RegExp _duration = RegExp(
  r'^(?:P[0-9]+W|P(?:'
  r'(?:[0-9]+Y(?:[0-9]+M(?:[0-9]+D)?)?'
  r'|[0-9]+M(?:[0-9]+D)?|[0-9]+D)'
  r'(?:T(?:[0-9]+H(?:[0-9]+M(?:[0-9]+S)?)?'
  r'|[0-9]+M(?:[0-9]+S)?|[0-9]+S))?'
  r'|T(?:[0-9]+H(?:[0-9]+M(?:[0-9]+S)?)?'
  r'|[0-9]+M(?:[0-9]+S)?|[0-9]+S)))$',
);
final RegExp _jsonPointer = RegExp(r'^(?:/(?:[^~/]|~[01])*)*$');
final RegExp _relativeJsonPointer = RegExp(
  r'^(?:0|[1-9][0-9]*)(?:#|(?:/(?:[^~/]|~[01])*)*)$',
);
final RegExp _uuid = RegExp(
  r'^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-'
  r'[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$',
);
final RegExp _scheme = RegExp(r'^[A-Za-z][A-Za-z0-9+.-]*$');
final RegExp _asciiDigits = RegExp(r'^[0-9]+$');
final RegExp _templateVariablePart = RegExp(
  r'^(?:[A-Za-z0-9_]|%[0-9A-Fa-f]{2})+$',
);

bool _isDate(String value) {
  final match = _date.firstMatch(value);
  if (match == null) return false;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  if (month < 1 || month > 12 || day < 1) return false;
  const monthLengths = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  var maximum = monthLengths[month - 1];
  if (month == 2 && _isLeapYear(year)) maximum++;
  return day <= maximum;
}

bool _isLeapYear(int year) {
  return year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
}

bool _isTime(String value) {
  final match = _time.firstMatch(value);
  if (match == null) return false;
  final hour = int.parse(match.group(1)!);
  final minute = int.parse(match.group(2)!);
  final second = int.parse(match.group(3)!);
  if (hour > 23 || minute > 59 || second > 60) return false;

  final offsetSign = match.group(5);
  var offsetMinutes = 0;
  if (offsetSign != null) {
    final offsetHour = int.parse(match.group(6)!);
    final offsetMinute = int.parse(match.group(7)!);
    if (offsetHour > 23 || offsetMinute > 59) return false;
    offsetMinutes = offsetHour * 60 + offsetMinute;
    if (offsetSign == '-') offsetMinutes = -offsetMinutes;
  }

  if (second != 60) return true;
  final utcMinute = (hour * 60 + minute - offsetMinutes) % (24 * 60);
  return utcMinute == 23 * 60 + 59;
}

bool _isDateTime(String value) {
  final separator = value.indexOf(RegExp('[Tt]'));
  if (separator <= 0 || separator != value.lastIndexOf(RegExp('[Tt]'))) {
    return false;
  }
  return _isDate(value.substring(0, separator)) &&
      _isTime(value.substring(separator + 1));
}

bool _isRegex(String value) {
  try {
    RegExp(value, unicode: true);
    return true;
  } on FormatException {
    return false;
  }
}

bool _isIpv4(String value) {
  final parts = value.split('.');
  if (parts.length != 4) return false;
  for (final part in parts) {
    if (part.isEmpty || part.length > 3 || !_asciiDigits.hasMatch(part)) {
      return false;
    }
    if (int.parse(part) > 255) return false;
  }
  return true;
}

bool _isIpv6(String value) {
  if (!_hasWellFormedUtf16(value)) return false;
  // `Uri.parseIPv6Address` accepted surrounding whitespace on older Dart
  // SDKs. Keep format validation stable across the supported SDK range and
  // reject zone identifiers and every other character outside IPv6 syntax.
  for (final rune in value.runes) {
    final isDigit = rune >= 0x30 && rune <= 0x39;
    final isUpperHex = rune >= 0x41 && rune <= 0x46;
    final isLowerHex = rune >= 0x61 && rune <= 0x66;
    if (!isDigit &&
        !isUpperHex &&
        !isLowerHex &&
        rune != 0x3a &&
        rune != 0x2e) {
      return false;
    }
  }
  try {
    Uri.parseIPv6Address(value);
    return true;
  } on FormatException {
    return false;
  }
}

bool _isEmail(String value, {required bool international}) {
  if (!_hasWellFormedUtf16(value) || value.isEmpty || value.length > 254) {
    return false;
  }

  final int separator;
  final String local;
  if (value.startsWith('"')) {
    final closingQuote = _closingEmailQuote(value);
    if (closingQuote < 1 ||
        closingQuote + 1 >= value.length ||
        value.codeUnitAt(closingQuote + 1) != 0x40) {
      return false;
    }
    separator = closingQuote + 1;
    local = value.substring(0, closingQuote + 1);
  } else {
    separator = value.indexOf('@');
    if (separator < 1 || separator != value.lastIndexOf('@')) return false;
    local = value.substring(0, separator);
  }
  final domain = value.substring(separator + 1);
  if (domain.isEmpty || local.length > 64) return false;
  if (!_isEmailLocalPart(local, international: international)) return false;

  if (domain.startsWith('[') && domain.endsWith(']')) {
    final address = domain.substring(1, domain.length - 1);
    if (address.startsWith('IPv6:')) {
      return _isIpv6(address.substring(5));
    }
    return _isIpv4(address);
  }
  return _isHostname(domain, international: international);
}

int _closingEmailQuote(String value) {
  var escaped = false;
  for (var index = 1; index < value.length; index++) {
    final codeUnit = value.codeUnitAt(index);
    if (escaped) {
      escaped = false;
    } else if (codeUnit == 0x5c) {
      escaped = true;
    } else if (codeUnit == 0x22) {
      return index;
    }
  }
  return -1;
}

bool _isEmailLocalPart(String value, {required bool international}) {
  if (value.startsWith('"')) {
    if (!value.endsWith('"') || value.length < 2) return false;
    var escaped = false;
    for (var index = 1; index < value.length - 1; index++) {
      final codeUnit = value.codeUnitAt(index);
      if (escaped) {
        if (codeUnit == 0x0a || codeUnit == 0x0d) return false;
        escaped = false;
      } else if (codeUnit == 0x5c) {
        escaped = true;
      } else if (codeUnit == 0x22 || codeUnit == 0x0a || codeUnit == 0x0d) {
        return false;
      } else if ((!international && codeUnit > 0x7f) || codeUnit == 0x7f) {
        return false;
      }
    }
    return !escaped;
  }

  final atoms = value.split('.');
  if (atoms.any((atom) => atom.isEmpty)) return false;
  for (final atom in atoms) {
    for (final rune in atom.runes) {
      if (rune < 0x80) {
        if (!_isEmailAtomCharacter(rune)) return false;
      } else if (!international || _isUnicodeControlOrSpace(rune)) {
        return false;
      }
    }
  }
  return true;
}

bool _isEmailAtomCharacter(int rune) {
  return _isAsciiLetterOrDigit(rune) ||
      const {
        0x21,
        0x23,
        0x24,
        0x25,
        0x26,
        0x27,
        0x2a,
        0x2b,
        0x2d,
        0x2f,
        0x3d,
        0x3f,
        0x5e,
        0x5f,
        0x60,
        0x7b,
        0x7c,
        0x7d,
        0x7e,
      }.contains(rune);
}

bool _isHostname(String value, {required bool international}) {
  if (!_hasWellFormedUtf16(value) || value.isEmpty) return false;
  final separators = international ? RegExp(r'[.\u3002\uff0e\uff61]') : '.';
  final labels = value.split(separators);
  if (labels.any((label) => label.isEmpty)) return false;

  final encodedLabels = <String>[];
  final decodedLabels = <List<int>>[];
  for (final label in labels) {
    final result = _validateHostnameLabel(label, international: international);
    if (result == null) return false;
    encodedLabels.add(result.ascii);
    decodedLabels.add(result.runes);
  }
  if (encodedLabels.join('.').length > 253) return false;

  final bidiDomain = decodedLabels.any((label) => label.any(_isRtlRune));
  if (bidiDomain) {
    for (final label in decodedLabels) {
      if (!_passesBidiRule(label)) return false;
    }
  }
  return true;
}

_HostnameLabel? _validateHostnameLabel(
  String label, {
  required bool international,
}) {
  final lower = label.toLowerCase();
  if (lower.startsWith('xn--')) {
    if (label.length > 63) return null;
    final payload = label.substring(4);
    final decoded = _punycodeDecode(payload);
    if (decoded == null || !decoded.any((rune) => rune >= 0x80)) return null;
    if (!_isValidIdnLabel(decoded)) return null;
    final encoded = _punycodeEncode(decoded);
    if (encoded == null || encoded.toLowerCase() != payload.toLowerCase()) {
      return null;
    }
    final ascii = 'xn--$encoded';
    if (ascii.length > 63) return null;
    return _HostnameLabel(ascii, decoded);
  }

  final runes = label.runes.toList(growable: false);
  if (runes.length > 63) return null;
  if (!international && runes.any((rune) => rune >= 0x80)) return null;
  if (!_isValidIdnLabel(runes)) return null;
  final encoded = runes.any((rune) => rune >= 0x80)
      ? _punycodeEncode(runes)
      : label.toLowerCase();
  if (encoded == null) return null;
  final ascii = runes.any((rune) => rune >= 0x80) ? 'xn--$encoded' : encoded;
  if (ascii.length > 63) return null;
  return _HostnameLabel(ascii, runes);
}

bool _isValidIdnLabel(List<int> runes) {
  if (runes.isEmpty || runes.first == 0x2d || runes.last == 0x2d) return false;
  if (runes.length >= 4 && runes[2] == 0x2d && runes[3] == 0x2d) {
    return false;
  }
  if (_isCombiningMark(runes.first)) return false;

  var hasJapaneseScript = false;
  var hasArabicIndicDigits = false;
  var hasExtendedArabicIndicDigits = false;
  for (final rune in runes) {
    if (_isJapaneseScript(rune)) hasJapaneseScript = true;
    if (rune >= 0x0660 && rune <= 0x0669) hasArabicIndicDigits = true;
    if (rune >= 0x06f0 && rune <= 0x06f9) {
      hasExtendedArabicIndicDigits = true;
    }
    if (!_isPermittedIdnRune(rune)) return false;
  }
  if (hasArabicIndicDigits && hasExtendedArabicIndicDigits) return false;

  for (var index = 0; index < runes.length; index++) {
    final rune = runes[index];
    if (rune == 0x00b7 &&
        (index == 0 ||
            index + 1 == runes.length ||
            runes[index - 1] != 0x6c ||
            runes[index + 1] != 0x6c)) {
      return false;
    }
    if (rune == 0x0375 &&
        (index + 1 == runes.length || !_isGreek(runes[index + 1]))) {
      return false;
    }
    if ((rune == 0x05f3 || rune == 0x05f4) &&
        (index == 0 || !_isHebrew(runes[index - 1]))) {
      return false;
    }
    if (rune == 0x30fb && !hasJapaneseScript) return false;
    if (rune == 0x200d && (index == 0 || !_isVirama(runes[index - 1]))) {
      return false;
    }
    if (rune == 0x200c &&
        (index == 0 ||
            (!_isVirama(runes[index - 1]) &&
                !(index + 1 < runes.length &&
                    _isArabicJoiningLetter(runes[index - 1]) &&
                    _isArabicJoiningLetter(runes[index + 1]))))) {
      return false;
    }
  }
  return true;
}

bool _isPermittedIdnRune(int rune) {
  if (_isAsciiLetterOrDigit(rune) || rune == 0x2d) return true;
  if (rune < 0x80 || _isUnicodeControlOrSpace(rune)) return false;
  if (rune >= 0xd800 && rune <= 0xdfff) return false;
  if (rune >= 0xfdd0 && rune <= 0xfdef || (rune & 0xffff) >= 0xfffe) {
    return false;
  }
  if (const {
    0x00a1,
    0x0640,
    0x07fa,
    0x302e,
    0x302f,
    0x3031,
    0x3032,
    0x3033,
    0x3034,
    0x3035,
  }.contains(rune)) {
    return false;
  }
  return true;
}

bool _passesBidiRule(List<int> runes) {
  if (runes.isEmpty) return false;
  final rtl = runes.any(_isRtlRune);
  var last = runes.length - 1;
  while (last >= 0 && _isCombiningMark(runes[last])) {
    last--;
  }
  if (last < 0) return false;

  if (rtl) {
    if (!_isRtlLetter(runes.first) ||
        !(_isRtlLetter(runes[last]) || _isDecimalDigit(runes[last]))) {
      return false;
    }
    if (runes.any(_isLtrLetter)) return false;
    final hasEuropeanDigits = runes.any(_isAsciiDigit);
    final hasArabicDigits = runes.any(
      (rune) => rune >= 0x0660 && rune <= 0x0669,
    );
    return !(hasEuropeanDigits && hasArabicDigits);
  }

  if (!_isLtrLetter(runes.first)) return false;
  return _isLtrLetter(runes[last]) || _isAsciiDigit(runes[last]);
}

bool _isUri(
  String value, {
  required bool requireScheme,
  required bool international,
}) {
  if (!_hasWellFormedUtf16(value) ||
      !_hasValidUriCharacters(value, international: international) ||
      !_hasValidPercentEncoding(value)) {
    return false;
  }
  if (value.indexOf('#') != value.lastIndexOf('#')) return false;

  final firstColon = value.indexOf(':');
  final firstDelimiter = _firstIndexOfAny(value, '/?#');
  final colonCouldBeScheme =
      firstColon >= 0 && (firstDelimiter < 0 || firstColon < firstDelimiter);
  var schemeEnd = -1;
  if (colonCouldBeScheme) {
    if (firstColon == 0 || !_scheme.hasMatch(value.substring(0, firstColon))) {
      return false;
    }
    schemeEnd = firstColon;
  }
  if (requireScheme && schemeEnd < 0) return false;

  final hierarchyStart = schemeEnd < 0 ? 0 : schemeEnd + 1;
  var allowedBracketStart = -1;
  var allowedBracketEnd = -1;
  if (value.startsWith('//', hierarchyStart)) {
    final authorityStart = hierarchyStart + 2;
    final authorityEnd = _firstIndexOfAny(value, '/?#', start: authorityStart);
    final authority = value.substring(
      authorityStart,
      authorityEnd < 0 ? value.length : authorityEnd,
    );
    if (!_isValidAuthority(authority, international: international)) {
      return false;
    }
    final userInfoEnd = authority.lastIndexOf('@');
    final hostStart = authorityStart + (userInfoEnd < 0 ? 0 : userInfoEnd + 1);
    if (hostStart < value.length && value.codeUnitAt(hostStart) == 0x5b) {
      allowedBracketStart = hostStart;
      allowedBracketEnd = value.indexOf(']', hostStart + 1);
    }
  }
  for (var index = 0; index < value.length; index++) {
    final codeUnit = value.codeUnitAt(index);
    if ((codeUnit == 0x5b || codeUnit == 0x5d) &&
        index != allowedBracketStart &&
        index != allowedBracketEnd) {
      return false;
    }
  }

  try {
    Uri.parse(value);
    return true;
  } on FormatException {
    return false;
  }
}

bool _hasValidUriCharacters(String value, {required bool international}) {
  for (final rune in value.runes) {
    if (rune < 0x21 || rune == 0x7f) return false;
    if (rune > 0x7f) {
      if (!international || _isUnicodeControlOrSpace(rune)) return false;
      continue;
    }
    if (const {
      0x22,
      0x3c,
      0x3e,
      0x5c,
      0x5e,
      0x60,
      0x7b,
      0x7c,
      0x7d,
    }.contains(rune)) {
      return false;
    }
  }
  return true;
}

bool _hasValidPercentEncoding(String value) {
  for (var index = 0; index < value.length; index++) {
    if (value.codeUnitAt(index) != 0x25) continue;
    if (index + 2 >= value.length ||
        !_isAsciiHex(value.codeUnitAt(index + 1)) ||
        !_isAsciiHex(value.codeUnitAt(index + 2))) {
      return false;
    }
    index += 2;
  }
  return true;
}

bool _isValidAuthority(String authority, {required bool international}) {
  if (authority.indexOf('@') != authority.lastIndexOf('@')) return false;
  final at = authority.lastIndexOf('@');
  final hostPort = at < 0 ? authority : authority.substring(at + 1);
  if (hostPort.startsWith('[')) {
    final closing = hostPort.indexOf(']');
    if (closing < 0) return false;
    final address = hostPort.substring(1, closing);
    final suffix = hostPort.substring(closing + 1);
    if (suffix.isNotEmpty &&
        (!suffix.startsWith(':') ||
            (suffix.length > 1 &&
                !_asciiDigits.hasMatch(suffix.substring(1))))) {
      return false;
    }
    if (address.startsWith(RegExp('[vV]'))) {
      return RegExp(
        r'^[vV][0-9A-Fa-f]+\.[A-Za-z0-9._~!$&\x27()*+,;=:-]+$',
      ).hasMatch(address);
    }
    return _isIpv6(address);
  }
  if (hostPort.contains('[') || hostPort.contains(']')) return false;

  final firstColon = hostPort.indexOf(':');
  if (firstColon >= 0) {
    if (firstColon != hostPort.lastIndexOf(':')) return false;
    final port = hostPort.substring(firstColon + 1);
    if (port.isNotEmpty && !_asciiDigits.hasMatch(port)) return false;
  }
  return international || hostPort.runes.every((rune) => rune < 0x80);
}

bool _isUriTemplate(String value) {
  if (!_hasWellFormedUtf16(value)) return false;
  final expanded = StringBuffer();
  var index = 0;
  while (index < value.length) {
    final codeUnit = value.codeUnitAt(index);
    if (codeUnit == 0x7d) return false;
    if (codeUnit != 0x7b) {
      expanded.writeCharCode(codeUnit);
      index++;
      continue;
    }
    final close = value.indexOf('}', index + 1);
    if (close < 0) return false;
    final expression = value.substring(index + 1, close);
    if (!_isUriTemplateExpression(expression)) return false;
    expanded.write('x');
    index = close + 1;
  }
  return _isUri(
    expanded.toString(),
    requireScheme: false,
    international: false,
  );
}

bool _isUriTemplateExpression(String expression) {
  if (expression.isEmpty || expression.contains('{')) return false;
  if ('+#./;?&'.contains(expression[0])) expression = expression.substring(1);
  if (expression.isEmpty) return false;
  for (var variable in expression.split(',')) {
    if (variable.isEmpty) return false;
    if (variable.endsWith('*')) {
      variable = variable.substring(0, variable.length - 1);
    } else {
      final colon = variable.lastIndexOf(':');
      if (colon >= 0) {
        final prefix = variable.substring(colon + 1);
        if (prefix.isEmpty ||
            prefix.length > 4 ||
            prefix.startsWith('0') ||
            !_asciiDigits.hasMatch(prefix)) {
          return false;
        }
        variable = variable.substring(0, colon);
      }
    }
    if (variable.isEmpty ||
        variable.split('.').any(
              (part) => part.isEmpty || !_templateVariablePart.hasMatch(part),
            )) {
      return false;
    }
  }
  return true;
}

bool _hasWellFormedUtf16(String value) {
  for (var index = 0; index < value.length; index++) {
    final codeUnit = value.codeUnitAt(index);
    if (codeUnit >= 0xd800 && codeUnit <= 0xdbff) {
      if (++index >= value.length) return false;
      final low = value.codeUnitAt(index);
      if (low < 0xdc00 || low > 0xdfff) return false;
    } else if (codeUnit >= 0xdc00 && codeUnit <= 0xdfff) {
      return false;
    }
  }
  return true;
}

bool _isUnicodeControlOrSpace(int rune) {
  return rune <= 0x20 ||
      rune >= 0x7f && rune <= 0x9f ||
      const {
        0x00a0,
        0x1680,
        0x2028,
        0x2029,
        0x202f,
        0x205f,
        0x3000,
      }.contains(rune) ||
      rune >= 0x2000 && rune <= 0x200b;
}

bool _isCombiningMark(int rune) {
  return rune >= 0x0300 && rune <= 0x036f ||
      rune >= 0x0483 && rune <= 0x0489 ||
      rune >= 0x0591 && rune <= 0x05bd ||
      rune == 0x05bf ||
      rune >= 0x05c1 && rune <= 0x05c2 ||
      rune >= 0x05c4 && rune <= 0x05c5 ||
      rune >= 0x0610 && rune <= 0x061a ||
      rune >= 0x064b && rune <= 0x065f ||
      rune == 0x0670 ||
      rune >= 0x06d6 && rune <= 0x06ed ||
      rune >= 0x0900 && rune <= 0x0903 ||
      rune >= 0x093a && rune <= 0x094f ||
      rune >= 0x0951 && rune <= 0x0957 ||
      rune >= 0x0f71 && rune <= 0x0f84 ||
      rune >= 0x1ab0 && rune <= 0x1aff ||
      rune >= 0x1dc0 && rune <= 0x1dff ||
      rune >= 0x20d0 && rune <= 0x20ff ||
      rune >= 0xfe00 && rune <= 0xfe0f ||
      rune >= 0xfe20 && rune <= 0xfe2f;
}

bool _isVirama(int rune) {
  return const {
    0x094d,
    0x09cd,
    0x0a4d,
    0x0acd,
    0x0b4d,
    0x0bcd,
    0x0c4d,
    0x0ccd,
    0x0d4d,
    0x0dca,
    0x0e3a,
    0x0f84,
    0x1039,
    0x103a,
    0x1714,
    0x1734,
    0x17d2,
    0x1a60,
    0x1b44,
    0x1baa,
    0xa806,
    0xa8c4,
    0xa953,
    0xa9c0,
    0xaaf6,
    0xabed,
  }.contains(rune);
}

bool _isJapaneseScript(int rune) {
  return rune >= 0x3040 && rune <= 0x30ff && rune != 0x30fb ||
      rune >= 0x3400 && rune <= 0x4dbf ||
      rune >= 0x4e00 && rune <= 0x9fff ||
      rune >= 0x20000 && rune <= 0x2fa1f;
}

bool _isGreek(int rune) {
  return rune >= 0x0370 && rune <= 0x03ff || rune >= 0x1f00 && rune <= 0x1fff;
}

bool _isHebrew(int rune) => rune >= 0x0590 && rune <= 0x05ff;

bool _isArabicJoiningLetter(int rune) {
  return rune >= 0x0620 && rune <= 0x063f ||
      rune >= 0x0641 && rune <= 0x064a ||
      rune >= 0x066e && rune <= 0x066f ||
      rune >= 0x0671 && rune <= 0x06d3 ||
      rune >= 0x06fa && rune <= 0x06fc;
}

bool _isRtlRune(int rune) {
  if (_isCombiningMark(rune) || _isDecimalDigit(rune)) return false;
  return rune >= 0x0590 && rune <= 0x08ff ||
      rune >= 0xfb1d && rune <= 0xfdff ||
      rune >= 0xfe70 && rune <= 0xfeff;
}

bool _isRtlLetter(int rune) {
  return _isRtlRune(rune) &&
      !_isCombiningMark(rune) &&
      !_isDecimalDigit(rune) &&
      rune != 0x200c &&
      rune != 0x200d;
}

bool _isLtrLetter(int rune) {
  if (rune >= 0x41 && rune <= 0x5a || rune >= 0x61 && rune <= 0x7a) {
    return true;
  }
  if (_isDecimalDigit(rune) ||
      _isCombiningMark(rune) ||
      rune == 0x00b7 ||
      rune == 0x0375 ||
      rune == 0x200c ||
      rune == 0x200d ||
      rune == 0x30fb) {
    return false;
  }
  return rune >= 0x00c0 && !_isRtlRune(rune);
}

bool _isDecimalDigit(int rune) {
  return _isAsciiDigit(rune) ||
      rune >= 0x0660 && rune <= 0x0669 ||
      rune >= 0x06f0 && rune <= 0x06f9;
}

bool _isAsciiDigit(int rune) => rune >= 0x30 && rune <= 0x39;

bool _isAsciiLetterOrDigit(int rune) {
  return _isAsciiDigit(rune) ||
      rune >= 0x41 && rune <= 0x5a ||
      rune >= 0x61 && rune <= 0x7a;
}

bool _isAsciiHex(int rune) {
  return _isAsciiDigit(rune) ||
      rune >= 0x41 && rune <= 0x46 ||
      rune >= 0x61 && rune <= 0x66;
}

int _firstIndexOfAny(String value, String characters, {int start = 0}) {
  for (var index = start; index < value.length; index++) {
    if (characters.contains(value[index])) return index;
  }
  return -1;
}

final class _HostnameLabel {
  final String ascii;
  final List<int> runes;

  const _HostnameLabel(this.ascii, this.runes);
}

const _punycodeBase = 36;
const _punycodeTMin = 1;
const _punycodeTMax = 26;
const _punycodeSkew = 38;
const _punycodeDamp = 700;
const _punycodeInitialBias = 72;
const _punycodeInitialN = 128;

List<int>? _punycodeDecode(String input) {
  if (input.isEmpty || input.runes.any((rune) => rune >= 0x80)) return null;
  final output = <int>[];
  final delimiter = input.lastIndexOf('-');
  var position = 0;
  if (delimiter >= 0) {
    for (var index = 0; index < delimiter; index++) {
      final rune = input.codeUnitAt(index);
      if (rune >= 0x80) return null;
      output.add(rune);
    }
    position = delimiter + 1;
  }

  var n = _punycodeInitialN;
  var indexValue = 0;
  var bias = _punycodeInitialBias;
  while (position < input.length) {
    final oldIndex = indexValue;
    var weight = 1;
    for (var k = _punycodeBase;; k += _punycodeBase) {
      if (position >= input.length) return null;
      final digit = _punycodeDigit(input.codeUnitAt(position++));
      if (digit < 0) return null;
      indexValue += digit * weight;
      final threshold = k <= bias
          ? _punycodeTMin
          : k >= bias + _punycodeTMax
              ? _punycodeTMax
              : k - bias;
      if (digit < threshold) break;
      weight *= _punycodeBase - threshold;
    }
    final outputLength = output.length + 1;
    bias = _adaptPunycodeBias(
      indexValue - oldIndex,
      outputLength,
      oldIndex == 0,
    );
    n += indexValue ~/ outputLength;
    if (n > 0x10ffff || n >= 0xd800 && n <= 0xdfff) return null;
    indexValue %= outputLength;
    output.insert(indexValue, n);
    indexValue++;
  }
  return output;
}

String? _punycodeEncode(List<int> input) {
  if (input.any(
    (rune) => rune < 0 || rune > 0x10ffff || rune >= 0xd800 && rune <= 0xdfff,
  )) {
    return null;
  }
  final output = StringBuffer();
  var basicCount = 0;
  for (final rune in input) {
    if (rune < 0x80) {
      output.writeCharCode(rune);
      basicCount++;
    }
  }
  var handled = basicCount;
  if (basicCount > 0 && handled < input.length) output.write('-');

  var n = _punycodeInitialN;
  var delta = 0;
  var bias = _punycodeInitialBias;
  while (handled < input.length) {
    var next = 0x10ffff;
    for (final rune in input) {
      if (rune >= n && rune < next) next = rune;
    }
    delta += (next - n) * (handled + 1);
    n = next;
    for (final rune in input) {
      if (rune < n) delta++;
      if (rune != n) continue;
      var q = delta;
      for (var k = _punycodeBase;; k += _punycodeBase) {
        final threshold = k <= bias
            ? _punycodeTMin
            : k >= bias + _punycodeTMax
                ? _punycodeTMax
                : k - bias;
        if (q < threshold) break;
        output.writeCharCode(
          _encodePunycodeDigit(
            threshold + (q - threshold) % (_punycodeBase - threshold),
          ),
        );
        q = (q - threshold) ~/ (_punycodeBase - threshold);
      }
      output.writeCharCode(_encodePunycodeDigit(q));
      bias = _adaptPunycodeBias(delta, handled + 1, handled == basicCount);
      delta = 0;
      handled++;
    }
    delta++;
    n++;
  }
  return output.toString();
}

int _punycodeDigit(int codeUnit) {
  if (codeUnit >= 0x30 && codeUnit <= 0x39) return codeUnit - 0x30 + 26;
  if (codeUnit >= 0x41 && codeUnit <= 0x5a) return codeUnit - 0x41;
  if (codeUnit >= 0x61 && codeUnit <= 0x7a) return codeUnit - 0x61;
  return -1;
}

int _encodePunycodeDigit(int digit) {
  return digit < 26 ? 0x61 + digit : 0x30 + digit - 26;
}

int _adaptPunycodeBias(int delta, int points, bool firstTime) {
  delta = firstTime ? delta ~/ _punycodeDamp : delta ~/ 2;
  delta += delta ~/ points;
  var k = 0;
  final limit = (_punycodeBase - _punycodeTMin) * _punycodeTMax ~/ 2;
  while (delta > limit) {
    delta ~/= _punycodeBase - _punycodeTMin;
    k += _punycodeBase;
  }
  return k +
      (_punycodeBase - _punycodeTMin + 1) * delta ~/ (delta + _punycodeSkew);
}
