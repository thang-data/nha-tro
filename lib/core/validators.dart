import '../data/models.dart';

/// Hạn thanh toán hợp lệ: từ [minPaymentDueDays] đến [maxPaymentDueDays] ngày.
bool isValidPaymentDueDays(int days) =>
    days >= minPaymentDueDays && days <= maxPaymentDueDays;

/// Kiểm tra chuỗi người dùng nhập cho hạn thanh toán. Trả về null nếu hợp lệ.
String? validatePaymentDueDaysInput(String? input) {
  final days = int.tryParse(input?.trim() ?? '');
  if (days == null) return 'Nhập số ngày';
  if (!isValidPaymentDueDays(days)) {
    return 'Hạn thanh toán từ $minPaymentDueDays đến $maxPaymentDueDays ngày';
  }
  return null;
}
