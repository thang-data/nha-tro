import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rental_manager/core/validators.dart';
import 'package:rental_manager/data/models.dart';
import 'package:rental_manager/data/repository.dart';
import 'package:rental_manager/screens/room_form_screen.dart';

void main() {
  group('validate hạn thanh toán', () {
    test('1..60 ngày là hợp lệ', () {
      expect(validatePaymentDueDaysInput('1'), isNull);
      expect(validatePaymentDueDaysInput('7'), isNull);
      expect(validatePaymentDueDaysInput(' 60 '), isNull);
    });

    test('ngoài 1..60 hoặc không phải số thì báo lỗi', () {
      const range = 'Hạn thanh toán từ 1 đến 60 ngày';
      expect(validatePaymentDueDaysInput('0'), range);
      expect(validatePaymentDueDaysInput('61'), range);
      expect(validatePaymentDueDaysInput('-3'), range);
      expect(validatePaymentDueDaysInput(''), 'Nhập số ngày');
      expect(validatePaymentDueDaysInput('abc'), 'Nhập số ngày');
      expect(validatePaymentDueDaysInput(null), 'Nhập số ngày');
    });
  });

  test('phòng mới mặc định hạn 7 ngày', () async {
    final repo = MockRentalRepository();
    final room = await repo.createRoom(
      siteId: 's1',
      code: 'C301',
      floor: 3,
      rent: 2800000,
    );
    expect(room.paymentDueDays, defaultPaymentDueDays);
    expect(defaultPaymentDueDays, 7);
  });

  test(
    'tạo phòng và đổi hạn: nhận giá trị hợp lệ, từ chối ngoài khoảng',
    () async {
      final repo = MockRentalRepository();
      final room = await repo.createRoom(
        siteId: 's1',
        code: 'C302',
        floor: 3,
        rent: 2800000,
        paymentDueDays: 15,
      );
      expect(room.paymentDueDays, 15);

      final updated = await repo.updateRoomDueDays(room.id, 30);
      expect(updated.paymentDueDays, 30);
      expect((await repo.getRoom(room.id)).paymentDueDays, 30);

      await expectLater(
        repo.updateRoomDueDays(room.id, 0),
        throwsArgumentError,
      );
      await expectLater(
        repo.updateRoomDueDays(room.id, 61),
        throwsArgumentError,
      );
      expect((await repo.getRoom(room.id)).paymentDueDays, 30);
    },
  );

  testWidgets('form phòng: hạn sai thì không lưu, hạn đúng thì lưu', (
    tester,
  ) async {
    final repo = MockRentalRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: RoomFormScreen(siteId: 's1', repository: repo),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('7'), findsWidgets);
    await tester.enterText(find.byKey(const ValueKey('room-code')), 'C303');
    await tester.enterText(find.byKey(const ValueKey('room-rent')), '2800000');
    await tester.enterText(find.byKey(const ValueKey('room-due-days')), '61');
    await tester.tap(find.text('Lưu phòng'));
    await tester.pumpAndSettle();
    expect(find.text('Hạn thanh toán từ 1 đến 60 ngày'), findsOneWidget);
    expect(
      (await repo.listRooms(siteId: 's1')).any((r) => r.code == 'C303'),
      isFalse,
    );

    await tester.enterText(find.byKey(const ValueKey('room-due-days')), '14');
    await tester.tap(find.text('Lưu phòng'));
    await tester.pumpAndSettle();
    final saved = (await repo.listRooms(siteId: 's1'))
        .where((r) => r.code == 'C303')
        .single;
    expect(saved.paymentDueDays, 14);
  });
}
