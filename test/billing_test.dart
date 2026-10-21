import 'package:flutter_test/flutter_test.dart';
import 'package:rental_manager/core/money.dart';
import 'package:rental_manager/data/billing.dart';

void main() {
  test('tổng hóa đơn khớp ví dụ A101 tháng 10 (3.680.000đ)', () {
    final b = calculateInvoice(
      rent: 3000000,
      kwhUsed: 120,
      electricityRate: 3500,
      m3Used: 8,
      waterRate: 20000,
      services: 100000,
    );
    expect(b.electricity, 420000);
    expect(b.water, 160000);
    expect(b.total, 3680000);
  });

  test('còn nợ sau thu lần 1 là 1.680.000đ, không âm khi trả thừa', () {
    expect(outstandingAmount(3680000, [2000000]), 1680000);
    expect(outstandingAmount(3680000, [4000000]), 0);
  });

  test('chỉ số tiêu thụ âm bị từ chối', () {
    expect(
      () => calculateInvoice(
        rent: 0,
        kwhUsed: -1,
        electricityRate: 3500,
        m3Used: 0,
        waterRate: 0,
        services: 0,
      ),
      throwsArgumentError,
    );
  });

  test('định dạng tiền VND', () {
    expect(formatVnd(3680000), '3.680.000 đ');
    expect(formatVnd(0), '0 đ');
    expect(formatVnd(999), '999 đ');
  });
}
