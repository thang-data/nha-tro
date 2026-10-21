import 'package:flutter_test/flutter_test.dart';
import 'package:rental_manager/data/billing.dart';
import 'package:rental_manager/data/models.dart';

Invoice _invoice({
  required List<InvoiceLine> lines,
  List<Payment> payments = const [],
  String period = 'Tháng 3/2026',
}) => Invoice(
  id: 'INV-1',
  siteId: 's1',
  roomCode: '107GB',
  tenant: 'Nguyễn Văn A',
  period: period,
  total: linesTotal(lines),
  dueDate: DateTime(2026, 3, 7),
  payments: payments,
  lines: lines,
);

String _value(List<ReceiptRow> rows, String label) =>
    rows.firstWhere((r) => r.label == label).value;

void main() {
  test('bố cục theo mẫu: tiền phòng, điện chỉ số, nước, dịch vụ, tổng', () {
    final lines = [
      InvoiceLine(
        label: 'Tiền phòng',
        description: '',
        amount: 2900000,
        section: 'Tiền phòng',
        unitPrice: 2900000,
      ),
      electricLine(175, 3400, start: 10536, end: 10711),
      waterLine(4, 20000, start: 168, end: 172),
      serviceLine(
        name: 'Tiền rác và vệ sinh',
        unit: ServiceUnit.fixed,
        unitPrice: 108000,
        quantity: 1,
      ),
      serviceLine(
        name: 'Tiền xe',
        unit: ServiceUnit.fixed,
        unitPrice: 180000,
        quantity: 1,
      ),
    ];
    final rows = receiptRows(_invoice(lines: lines));
    final labels = rows.map((r) => r.label).toList();

    expect(labels.take(3), ['Tiền phòng', 'Đơn giá', 'Thành tiền']);
    expect(_value(rows, 'Đơn giá'), '2.900.000');
    expect(labels, contains('Tiền điện'));
    expect(
      labels,
      containsAllInOrder(['-- Đầu kỳ', '-- Cuối kỳ', '-- Tiêu thụ']),
    );
    expect(_value(rows, '-- Đầu kỳ'), '10.536');
    expect(_value(rows, '-- Tiêu thụ'), '175 kWh');
    expect(labels, contains('Tiền nước'));
    expect(labels, contains('Tiền dịch vụ'));
    expect(_value(rows, '-- Tiền xe'), '180.000');
    expect(_value(rows, 'TỔNG CỘNG'), '3.863.000 đ');
    expect(_value(rows, 'Số tiền trả trước'), '0 đ');
    expect(_value(rows, 'Số tiền trả cuối'), '-3.863.000 đ');
  });

  test('dịch vụ theo tháng có số lượng thì hiện số lượng × đơn giá', () {
    final lines = [
      serviceLine(
        name: 'Nước uống',
        unit: ServiceUnit.monthly,
        unitPrice: 15000,
        quantity: 3,
      ),
      serviceLine(
        name: 'Tiền xe',
        unit: ServiceUnit.fixed,
        unitPrice: 180000,
        quantity: 1,
      ),
    ];
    final rows = receiptRows(_invoice(lines: lines));
    final water = rows.firstWhere((r) => r.label == '-- Nước uống');
    expect(water.note, '3 × 15.000 đ');
    expect(water.value, '45.000');
    expect(rows.firstWhere((r) => r.label == '-- Tiền xe').note, '');
  });

  test('có đã thu thì trả trước tăng, trả cuối tiến về 0 khi thu đủ', () {
    final lines = [
      InvoiceLine(label: 'Tiền phòng', description: '', amount: 1000000),
    ];
    final paid = Payment(
      id: 'p1',
      invoiceId: 'INV-1',
      amount: 1000000,
      method: 'cash',
      paidAt: DateTime(2026, 3, 8),
      idempotencyKey: 'k1',
    );
    final rows = receiptRows(_invoice(lines: lines, payments: [paid]));
    expect(_value(rows, 'Đã thu'), '1.000.000 đ');
    expect(_value(rows, 'Số tiền trả cuối'), '0 đ');
  });

  test(
    'thanh lý: nợ cũ và tiền cọc nằm ở phần trả trước, không ở nhóm khoản thu',
    () {
      final lines = [
        InvoiceLine(
          label: 'Còn nợ Tháng 2/2026',
          description: 'Hóa đơn INV-0',
          amount: 500000,
          section: 'Công nợ',
        ),
        InvoiceLine(label: depositLabel, description: '', amount: -2800000),
      ];
      final rows = receiptRows(_invoice(lines: lines, period: 'Thanh lý'));
      expect(rows.first.label, 'Công nợ');
      expect(rows.any((r) => r.label == depositLabel), isFalse);
      expect(_value(rows, 'TỔNG CỘNG'), '500.000 đ');
      expect(_value(rows, 'Tiền cọc'), '2.800.000 đ');
      expect(_value(rows, 'Số tiền trả cuối'), '2.300.000 đ');
    },
  );

  test(
    'hóa đơn cũ không có chi tiết: lấy tiêu thụ và số lượng từ công thức',
    () {
      final lines = [
        InvoiceLine(
          label: 'Điện',
          description: '120 kWh × 3.500 đ',
          amount: 420000,
        ),
        InvoiceLine(
          label: 'Nước',
          description: '8 m³ × 20000đ',
          amount: 160000,
        ),
        InvoiceLine(
          label: 'Nước uống',
          description: '3 × 15000 đ',
          amount: 45000,
        ),
      ];
      final rows = receiptRows(_invoice(lines: lines));
      expect(_value(rows, 'Đơn giá'), '3.500');
      expect(_value(rows, '-- Tiêu thụ'), '120 kWh');
      expect(rows.where((r) => r.label == '-- Tiêu thụ').length, 2);
      expect(_value(rows, '-- Số lượng'), '3');
      expect(
        rows.where((r) => r.label == 'Đơn giá').map((r) => r.value).toList(),
        ['3.500', '20.000', '15.000'],
      );
    },
  );
}
