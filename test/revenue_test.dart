import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rental_manager/data/billing.dart';
import 'package:rental_manager/data/models.dart';
import 'package:rental_manager/data/repository.dart';
import 'package:rental_manager/screens/dashboard_screen.dart';

Payment _pay(String id, int amount, DateTime at, {String method = 'cash'}) =>
    Payment(
      id: id,
      invoiceId: 'inv',
      amount: amount,
      method: method,
      paidAt: at,
      idempotencyKey: id,
    );

Invoice _invoice(String id, String siteId, List<Payment> payments) => Invoice(
  id: id,
  siteId: siteId,
  roomCode: 'A101',
  tenant: 'Nguyễn Văn A',
  period: 'Tháng 9/2026',
  total: 1000000,
  dueDate: DateTime(2026, 10, 7),
  payments: payments,
  lines: const [],
);

void main() {
  test('doanh thu tính theo ngày thu, tách theo cơ sở, bỏ khoản chuyển nợ', () {
    final invoices = [
      _invoice('a', 's1', [
        _pay('p1', 1000000, DateTime(2026, 10, 3)),
        _pay('p2', 500000, DateTime(2026, 11, 2)),
      ]),
      _invoice('b', 's2', [
        _pay('p3', 700000, DateTime(2026, 10, 25), method: 'transfer'),
        _pay(
          'p4',
          300000,
          DateTime(2026, 10, 30),
          method: Payment.settlementMethod,
        ),
      ]),
    ];
    final revenue = revenueOf(invoices, 'Tháng 10/2026');
    expect(revenue.total, 1700000);
    expect(revenue.bySite, {'s1': 1000000, 's2': 700000});
  });

  test('kỳ không có khoản thu thì doanh thu bằng 0', () {
    final revenue = revenueOf(const [], 'Tháng 10/2026');
    expect(revenue.total, 0);
    expect(revenue.bySite, isEmpty);
  });

  test('mock repository: ghi nhận thu xong thì doanh thu tháng tăng', () async {
    final repo = MockRentalRepository(clock: () => DateTime(2026, 10, 20));
    final before = (await repo.revenueForPeriod('Tháng 10/2026')).total;
    await repo.recordPayment(
      invoiceId: 'INV-2610-001',
      amount: 400000,
      method: 'cash',
      idempotencyKey: 'k-revenue',
    );
    final after = (await repo.revenueForPeriod('Tháng 10/2026')).total;
    expect(after - before, 400000);
  });

  testWidgets('tổng quan: super admin thấy thẻ doanh thu tháng', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        home: DashboardScreen(
          repository: MockRentalRepository(clock: () => DateTime(2026, 10, 20)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Doanh thu Tháng '), findsOneWidget);
  });
}
