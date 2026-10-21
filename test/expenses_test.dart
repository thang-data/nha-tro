import 'package:flutter_test/flutter_test.dart';
import 'package:rental_manager/data/billing.dart';
import 'package:rental_manager/data/models.dart';
import 'package:rental_manager/data/repository.dart';

Expense _expense(String id, int amount, DateTime date) => Expense(
  id: id,
  siteId: 's1',
  date: date,
  category: expenseCategories.first,
  amount: amount,
  note: '',
);

void main() {
  test('expensesOf chỉ cộng khoản chi trong đúng kỳ', () {
    final expenses = [
      _expense('a', 500000, DateTime(2026, 10, 3)),
      _expense('b', 200000, DateTime(2026, 10, 25)),
      _expense('c', 900000, DateTime(2026, 9, 30)),
    ];
    expect(expensesOf(expenses, 'Tháng 10/2026'), 700000);
    expect(expensesOf(expenses, 'Tháng 11/2026'), 0);
  });

  test('mock: lưu, liệt kê theo kỳ, xóa khoản chi', () async {
    final repo = MockRentalRepository(clock: () => DateTime(2026, 10, 20));
    await repo.saveExpense(_expense('x1', 300000, DateTime(2026, 10, 5)));
    await repo.saveExpense(_expense('x2', 150000, DateTime(2026, 9, 5)));

    final oct = await repo.listExpenses(period: 'Tháng 10/2026');
    expect(oct.map((e) => e.id), ['x1']);

    await repo.deleteExpense('x1');
    expect(await repo.listExpenses(period: 'Tháng 10/2026'), isEmpty);
  });

  test('mock: số tiền không dương bị từ chối', () async {
    final repo = MockRentalRepository(clock: () => DateTime(2026, 10, 20));
    expect(
      () => repo.saveExpense(_expense('x3', 0, DateTime(2026, 10, 5))),
      throwsArgumentError,
    );
  });

  test('doanh thu trừ chi phí cho ra lợi nhuận đúng', () async {
    final repo = MockRentalRepository(clock: () => DateTime(2026, 10, 20));
    final revenue = await repo.revenueForPeriod('Tháng 10/2026');
    await repo.saveExpense(_expense('x4', 1000000, DateTime(2026, 10, 10)));
    final expenses = await repo.listExpenses(period: 'Tháng 10/2026');
    expect(
      revenue.total - expensesOf(expenses, 'Tháng 10/2026'),
      revenue.total - 1000000,
    );
  });
}
