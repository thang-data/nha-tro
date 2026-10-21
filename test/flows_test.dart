import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rental_manager/data/models.dart';
import 'package:rental_manager/data/repository.dart';
import 'package:rental_manager/screens/invoices_screen.dart';
import 'package:rental_manager/screens/tenant_form_screen.dart';

void main() {
  testWidgets('ghi nhận thu: không vượt số còn nợ, lưu được khoản hợp lệ', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final repo = MockRentalRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: InvoiceDetailScreen(
          invoice: (await repo.getInvoice('INV-2609-014')),
          repository: repo,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(
      find.text('Ghi nhận thu tiền'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.tap(find.text('Ghi nhận thu tiền'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('payment-amount')),
      '3000000',
    );
    await tester.tap(find.text('Xác nhận thu tiền'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Không được vượt số còn nợ'), findsOneWidget);
    expect((await repo.getInvoice('INV-2609-014')).payments, isEmpty);

    await tester.enterText(
      find.byKey(const ValueKey('payment-amount')),
      '1000000',
    );
    await tester.tap(find.text('Xác nhận thu tiền'));
    await tester.pumpAndSettle();

    final invoice = await repo.getInvoice('INV-2609-014');
    expect(invoice.payments.length, 1);
    expect(invoice.remaining, 1900000);
    expect(find.text('Đã ghi nhận thu 1.000.000 đ'), findsOneWidget);
  });

  testWidgets('thêm người thuê vào phòng trống: phòng chuyển sang đang thuê', (
    tester,
  ) async {
    final repo = MockRentalRepository();
    final room = (await repo.listRooms(
      siteId: 's1',
      status: RoomStatus.vacant,
    )).first;
    await tester.pumpWidget(
      MaterialApp(
        home: TenantFormScreen(room: room, repository: repo),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('tenant-name')),
      'Lê Văn Cường',
    );
    await tester.enterText(
      find.byKey(const ValueKey('tenant-phone')),
      '0933445566',
    );
    await tester.enterText(
      find.byKey(const ValueKey('tenant-citizen')),
      '036099001234',
    );
    await tester.tap(find.text('Lưu và ký hợp đồng'));
    await tester.pumpAndSettle();

    final updated = await repo.getRoom(room.id);
    expect(updated.status, RoomStatus.occupied);
    expect(updated.tenantName, 'Lê Văn Cường');
    expect(await repo.activeContractForRoom(room.id), isNotNull);
  });
}
