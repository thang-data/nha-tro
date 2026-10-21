import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rental_manager/data/billing.dart';
import 'package:rental_manager/data/models.dart';
import 'package:rental_manager/data/repository.dart';

void main() {
  test(
    'đổi giá phòng đang thuê thì hợp đồng và hóa đơn mới dùng giá mới',
    () async {
      final repo = MockRentalRepository(clock: () => DateTime(2026, 11, 3));
      for (final site in await repo.listSites()) {
        await repo.updateSite(
          site.copyWith(electricRate: 3500, waterRate: 20000),
        );
      }
      final room = await repo.getRoom('r-A101');
      expect((await repo.activeContractForRoom(room.id))!.rent, 3000000);

      await repo.updateRoom(room.copyWith(rent: 3500000));
      expect((await repo.getRoom(room.id)).rent, 3500000);
      expect((await repo.activeContractForRoom(room.id))!.rent, 3500000);

      // Chốt chỉ số kỳ 11/2026 rồi lập hóa đơn: tiền phòng phải là giá mới.
      for (final kind in MeterKind.values) {
        final r = await repo.submitMeterReading(
          roomId: room.id,
          period: 'Tháng 11/2026',
          kind: kind,
          startValue: 100,
          endValue: 110,
        );
        await repo.confirmMeterReading(r.id);
      }
      await repo.proposeInvoices(period: 'Tháng 11/2026');
      final invoices = await repo.listInvoices(period: 'Tháng 11/2026');
      final mine = invoices.singleWhere((i) => i.roomCode == 'A101');
      expect(mine.lines.first.label, 'Tiền phòng');
      expect(mine.lines.first.amount, 3500000);
      expect(periodOf(DateTime(2026, 11, 3)), 'Tháng 11/2026');
    },
  );

  test('sửa giá trên hợp đồng thì giá phòng đổi theo; hợp đồng đã thanh lý không sửa được', () async {
    final repo = MockRentalRepository();
    final contract = (await repo.activeContractForRoom('r-A101'))!;
    final updated = await repo.updateContract(
      contract.copyWith(rent: 1000000, deposit: 2000000),
    );
    expect(updated.rent, 1000000);
    expect(updated.deposit, 2000000);
    expect((await repo.getRoom('r-A101')).rent, 1000000);

    await repo.terminateContract(
      roomId: 'r-A101',
      inspectionPhotos: [
        Uint8List.fromList([1]),
      ],
      liquidationPhotos: [
        Uint8List.fromList([2]),
      ],
    );
    await expectLater(
      repo.updateContract(updated.copyWith(rent: 5000000)),
      throwsA(isA<StateError>()),
    );
  });

  test('đổi giá thì hóa đơn kỳ hiện tại chưa thu đổi theo, hóa đơn đã thu giữ nguyên', () async {
    final repo = MockRentalRepository(clock: () => DateTime(2026, 11, 3));
    for (final site in await repo.listSites()) {
      await repo.updateSite(
        site.copyWith(electricRate: 3500, waterRate: 20000),
      );
    }
    for (final roomId in ['r-A101', 'r-B101']) {
      for (final kind in MeterKind.values) {
        final r = await repo.submitMeterReading(
          roomId: roomId,
          period: 'Tháng 11/2026',
          kind: kind,
          startValue: 100,
          endValue: 110,
        );
        await repo.confirmMeterReading(r.id);
      }
    }
    await repo.proposeInvoices(period: 'Tháng 11/2026');
    final invoices = await repo.listInvoices(period: 'Tháng 11/2026');
    final paid = invoices.singleWhere((i) => i.roomCode == 'A101');
    final unpaid = invoices.singleWhere((i) => i.roomCode == 'B101');
    await repo.recordPayment(
      invoiceId: paid.id,
      amount: 100000,
      method: 'cash',
      idempotencyKey: 'k-reprice',
    );

    final contractB = (await repo.activeContractForRoom('r-B101'))!;
    await repo.updateContract(
      contractB.copyWith(rent: contractB.rent + 1000000),
    );

    final repriced = await repo.getInvoice(unpaid.id);
    expect(repriced.lines.first.amount, contractB.rent + 1000000);
    expect(repriced.total, unpaid.total + 1000000);
    expect(
      (await repo.getInvoice(paid.id)).total,
      paid.total,
      reason: 'Hóa đơn đã thu giữ nguyên số tiền',
    );
  });

  test(
    'đổi giá đổi cả hóa đơn kỳ trước chưa thu, syncUnpaidRents không đổi thêm',
    () async {
      final repo = MockRentalRepository(clock: () => DateTime(2026, 10, 20));
      for (final site in await repo.listSites()) {
        await repo.updateSite(
          site.copyWith(electricRate: 3500, waterRate: 20000),
        );
      }
      for (final kind in MeterKind.values) {
        final r = await repo.submitMeterReading(
          roomId: 'r-B101',
          period: 'Tháng 8/2026',
          kind: kind,
          startValue: 100,
          endValue: 110,
        );
        await repo.confirmMeterReading(r.id);
      }
      await repo.proposeInvoices(period: 'Tháng 8/2026');
      final sep = (await repo.listInvoices(period: 'Tháng 8/2026'))
          .singleWhere((i) => i.roomCode == 'B101');
      final room = await repo.getRoom('r-B101');

      await repo.updateRoom(room.copyWith(rent: room.rent + 1000000));

      final repriced = await repo.getInvoice(sep.id);
      expect(
        repriced.lines.firstWhere((l) => l.label == 'Tiền phòng').amount,
        room.rent + 1000000,
      );
      expect(await repo.syncUnpaidRents(), 0);
    },
  );
}
