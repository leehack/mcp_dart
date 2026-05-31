/// Validates an MCP parameter header suffix against RFC 9110 field-name token
/// syntax.
bool isValidMcpHeaderNameSuffix(String value) {
  return value.isNotEmpty && value.codeUnits.every(isHttpFieldNameTokenChar);
}

/// Returns whether [unit] is an RFC 9110 HTTP field-name token character.
bool isHttpFieldNameTokenChar(int unit) {
  return unit >= 0x30 && unit <= 0x39 ||
      unit >= 0x41 && unit <= 0x5A ||
      unit >= 0x61 && unit <= 0x7A ||
      switch (unit) {
        0x21 ||
        0x23 ||
        0x24 ||
        0x25 ||
        0x26 ||
        0x27 ||
        0x2A ||
        0x2B ||
        0x2D ||
        0x2E ||
        0x5E ||
        0x5F ||
        0x60 ||
        0x7C ||
        0x7E =>
          true,
        _ => false,
      };
}
