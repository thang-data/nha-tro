import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:rental_manager/core/image_compress.dart';
import 'package:rental_manager/data/billing.dart';
import 'package:rental_manager/data/models.dart';
import 'package:rental_manager/data/repository.dart';

Invoice _invoice(String id, int total, int paid) => Invoice(
  id: id,
  roomCode: 'A102',
  tenant: 'Nguyễn Văn A',
  period: 'Tháng 9/2026',
  total: total,
  dueDate: DateTime(2026, 9, 7),
  payments: [
    if (paid > 0)
      Payment(
        id: 'p-$id',
        invoiceId: id,
        amount: paid,
        method: 'cash',
        paidAt: DateTime(2026, 9, 8),
        idempotencyKey: 'k-$id',
      ),
  ],
);

void main() {
  test('settlementLines cộng nợ cũ và trừ tiền cọc', () {
    final lines = settlementLines(
      unpaid: [_invoice('INV-1', 1000, 200), _invoice('INV-2', 500, 0)],
      deposit: 300,
    );
    expect(lines.map((l) => l.amount), [800, 500, -300]);
    expect(linesTotal(lines), 1000);
    expect(lines.first.label, 'Còn nợ Tháng 9/2026');
  });

  test('settlementLines cho tổng âm khi tiền cọc lớn hơn nợ (hoàn khách)', () {
    final lines = settlementLines(unpaid: const [], deposit: 500000);
    expect(linesTotal(lines), -500000);
  });

  test('settlementLines không có nợ và không cọc thì không có dòng nào', () {
    expect(settlementLines(unpaid: const [], deposit: 0), isEmpty);
    expect(
      () => settlementLines(unpaid: const [], deposit: -1),
      throwsArgumentError,
    );
  });

  test('thanh lý cần đủ ảnh kiểm tra và ảnh thanh lý', () async {
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
    final photo = Uint8List.fromList([1, 2, 3]);
    expect(
      () => repo.terminateContract(
        roomId: vacant.id,
        inspectionPhotos: [photo],
        liquidationPhotos: const [],
      ),
      throwsA(isA<TerminationNeedsPhotosException>()),
    );
    expect(
      await repo.activeContractForRoom(vacant.id),
      isNotNull,
      reason: 'Thiếu ảnh thì hợp đồng vẫn còn hiệu lực',
    );
  });

  test('thanh lý: phòng sang Hết hạn, có ảnh, hoàn cọc; mở lại được', () async {
    final repo = MockRentalRepository(clock: () => DateTime(2026, 10, 20));
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

    final result = await repo.terminateContract(
      roomId: vacant.id,
      inspectionPhotos: [
        Uint8List.fromList([1]),
      ],
      liquidationPhotos: [
        Uint8List.fromList([2]),
        Uint8List.fromList([3]),
      ],
    );
    expect(result.contract.isActive, isFalse);
    expect(result.settlement?.total, -500000, reason: 'Hoàn lại khách 500.000');

    final room = await repo.getRoom(vacant.id);
    expect(room.status, RoomStatus.expired);
    expect(room.tenantName, isNull);
    expect(await repo.activeContractForRoom(vacant.id), isNull);

    final photos = await repo.listRoomPhotos(vacant.id);
    expect(photos.where((p) => p.kind == PhotoKind.inspection), hasLength(1));
    expect(photos.where((p) => p.kind == PhotoKind.liquidation), hasLength(2));

    await repo.updateRoom(
      room.copyWith(status: RoomStatus.vacant, clearTenant: true),
    );
    expect((await repo.getRoom(vacant.id)).status, RoomStatus.vacant);
  });

  test(
    'compressPhoto đưa ảnh lớn xuống cạnh dài tối đa 1280px và dưới giới hạn',
    () {
      final big = img.Image(width: 4000, height: 3000);
      for (var y = 0; y < big.height; y++) {
        for (var x = 0; x < big.width; x++) {
          big.setPixelRgb(x, y, x % 256, y % 256, (x + y) % 256);
        }
      }
      final out = compressPhoto(Uint8List.fromList(img.encodePng(big)));
      expect(out, isNotNull);
      expect(out!.length, lessThanOrEqualTo(maxPhotoBytes));
      final decoded = img.decodeImage(out)!;
      expect(decoded.width, lessThanOrEqualTo(1280));
      expect(
        decoded.width >= decoded.height,
        isTrue,
        reason: 'Giữ hướng ngang',
      );
    },
  );

  test('compressPhoto trả về null với dữ liệu không phải ảnh', () {
    expect(compressPhoto(Uint8List.fromList([1, 2, 3, 4])), isNull);
  });

  test(
    'thanh lý chuyển nợ cũ sang hóa đơn thanh lý, không thu trùng',
    () async {
      final repo = MockRentalRepository(clock: () => DateTime(2026, 10, 20));
      final owed = (await repo.getInvoice('INV-2610-001')).remaining;
      expect(owed, greaterThan(0));
      final result = await repo.terminateContract(
        roomId: 'r-A101',
        inspectionPhotos: [
          Uint8List.fromList([1]),
        ],
        liquidationPhotos: [
          Uint8List.fromList([2]),
        ],
      );
      final settlement = result.settlement!;
      expect(settlement.period, 'Thanh lý');
      expect(settlement.lines.first.label, 'Còn nợ Tháng 10/2026');
      expect(settlement.total, owed);

      final old = await repo.getInvoice('INV-2610-001');
      expect(old.remaining, 0);
      expect(old.payments.last.method, Payment.settlementMethod);
      expect(old.payments.last.reference, settlement.id);
    },
  );

  test('ghi nhận thu kèm ảnh chứng từ, ảnh đọc lại được', () async {
    final repo = MockRentalRepository();
    final proof = Uint8List.fromList([9, 8, 7]);
    final payment = await repo.recordPayment(
      invoiceId: 'INV-2610-001',
      amount: 1000000,
      method: 'transfer',
      reference: 'FT123',
      idempotencyKey: 'k-proof',
      proof: proof,
    );
    expect(payment.proofPhotoId, isNotNull);
    final photo = await repo.getPhoto(payment.proofPhotoId!);
    expect(photo!.kind, PhotoKind.paymentProof);
    expect(photo.invoiceId, 'INV-2610-001');
    expect(base64Decode(photo.data), proof);
  });
}
