import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rental_manager/data/repository.dart';
import 'package:rental_manager/screens/room_form_screen.dart';

Future<void> pumpForm(WidgetTester tester, RentalRepository repo) async {
  await tester.pumpWidget(
    MaterialApp(
      home: RoomFormScreen(siteId: 's1', repository: repo),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('trùng mã phòng trong cùng cơ sở bị chặn', (tester) async {
    final repo = MockRentalRepository();
    await pumpForm(tester, repo);

    await tester.enterText(find.byKey(const ValueKey('room-code')), 'A101');
    await tester.enterText(find.byKey(const ValueKey('room-rent')), '3000000');
    await tester.tap(find.text('Lưu phòng'));
    await tester.pumpAndSettle();

    expect(find.text('Mã phòng đã tồn tại trong cơ sở này'), findsOneWidget);
    expect((await repo.listRooms(siteId: 's1')).length, 4);
  });

  testWidgets('giá thuê phải lớn hơn 0', (tester) async {
    final repo = MockRentalRepository();
    await pumpForm(tester, repo);

    await tester.enterText(find.byKey(const ValueKey('room-code')), 'C301');
    await tester.enterText(find.byKey(const ValueKey('room-rent')), '0');
    await tester.tap(find.text('Lưu phòng'));
    await tester.pumpAndSettle();

    expect(find.text('Giá thuê phải lớn hơn 0'), findsOneWidget);
    expect(
      (await repo.listRooms(siteId: 's1')).any((r) => r.code == 'C301'),
      isFalse,
    );
  });

  testWidgets('tạo phòng mới hợp lệ thì lưu được', (tester) async {
    final repo = MockRentalRepository();
    await pumpForm(tester, repo);

    await tester.enterText(find.byKey(const ValueKey('room-code')), 'c301');
    await tester.enterText(find.byKey(const ValueKey('room-rent')), '2800000');
    await tester.tap(find.text('Lưu phòng'));
    await tester.pumpAndSettle();

    expect(
      (await repo.listRooms(siteId: 's1')).any((r) => r.code == 'C301'),
      isTrue,
    );
  });
}
