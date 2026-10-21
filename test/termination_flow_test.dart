import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:rental_manager/core/money.dart';
import 'package:rental_manager/data/models.dart';
import 'package:rental_manager/data/repository.dart';
import 'package:rental_manager/screens/room_detail_screen.dart';
import 'package:rental_manager/screens/termination_screen.dart';

/// Ảnh PNG hợp lệ nhỏ, để Image.memory giải mã được khi test.
Uint8List _tinyPng() =>
    Uint8List.fromList(img.encodePng(img.Image(width: 2, height: 2)));

void main() {
  testWidgets('thanh lý: nút xác nhận bị khóa khi chưa có ảnh', (tester) async {
    final repo = MockRentalRepository();
    final room = await repo.getRoom('r-A101');
    await tester.pumpWidget(
      MaterialApp(
        home: RoomDetailScreen(room: room, repository: repo),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Thanh lý hợp đồng'));
    await tester.pumpAndSettle();

    expect(find.byType(TerminationScreen), findsOneWidget);
    expect(find.text('Ảnh kiểm tra phòng'), findsOneWidget);
    expect(find.text('Ảnh thanh lý'), findsOneWidget);
    expect(find.text('Quyết toán'), findsOneWidget);
    // Chưa có ảnh: bấm nút không được mở hộp thoại xác nhận.
    final confirm = find.descendant(
      of: find.byType(TerminationScreen),
      matching: find.text('Thanh lý hợp đồng'),
    );
    await tester.dragUntilVisible(
      confirm,
      find.descendant(
        of: find.byType(TerminationScreen),
        matching: find.byType(ListView),
      ),
      const Offset(0, -200),
    );
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(
      find.text('Cần chọn ảnh kiểm tra và ảnh thanh lý trước khi thanh lý.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'thanh lý xong: phòng hiện Hết hạn, có ảnh đã lưu và nút mở lại',
    (tester) async {
      final repo = MockRentalRepository();
      final vacant = (await repo.listRooms(status: RoomStatus.vacant)).first;
      final tenant = await repo.createTenant(
        fullName: 'Trần Thị B',
        phone: '0901234567',
        citizenId: '012345678901',
      );
      await repo.createContract(
        roomId: vacant.id,
        tenantId: tenant.id,
        startDate: DateTime(2026, 10, 1),
        rent: 3000000,
        deposit: 500000,
      );
      final png = _tinyPng();
      await repo.terminateContract(
        roomId: vacant.id,
        inspectionPhotos: [png],
        liquidationPhotos: [png],
      );

      final room = await repo.getRoom(vacant.id);
      await tester.pumpWidget(
        MaterialApp(
          home: RoomDetailScreen(room: room, repository: repo),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Trạng thái: ${RoomStatus.expired.label}'),
        findsOneWidget,
      );
      expect(find.text('Mở lại cho thuê'), findsOneWidget);
      expect(find.text('Thanh lý hợp đồng'), findsNothing);
      // Phòng Hết hạn chưa được ký hợp đồng mới cho đến khi mở lại.
      expect(find.text('Thêm người thuê & hợp đồng'), findsNothing);
      expect(find.text('Ảnh kiểm tra & thanh lý'), findsOneWidget);
      expect(find.byType(Image), findsNWidgets(2));
    },
  );

  testWidgets('quyết toán hiển thị số tiền hoàn khi cọc lớn hơn nợ', (
    tester,
  ) async {
    final repo = MockRentalRepository();
    final vacant = (await repo.listRooms(status: RoomStatus.vacant)).first;
    final tenant = await repo.createTenant(
      fullName: 'Trần Thị B',
      phone: '0901234567',
      citizenId: '012345678901',
    );
    await repo.createContract(
      roomId: vacant.id,
      tenantId: tenant.id,
      startDate: DateTime(2026, 10, 1),
      rent: 3000000,
      deposit: 500000,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: TerminationScreen(
          room: await repo.getRoom(vacant.id),
          repository: repo,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Trừ tiền cọc'), findsOneWidget);
    expect(find.text('Hoàn lại khách'), findsOneWidget);
    expect(find.text(formatVnd(500000)), findsWidgets);
  });
}
