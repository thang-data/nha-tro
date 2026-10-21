import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rental_manager/data/billing.dart';
import 'package:rental_manager/data/models.dart';
import 'package:rental_manager/data/repository.dart';
import 'package:rental_manager/screens/meter_reading_screen.dart';

void main() {
  testWidgets('chốt kỳ tự lập hóa đơn cho các phòng đang thuê', (tester) async {
    final repo = MockRentalRepository();
    for (final site in await repo.listSites()) {
      await repo.updateSite(
        site.copyWith(electricRate: 3500, waterRate: 20000),
      );
    }
    final occupied = await repo.listRooms(status: RoomStatus.occupied);
    const period = 'Tháng 11/2026';

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => MeterReadingScreen(repository: repo),
                ),
              ),
              child: const Text('mở'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('mở'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Kỳ tính tiền'),
      period,
    );
    for (final room in occupied) {
      await tester.enterText(
        find.byKey(ValueKey('elec-start-${room.code}')),
        '100',
      );
      await tester.enterText(
        find.byKey(ValueKey('elec-end-${room.code}')),
        '150',
      );
      await tester.enterText(
        find.byKey(ValueKey('water-start-${room.code}')),
        '10',
      );
      await tester.enterText(
        find.byKey(ValueKey('water-end-${room.code}')),
        '13',
      );
    }
    await tester.pumpAndSettle();

    expect(await repo.listInvoices(period: period), isEmpty);
    await tester.tap(find.text('Chốt kỳ'));
    await tester.pumpAndSettle();

    final invoices = await repo.listInvoices(period: period);
    expect(invoices, hasLength(occupied.length));
    for (final room in occupied) {
      expect(
        invoices.where(
          (i) => i.siteId == room.siteId && i.roomCode == room.code,
        ),
        hasLength(1),
        reason: 'Mỗi phòng đang thuê có đúng một hóa đơn của kỳ',
      );
    }
    expect(invoices.every((i) => i.lines.isNotEmpty), isTrue);
    expect(periodOf(DateTime(2026, 11, 3)), period);
  });
}
