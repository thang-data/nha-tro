import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rental_manager/data/repository.dart';
import 'package:rental_manager/screens/invoices_screen.dart';
import 'package:rental_manager/screens/room_detail_screen.dart';
import 'package:rental_manager/screens/services_screen.dart';
import 'package:rental_manager/screens/sites_screen.dart';

void main() {
  testWidgets('màn cơ sở: nút thêm phòng bật sau khi tải xong', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: SitesScreen(repository: MockRentalRepository())),
    );
    await tester.pumpAndSettle();

    final fab = tester.widget<FloatingActionButton>(
      find.byType(FloatingActionButton),
    );
    expect(fab.onPressed, isNotNull);
  });

  testWidgets('màn dịch vụ: thêm dịch vụ mới rồi tắt', (tester) async {
    final repo = MockRentalRepository();
    await tester.pumpWidget(
      MaterialApp(home: ServicesScreen(repository: repo)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Thêm dịch vụ'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('service-name')),
      'Giặt là',
    );
    await tester.enterText(
      find.byKey(const ValueKey('service-price')),
      '50000',
    );
    await tester.tap(find.text('Theo tháng'));
    await tester.tap(find.widgetWithText(FilledButton, 'Lưu'));
    await tester.pumpAndSettle();

    expect(find.text('Giặt là'), findsOneWidget);
    expect(find.textContaining('theo tháng × số lượng'), findsWidgets);

    await tester.tap(find.byType(Switch).last);
    await tester.pumpAndSettle();
    final saved = (await repo.listServices(siteId: 's1'))
        .singleWhere((s) => s.name == 'Giặt là');
    expect(saved.active, isFalse);
    expect(find.textContaining('Đã tắt'), findsOneWidget);
  });

  testWidgets('màn dịch vụ: đơn giá bằng 0 bị chặn, không tạo dịch vụ', (
    tester,
  ) async {
    final repo = MockRentalRepository();
    await tester.pumpWidget(
      MaterialApp(home: ServicesScreen(repository: repo)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Thêm dịch vụ'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('service-name')), 'Test');
    await tester.enterText(find.byKey(const ValueKey('service-price')), '0');
    await tester.tap(find.widgetWithText(FilledButton, 'Lưu'));
    await tester.pumpAndSettle();

    expect(find.text('Đơn giá phải lớn hơn 0'), findsOneWidget);
    expect(
      (await repo.listServices(siteId: 's1')).any((s) => s.name == 'Test'),
      isFalse,
    );
  });

  testWidgets('chi tiết phòng: sửa hạn thanh toán, chặn giá trị ngoài 1..60', (
    tester,
  ) async {
    final repo = MockRentalRepository();
    final room = await repo.getRoom('r-A101');
    await tester.pumpWidget(
      MaterialApp(
        home: RoomDetailScreen(room: room, repository: repo),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Hạn thanh toán: 7 ngày'), findsOneWidget);

    await tester.tap(find.byTooltip('Sửa hạn thanh toán'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('room-due-days-edit')),
      '61',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Lưu'));
    await tester.pumpAndSettle();
    expect(find.text('Hạn thanh toán từ 1 đến 60 ngày'), findsOneWidget);
    expect((await repo.getRoom('r-A101')).paymentDueDays, 7);

    await tester.enterText(
      find.byKey(const ValueKey('room-due-days-edit')),
      '20',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Lưu'));
    await tester.pumpAndSettle();
    expect(find.text('Hạn thanh toán: 20 ngày'), findsOneWidget);
    expect((await repo.getRoom('r-A101')).paymentDueDays, 20);
  });

  testWidgets('chi tiết hóa đơn: hiển thị từng dòng từ invoice_lines', (
    tester,
  ) async {
    final repo = MockRentalRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: InvoiceDetailScreen(
          invoice: await repo.getInvoice('INV-2610-001'),
          repository: repo,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Chi tiết hóa đơn'), findsOneWidget);
    expect(find.text('Tiền phòng'), findsOneWidget);
    expect(find.text('Điện'), findsOneWidget);
    expect(find.text('Nước'), findsOneWidget);
    expect(find.text('Internet'), findsOneWidget);
    expect(find.text('TỔNG CỘNG'), findsOneWidget);
    expect(find.text('Số tiền trả cuối'), findsOneWidget);
  });
}
