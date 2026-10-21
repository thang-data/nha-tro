import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rental_manager/data/models.dart';
import 'package:rental_manager/data/repository.dart';
import 'package:rental_manager/screens/meter_reading_screen.dart';

void main() {
  testWidgets('chỉ số cuối nhỏ hơn đầu bị chặn và không lưu', (tester) async {
    final repo = MockRentalRepository();
    await tester.pumpWidget(
      MaterialApp(home: MeterReadingScreen(repository: repo)),
    );
    await tester.pumpAndSettle();

    final before = (await repo.listMeterReadings(roomId: 'r-A101')).length;

    await tester.enterText(
      find.byKey(const ValueKey('elec-start-A101')),
      '100',
    );
    await tester.enterText(find.byKey(const ValueKey('elec-end-A101')), '50');
    await tester.pumpAndSettle();

    expect(find.text('Cuối phải ≥ đầu'), findsOneWidget);

    await tester.tap(find.text('Lưu nháp'));
    await tester.pumpAndSettle();

    expect((await repo.listMeterReadings(roomId: 'r-A101')).length, before);
    expect(
      (await repo.listMeterReadings(roomId: 'r-A101'))
          .any((m) => m.kind == MeterKind.electric && m.startValue == 100),
      isFalse,
    );
  });
}
