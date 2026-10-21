import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rental_manager/core/money.dart';
import 'package:rental_manager/data/mock_data.dart';
import 'package:rental_manager/data/models.dart';
import 'package:rental_manager/data/repository.dart';
import 'package:rental_manager/screens/room_detail_screen.dart';

void main() {
  group('dịch vụ gắn vào phòng', () {
    test('dịch vụ cố định luôn ép số lượng về 1', () async {
      final repo = MockRentalRepository();
      final rs = await repo.attachService(
        roomId: 'r-A102',
        serviceId: 'sv-2',
        quantity: 5,
      );
      expect(rs.quantity, 1);
    });

    test('dịch vụ theo tháng giữ đúng số lượng', () async {
      final repo = MockRentalRepository();
      final rs = await repo.attachService(
        roomId: 'r-A102',
        serviceId: 'sv-3',
        quantity: 3,
      );
      expect(rs.quantity, 3);
      expect((await repo.listRoomServices('r-A102')).map((e) => e.serviceId), [
        'sv-3',
      ]);
    });

    test('gắn trùng dịch vụ bị chặn, số lượng <= 0 bị chặn', () async {
      final repo = MockRentalRepository();
      await repo.attachService(roomId: 'r-A102', serviceId: 'sv-3');
      await expectLater(
        repo.attachService(roomId: 'r-A102', serviceId: 'sv-3'),
        throwsA(isA<ServiceAlreadyAttachedException>()),
      );
      await expectLater(
        repo.attachService(roomId: 'r-A201', serviceId: 'sv-3', quantity: 0),
        throwsArgumentError,
      );
    });

    test('dịch vụ đang tắt không gắn được', () async {
      final repo = MockRentalRepository();
      final service = (await repo.listServices(siteId: 's1'))
          .firstWhere((s) => s.id == 'sv-3');
      await repo.updateService(service.copyWith(active: false));
      await expectLater(
        repo.attachService(roomId: 'r-A102', serviceId: 'sv-3'),
        throwsArgumentError,
      );
    });

    test('gỡ dịch vụ khỏi phòng', () async {
      final repo = MockRentalRepository();
      final rs = await repo.attachService(roomId: 'r-A102', serviceId: 'sv-3');
      await repo.detachService(rs.id);
      expect(await repo.listRoomServices('r-A102'), isEmpty);
    });

    test('thêm dịch vụ mới theo cơ sở và tên được chuẩn hóa', () async {
      final repo = MockRentalRepository();
      final service = await repo.createService(
        siteId: 's2',
        name: '  Giặt là ',
        unitPrice: 50000,
        unit: ServiceUnit.monthly,
      );
      expect(service.name, 'Giặt là');
      expect(
        (await repo.listServices(siteId: 's2')).map((s) => s.id),
        contains(service.id),
      );
      expect(
        (await repo.listServices(siteId: 's1')).map((s) => s.id),
        isNot(contains(service.id)),
      );
    });
  });

  testWidgets('chi tiết phòng: thêm dịch vụ từ danh mục rồi gỡ ra', (
    tester,
  ) async {
    final repo = MockRentalRepository();
    final room = await repo.getRoom('r-A102');
    await tester.pumpWidget(
      MaterialApp(
        home: RoomDetailScreen(room: room, repository: repo),
      ),
    );
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(
      find.text('Thêm dịch vụ'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.tap(find.text('Thêm dịch vụ'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('attach-service')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vệ sinh · ${formatVnd(30000)}').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('attach-quantity')), '2');
    await tester.tap(find.widgetWithText(FilledButton, 'Gắn'));
    await tester.pumpAndSettle();

    final attached = await repo.listRoomServices('r-A102');
    expect(attached.length, 1);
    expect(attached.single.quantity, 2);
    expect(find.text('Vệ sinh'), findsOneWidget);

    await tester.tap(find.byTooltip('Gỡ khỏi phòng'));
    await tester.pumpAndSettle();
    expect(await repo.listRoomServices('r-A102'), isEmpty);
    expect(find.text('Chưa gắn dịch vụ nào'), findsOneWidget);
  });

  test('mock: dòng hóa đơn cộng đúng tổng của từng hóa đơn', () {
    for (final invoice in invoices) {
      final sum = invoice.lines.fold<int>(0, (a, l) => a + l.amount);
      expect(invoice.lines, isNotEmpty, reason: invoice.id);
      expect(sum, invoice.total, reason: invoice.id);
    }
  });
}
