import 'package:flutter_test/flutter_test.dart';
import 'package:rental_manager/data/billing.dart';
import 'package:rental_manager/data/models.dart';
import 'package:rental_manager/data/repository.dart';

void main() {
  test('parsePeriod đọc "Tháng 10/2026" và từ chối định dạng sai', () {
    final p = parsePeriod('Tháng 10/2026');
    expect(p.year, 2026);
    expect(p.month, 10);
    expect(() => parsePeriod('2026-10'), throwsArgumentError);
    expect(() => parsePeriod('Tháng 13/2026'), throwsArgumentError);
  });

  test('hạn thanh toán 7 ngày là ngày 7 của kỳ', () {
    expect(dueDateFor(2026, 10, 7), DateTime(2026, 10, 7));
  });

  test('buildRoomBill cộng đủ tiền phòng, điện, nước và dịch vụ', () {
    const site = Site(
      id: 's',
      name: 'A',
      address: '',
      electricRate: 3500,
      waterRate: 20000,
    );
    MeterReading reading(MeterKind kind, int start, int end) => MeterReading(
      id: 'm',
      roomId: 'r',
      period: 'Tháng 10/2026',
      kind: kind,
      startValue: start,
      endValue: end,
      status: ReadingStatus.confirmed,
    );
    final draft = buildRoomBill(
      rent: 3000000,
      site: site,
      electric: reading(MeterKind.electric, 100, 150),
      water: reading(MeterKind.water, 10, 13),
      services: [
        (
          name: 'Internet',
          unit: ServiceUnit.fixed,
          unitPrice: 100000,
          quantity: 1,
        ),
      ],
    );
    expect(draft.problem, isNull);
    // 3.000.000 + 50 × 3.500 + 3 × 20.000 + 100.000
    expect(draft.total, 3000000 + 175000 + 60000 + 100000);
  });

  test('buildRoomBill báo lý do khi thiếu chỉ số hoặc đơn giá', () {
    const noRate = Site(id: 's', name: 'A', address: '');
    final draft = buildRoomBill(
      rent: 1,
      site: noRate,
      electric: null,
      water: null,
      services: const [],
    );
    expect(draft.problem, 'chưa chốt chỉ số điện');
  });

  test('mock: cơ sở chưa có đơn giá thì phòng bị bỏ qua có lý do', () async {
    final repo = MockRentalRepository();
    final result = await repo.proposeInvoices(period: 'Tháng 1/2020');
    expect(result.created, 0);
    expect(result.skipped, isNotEmpty);
  });
}
