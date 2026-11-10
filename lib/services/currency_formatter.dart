/// Central formatting for money amounts shown in the app.
///
/// The selected currency is a display preference only. Amounts are stored
/// exactly as the user entered them, with no currency attached, and nothing
/// here converts or modifies stored values.
///
/// Currencies without an entry in [_rules] keep the app's original
/// behaviour: the symbol directly followed by the stored text (for example
/// `₹100000`), or by a value with two decimals for computed amounts (for
/// example `₹1234.50`).
class CurrencyFormatter {
  const CurrencyFormatter._();

  static const Map<String, CurrencyFormatRule> _rules = {
    // Sri Lankan Rupee: "Rs. 1,000.00"
    'LKR': CurrencyFormatRule(
      symbolSeparator: ' ',
      groupThousands: true,
      decimalDigits: 2,
      formatStoredValues: true,
    ),
  };

  /// Formatting rule for [currencyCode], or [CurrencyFormatRule.legacy].
  static CurrencyFormatRule ruleFor(String currencyCode) =>
      _rules[currencyCode] ?? CurrencyFormatRule.legacy;

  /// Formats a stored amount string, such as a card limit or annual spends.
  ///
  /// [fallback] is shown when [raw] is null. Text that is not a finite number
  /// is shown unchanged after the symbol.
  static String formatStored(
    String? raw, {
    required String currencyCode,
    required String symbol,
    String fallback = '',
  }) {
    final rule = ruleFor(currencyCode);
    final text = raw ?? fallback;
    if (!rule.formatStoredValues) return '$symbol$text';

    final trimmed = text.trim();
    if (trimmed.isEmpty) return symbol;
    final value = double.tryParse(trimmed);
    if (value == null || !value.isFinite || value.abs() >= 1e21) {
      return '$symbol${rule.symbolSeparator}$trimmed';
    }
    return _formatNumber(value, symbol, rule);
  }

  /// Formats a computed amount, such as estimated cashback.
  static String formatValue(
    double value, {
    required String currencyCode,
    required String symbol,
  }) {
    final rule = ruleFor(currencyCode);
    if (identical(rule, CurrencyFormatRule.legacy)) {
      return '$symbol${value.toStringAsFixed(rule.decimalDigits)}';
    }
    if (!value.isFinite || value.abs() >= 1e21) {
      return '$symbol${rule.symbolSeparator}$value';
    }
    return _formatNumber(value, symbol, rule);
  }

  static String _formatNumber(
    double value,
    String symbol,
    CurrencyFormatRule rule,
  ) {
    final fixed = value.abs().toStringAsFixed(rule.decimalDigits);
    final parts = fixed.split('.');
    final integer = rule.groupThousands ? _group(parts[0]) : parts[0];
    final number = parts.length > 1 ? '$integer.${parts[1]}' : integer;
    final isNegative = value < 0 && double.parse(fixed) != 0;
    return '${isNegative ? '-' : ''}$symbol${rule.symbolSeparator}$number';
  }

  static String _group(String digits) {
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }
}

/// How amounts in one currency are displayed.
class CurrencyFormatRule {
  /// Text between the symbol and the number, for example `' '` in `Rs. 10`.
  final String symbolSeparator;

  /// Whether the integer part uses `,` thousands separators.
  final bool groupThousands;

  /// Number of decimal places shown.
  final int decimalDigits;

  /// Whether stored amount strings are parsed and formatted. When false,
  /// stored text is shown exactly as entered (the original behaviour).
  final bool formatStoredValues;

  const CurrencyFormatRule({
    required this.symbolSeparator,
    required this.groupThousands,
    required this.decimalDigits,
    required this.formatStoredValues,
  });

  /// The app's original formatting, used by all currencies without a rule.
  static const legacy = CurrencyFormatRule(
    symbolSeparator: '',
    groupThousands: false,
    decimalDigits: 2,
    formatStoredValues: false,
  );
}
