import 'dart:math' as math;

/// Compares two finite JSON numbers by their exact decimal values.
int compareJsonNumbers(num left, num right) {
  if (!left.isFinite || !right.isFinite) {
    throw ArgumentError('JSON numbers must be finite');
  }
  final leftDecimal = _JsonDecimal.from(left);
  final rightDecimal = _JsonDecimal.from(right);
  final scale = math.max(leftDecimal.scale, rightDecimal.scale);
  final leftCoefficient =
      leftDecimal.coefficient * _powerOfTen(scale - leftDecimal.scale);
  final rightCoefficient =
      rightDecimal.coefficient * _powerOfTen(scale - rightDecimal.scale);
  return leftCoefficient.compareTo(rightCoefficient);
}

/// Whether two finite JSON numbers have the same mathematical value.
bool jsonNumbersEqual(num left, num right) {
  if (!left.isFinite || !right.isFinite) return false;
  return compareJsonNumbers(left, right) == 0;
}

/// Whether [value] is an exact mathematical multiple of positive [divisor].
bool jsonNumberIsMultiple(num value, num divisor) {
  if (divisor <= 0 || !value.isFinite || !divisor.isFinite) return false;
  final dividend = _JsonDecimal.from(value);
  final factor = _JsonDecimal.from(divisor);
  final scale = math.max(dividend.scale, factor.scale);
  final scaledDividend =
      dividend.coefficient.abs() * _powerOfTen(scale - dividend.scale);
  final scaledFactor =
      factor.coefficient.abs() * _powerOfTen(scale - factor.scale);
  return scaledDividend % scaledFactor == BigInt.zero;
}

/// Produces equal hashes for numerically equal finite JSON numbers.
int jsonNumberHash(num value) {
  if (!value.isFinite) return value.hashCode;
  final decimal = _JsonDecimal.from(value);
  return Object.hash(decimal.coefficient, decimal.scale);
}

final class _JsonDecimal {
  final BigInt coefficient;
  final int scale;

  const _JsonDecimal(this.coefficient, this.scale);

  factory _JsonDecimal.from(num value) {
    var text = value.toString().toLowerCase();
    var exponent = 0;
    final exponentMarker = text.indexOf('e');
    if (exponentMarker >= 0) {
      exponent = int.parse(text.substring(exponentMarker + 1));
      text = text.substring(0, exponentMarker);
    }
    final negative = text.startsWith('-');
    if (negative) text = text.substring(1);
    final point = text.indexOf('.');
    final fractionDigits = point < 0 ? 0 : text.length - point - 1;
    final digits = point < 0 ? text : text.replaceFirst('.', '');
    var coefficient = BigInt.parse('${negative ? '-' : ''}$digits');
    var scale = fractionDigits - exponent;
    final ten = BigInt.from(10);
    while (coefficient != BigInt.zero && coefficient % ten == BigInt.zero) {
      coefficient ~/= ten;
      scale--;
    }
    if (coefficient == BigInt.zero) scale = 0;
    return _JsonDecimal(coefficient, scale);
  }
}

BigInt _powerOfTen(int exponent) => BigInt.from(10).pow(exponent);
