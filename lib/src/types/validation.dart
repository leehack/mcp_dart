double? readUnitDouble(Object? value, String field) {
  if (value == null) {
    return null;
  }
  if (value is! num) {
    throw FormatException('$field must be a number between 0 and 1');
  }
  final result = value.toDouble();
  if (result < 0 || result > 1) {
    throw FormatException('$field must be between 0 and 1');
  }
  return result;
}

void validateUnitDouble(double? value, String field) {
  if (value == null) {
    return;
  }
  if (value < 0 || value > 1) {
    throw ArgumentError.value(value, field, 'must be between 0 and 1');
  }
}

int? readOptionalInteger(Object? value, String field) {
  if (value == null) {
    return null;
  }
  if (value is int) {
    return value;
  }
  if (value is double && value.isFinite && value == value.truncateToDouble()) {
    return value.toInt();
  }
  throw FormatException('$field must be an integer');
}
