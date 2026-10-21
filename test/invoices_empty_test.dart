import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rental_manager/data/models.dart';
import 'package:rental_manager/data/repository.dart';
import 'package:rental_manager/screens/invoices_screen.dart';

/// Repo không có hóa đơn nào, để kiểm tra trạng thái trống của màn Hóa đơn.
class _EmptyInvoicesRepo extends MockRentalRepository {
  @override
  Future<List<Invoice>> listInvoices({
    String? period,
    InvoiceStatus? status,
  }) async => [];
}

void main() {
  testWidgets('hóa đơn trống: giải thích và lập ngay được', (tester) async {
    final repo = _EmptyInvoicesRepo();
    await tester.pumpWidget(
      MaterialApp(home: InvoicesScreen(repository: repo)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Chưa có hóa đơn nào.'), findsOneWidget);
    expect(find.textContaining('Hóa đơn được lập tự động'), findsOneWidget);

    await tester.tap(find.textContaining('Lập hóa đơn Tháng'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Đã lập 0 hóa đơn'), findsOneWidget);
    expect(find.text('Chưa lập được:'), findsOneWidget);
  });
}
