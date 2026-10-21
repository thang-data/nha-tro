import '../core/money.dart';
import 'models.dart';

/// Tên dòng trừ tiền cọc trong hóa đơn thanh lý. Dòng này hiển thị ở phần trả trước, không ở các nhóm khoản thu.
const depositLabel = 'Trừ tiền cọc';

/// Tính tổng hóa đơn từ dữ liệu đã chốt. Hàm thuần, không phụ thuộc UI,
/// để có thể kiểm thử và tái tính được tổng tiền.
class InvoiceBreakdown {
  const InvoiceBreakdown({
    required this.rent,
    required this.electricity,
    required this.water,
    required this.services,
  });

  final int rent;
  final int electricity;
  final int water;
  final int services;

  int get total => rent + electricity + water + services;
}

InvoiceBreakdown calculateInvoice({
  required int rent,
  required int kwhUsed,
  required int electricityRate,
  required int m3Used,
  required int waterRate,
  required int services,
}) {
  if (kwhUsed < 0 || m3Used < 0) {
    throw ArgumentError('Chỉ số tiêu thụ không được âm');
  }
  return InvoiceBreakdown(
    rent: rent,
    electricity: kwhUsed * electricityRate,
    water: m3Used * waterRate,
    services: services,
  );
}

/// Số tiền còn phải trả = tổng hóa đơn - tổng đã thu hợp lệ (không âm).
int outstandingAmount(int total, Iterable<int> payments) {
  final paid = payments.fold<int>(0, (sum, p) => sum + p);
  final remaining = total - paid;
  return remaining < 0 ? 0 : remaining;
}

/// Kỳ hiện tại của một ngày, theo định dạng "Tháng 10/2026".
String periodOf(DateTime d) => 'Tháng ${d.month}/${d.year}';

/// Kỳ dạng "Tháng 10/2026" → (năm, tháng). Ném ArgumentError nếu sai định dạng.
({int year, int month}) parsePeriod(String period) {
  final m = RegExp(r'(\d{1,2})\s*/\s*(\d{4})').firstMatch(period);
  if (m == null) throw ArgumentError('Kỳ phải dạng "Tháng 10/2026"');
  final month = int.parse(m.group(1)!);
  if (month < 1 || month > 12) throw ArgumentError('Tháng không hợp lệ');
  return (year: int.parse(m.group(2)!), month: month);
}

/// Hạn thanh toán: tính từ ngày 1 của kỳ, ví dụ 7 ngày → ngày 7 của kỳ.
DateTime dueDateFor(int year, int month, int paymentDueDays) =>
    DateTime(year, month, 1).add(Duration(days: paymentDueDays - 1));

InvoiceLine electricLine(int kwh, int rate, {int? start, int? end}) =>
    InvoiceLine(
      label: 'Điện',
      description: '$kwh kWh × $rate đ',
      amount: kwh * rate,
      section: 'Tiền điện',
      unitPrice: rate,
      details: [
        if (start != null && end != null) ...[
          InvoiceDetail(label: 'Đầu kỳ', value: formatNumber(start)),
          InvoiceDetail(label: 'Cuối kỳ', value: formatNumber(end)),
        ],
        InvoiceDetail(label: 'Tiêu thụ', value: '$kwh kWh'),
      ],
    );

InvoiceLine waterLine(int m3, int rate, {int? start, int? end}) => InvoiceLine(
  label: 'Nước',
  description: '$m3 m³ × $rate đ',
  amount: m3 * rate,
  section: 'Tiền nước',
  unitPrice: rate,
  details: [
    if (start != null && end != null) ...[
      InvoiceDetail(label: 'Đầu kỳ', value: formatNumber(start)),
      InvoiceDetail(label: 'Cuối kỳ', value: formatNumber(end)),
    ],
    InvoiceDetail(label: 'Tiêu thụ', value: '$m3 m³'),
  ],
);

/// Dịch vụ theo tháng: đơn giá × số lượng. Dịch vụ cố định: đơn giá một lần.
InvoiceLine serviceLine({
  required String name,
  required ServiceUnit unit,
  required int unitPrice,
  required int quantity,
}) {
  final effective = unit == ServiceUnit.fixed ? 1 : quantity;
  return InvoiceLine(
    label: name,
    description: effective == 1
        ? ''
        : '$effective × ${formatNumber(unitPrice)} đ',
    amount: unitPrice * effective,
    section: 'Tiền dịch vụ',
  );
}

/// Kết quả đề xuất hóa đơn cho một kỳ.
class InvoiceProposal {
  const InvoiceProposal({required this.created, required this.skipped});

  final int created;

  /// Mỗi phòng không lập được: "A101: chưa chốt chỉ số điện".
  final List<String> skipped;
}

/// Một dịch vụ đã gắn vào phòng, kèm số lượng của phòng đó.
typedef ServiceCharge = ({
  String name,
  ServiceUnit unit,
  int unitPrice,
  int quantity,
});

/// Các dòng của hóa đơn một phòng, hoặc lý do không lập được (problem).
class RoomBillDraft {
  const RoomBillDraft(this.lines, this.problem);

  final List<InvoiceLine> lines;
  final String? problem;

  int get total => lines.fold(0, (sum, l) => sum + l.amount);
}

/// Dựng hóa đơn một phòng từ tiền phòng, chỉ số đã chốt và dịch vụ.
/// Thiếu chỉ số đã chốt hoặc chưa có đơn giá thì không lập được hóa đơn.
RoomBillDraft buildRoomBill({
  required int rent,
  required Site site,
  required MeterReading? electric,
  required MeterReading? water,
  required List<ServiceCharge> services,
}) {
  if (electric == null) return const RoomBillDraft([], 'chưa chốt chỉ số điện');
  if (water == null) return const RoomBillDraft([], 'chưa chốt chỉ số nước');
  if (site.electricRate <= 0) {
    return const RoomBillDraft([], 'cơ sở chưa có đơn giá điện');
  }
  if (site.waterRate <= 0) {
    return const RoomBillDraft([], 'cơ sở chưa có đơn giá nước');
  }
  return RoomBillDraft([
    InvoiceLine(
      label: 'Tiền phòng',
      description: '',
      amount: rent,
      section: 'Tiền phòng',
      unitPrice: rent,
    ),
    electricLine(
      electric.consumption,
      site.electricRate,
      start: electric.startValue,
      end: electric.endValue,
    ),
    waterLine(
      water.consumption,
      site.waterRate,
      start: water.startValue,
      end: water.endValue,
    ),
    for (final s in services)
      serviceLine(
        name: s.name,
        unit: s.unit,
        unitPrice: s.unitPrice,
        quantity: s.quantity,
      ),
  ], null);
}

/// Các dòng hóa đơn thanh lý: cộng số còn nợ của từng hóa đơn cũ, rồi trừ tiền cọc.
/// Tổng âm nghĩa là phải hoàn lại cho người thuê.
List<InvoiceLine> settlementLines({
  required List<Invoice> unpaid,
  required int deposit,
}) {
  if (deposit < 0) throw ArgumentError('Tiền cọc không được âm');
  return [
    for (final inv in unpaid)
      if (inv.remaining > 0)
        InvoiceLine(
          label: 'Còn nợ ${inv.period}',
          description: 'Hóa đơn ${inv.id}',
          amount: inv.remaining,
          section: 'Công nợ',
        ),
    if (deposit > 0)
      InvoiceLine(label: depositLabel, description: '', amount: -deposit),
  ];
}

int linesTotal(Iterable<InvoiceLine> lines) =>
    lines.fold(0, (sum, l) => sum + l.amount);

/// Đổi dòng "Tiền phòng" sang giá mới. Trả về null nếu không có dòng này hoặc đã đúng giá.
List<InvoiceLine>? repriceRent(List<InvoiceLine> lines, int rent) {
  final i = lines.indexWhere((l) => l.label == 'Tiền phòng');
  if (i < 0 || lines[i].amount == rent) return null;
  return [
    for (var j = 0; j < lines.length; j++)
      if (j == i)
        InvoiceLine(
          label: 'Tiền phòng',
          description: '',
          amount: rent,
          section: lines[i].section,
          unitPrice: rent,
        )
      else
        lines[j],
  ];
}

/// Một dòng hiển thị trên hóa đơn (phiếu tính tiền).
class ReceiptRow {
  const ReceiptRow(
    this.label,
    this.value, {
    this.bold = false,
    this.indent = false,
    this.note = '',
  });

  final String label;
  final String value;
  final bool bold;
  final bool indent;

  /// Số lượng × đơn giá của dịch vụ, ví dụ '3 × 15.000 đ'. Rỗng nếu không cần.
  final String note;
}

final _usagePattern = RegExp(r'^(\d[\d.,]*)\s*(kWh|m³)\s*×\s*([\d.,]+)\s*đ$');
final _quantityPattern = RegExp(r'^(\d+)\s*×\s*([\d.,]+)\s*đ$');

int _digits(String s) => int.parse(s.replaceAll(RegExp(r'[.,]'), ''));

/// Hóa đơn lập trước khi có chi tiết: lấy số tiêu thụ và đơn giá từ công thức hiển thị,
/// ví dụ '120 kWh × 3.500 đ' hoặc '3 × 15000 đ'.
({int? unitPrice, List<InvoiceDetail> details}) _legacyUsage(InvoiceLine line) {
  final text = line.description.trim();
  final usage = _usagePattern.firstMatch(text);
  if (usage != null) {
    return (
      unitPrice: _digits(usage.group(3)!),
      details: [
        InvoiceDetail(
          label: 'Tiêu thụ',
          value: '${usage.group(1)} ${usage.group(2)}',
        ),
      ],
    );
  }
  final quantity = _quantityPattern.firstMatch(text);
  if (quantity != null) {
    return (
      unitPrice: _digits(quantity.group(2)!),
      details: [InvoiceDetail(label: 'Số lượng', value: quantity.group(1)!)],
    );
  }
  return (unitPrice: null, details: const []);
}

/// Ghi chú "số lượng × đơn giá" cho dòng dịch vụ, định dạng số kiểu Việt Nam.
String _quantityNote(String description) {
  final m = _quantityPattern.firstMatch(description.trim());
  if (m == null) return description;
  return '${m.group(1)} × ${formatNumber(_digits(m.group(2)!))} đ';
}

/// Các dòng phiếu tính tiền theo đúng bố cục: từng nhóm khoản thu, TỔNG CỘNG, số tiền trả trước và trả cuối.
/// Dùng chung cho màn hình chi tiết và file PDF.
///
/// Số tiền trả cuối = trả trước − tổng cộng: âm là khách còn phải trả, dương là hoàn lại khách.
List<ReceiptRow> receiptRows(Invoice invoice) {
  final rows = <ReceiptRow>[];
  final visible = invoice.lines.where((l) => l.label != depositLabel).toList();
  var i = 0;
  while (i < visible.length) {
    final title = visible[i].section ?? visible[i].label;
    final group = <InvoiceLine>[];
    while (i < visible.length &&
        (visible[i].section ?? visible[i].label) == title) {
      group.add(visible[i]);
      i++;
    }
    rows.add(ReceiptRow(title, '', bold: true));
    if (group.length == 1) {
      final line = group.single;
      final legacy = _legacyUsage(line);
      final unitPrice = line.unitPrice ?? legacy.unitPrice;
      if (unitPrice != null) {
        rows.add(ReceiptRow('Đơn giá', formatNumber(unitPrice), indent: true));
      }
      for (final d in line.details.isEmpty ? legacy.details : line.details) {
        rows.add(ReceiptRow('-- ${d.label}', d.value, indent: true));
      }
      rows.add(
        ReceiptRow(
          'Thành tiền',
          formatNumber(line.amount),
          bold: true,
          indent: true,
        ),
      );
    } else {
      for (final l in group) {
        rows.add(
          ReceiptRow(
            '-- ${l.label}',
            formatNumber(l.amount),
            indent: true,
            note: _quantityNote(l.description),
          ),
        );
      }
      rows.add(
        ReceiptRow(
          'Thành tiền',
          formatNumber(linesTotal(group)),
          bold: true,
          indent: true,
        ),
      );
    }
  }

  final deposit = -invoice.lines
      .where((l) => l.label == depositLabel)
      .fold<int>(0, (sum, l) => sum + l.amount);
  final paid = invoice.payments.fold<int>(0, (sum, p) => sum + p.amount);
  final charges = invoice.total + deposit;
  final prepaid = deposit + paid;
  rows.add(ReceiptRow('TỔNG CỘNG', formatVnd(charges), bold: true));
  rows.add(ReceiptRow('Số tiền trả trước', formatVnd(prepaid), bold: true));
  if (deposit > 0) {
    rows.add(ReceiptRow('Tiền cọc', formatVnd(deposit), indent: true));
  }
  if (paid > 0) {
    rows.add(ReceiptRow('Đã thu', formatVnd(paid), indent: true));
  }
  rows.add(
    ReceiptRow('Số tiền trả cuối', formatVnd(prepaid - charges), bold: true),
  );
  return rows;
}

/// Doanh thu một kỳ theo tiền thực thu: các khoản thu có ngày thu trong kỳ.
/// Không tính khoản chuyển nợ sang hóa đơn thanh lý vì đó không phải tiền về tay.
class RevenueSummary {
  const RevenueSummary({required this.total, required this.bySite});

  final int total;

  /// Doanh thu theo mã cơ sở.
  final Map<String, int> bySite;
}

RevenueSummary revenueOf(Iterable<Invoice> invoices, String period) {
  var total = 0;
  final bySite = <String, int>{};
  for (final invoice in invoices) {
    for (final p in invoice.payments) {
      if (p.method == Payment.settlementMethod) continue;
      if (periodOf(p.paidAt) != period) continue;
      total += p.amount;
      bySite[invoice.siteId] = (bySite[invoice.siteId] ?? 0) + p.amount;
    }
  }
  return RevenueSummary(total: total, bySite: bySite);
}

/// Tổng chi phí trong kỳ, theo ngày phát sinh chi phí.
int expensesOf(Iterable<Expense> expenses, String period) => expenses
    .where((e) => periodOf(e.date) == period)
    .fold(0, (sum, e) => sum + e.amount);
