/// Định dạng số kiểu Việt Nam, không đơn vị: 3680000 -> "3.680.000".
String formatNumber(num amount) {
  final negative = amount < 0;
  final digits = amount.abs().round().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    final remaining = digits.length - i;
    buffer.write(digits[i]);
    if (remaining > 1 && remaining % 3 == 1) buffer.write('.');
  }
  return '${negative ? '-' : ''}$buffer';
}

/// Định dạng tiền VND kiểu Việt Nam: 3680000 -> "3.680.000 đ".
String formatVnd(num amount) => '${formatNumber(amount)} đ';
