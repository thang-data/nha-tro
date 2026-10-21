import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../data/billing.dart';
import '../data/models.dart';
import 'common.dart';

/// Kỳ của hóa đơn thanh lý, hiển thị với tiêu đề "HÓA ĐƠN TRẢ CỌC".
const settlementPeriod = 'Thanh lý';

/// Dựng PDF hóa đơn theo đúng bố cục của [receiptRows].
/// Font mặc định tải từ Google Fonts (Noto Sans) để hiện đủ tiếng Việt.
Future<Uint8List> buildInvoicePdf({
  required Invoice invoice,
  required String siteName,
  pw.Font? regular,
  pw.Font? bold,
}) async {
  final base = regular ?? await PdfGoogleFonts.notoSansRegular();
  final strong = bold ?? await PdfGoogleFonts.notoSansBold();
  final doc = pw.Document(
    theme: pw.ThemeData.withFont(base: base, bold: strong),
  );
  final title = invoice.period == settlementPeriod
      ? 'HÓA ĐƠN TRẢ CỌC'
      : 'HÓA ĐƠN TIỀN THUÊ';
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      build: (_) => [
        pw.Center(
          child: pw.Text(
            title,
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.SizedBox(height: 16),
        _headerRow('Cơ sở', siteName),
        _headerRow('Số phòng', invoice.roomCode),
        _headerRow('Kỳ', invoice.period),
        _headerRow('Người thuê', invoice.tenant),
        _headerRow('Hạn thanh toán', formatDate(invoice.dueDate)),
        _headerRow('Mã hóa đơn', invoice.id),
        pw.SizedBox(height: 12),
        pw.Table(
          border: const pw.TableBorder(
            horizontalInside: pw.BorderSide(
              color: PdfColors.grey300,
              width: 0.5,
            ),
          ),
          columnWidths: {
            0: const pw.FlexColumnWidth(3),
            1: const pw.FlexColumnWidth(1.6),
            2: const pw.FlexColumnWidth(1.5),
          },
          children: [
            for (final row in receiptRows(invoice))
              pw.TableRow(
                children: [
                  _cell(row.label, bold: row.bold, indent: row.indent),
                  _cell(row.note, grey: true),
                  _cell(row.value, bold: row.bold, right: true),
                ],
              ),
          ],
        ),
      ],
    ),
  );
  return doc.save();
}

pw.Widget _headerRow(String label, String value) => pw.Padding(
  padding: const pw.EdgeInsets.symmetric(vertical: 2),
  child: pw.Row(
    children: [
      pw.SizedBox(width: 120, child: pw.Text(label)),
      pw.Expanded(child: pw.Text(value)),
    ],
  ),
);

pw.Widget _cell(
  String text, {
  bool bold = false,
  bool indent = false,
  bool right = false,
  bool grey = false,
}) {
  return pw.Padding(
    padding: pw.EdgeInsets.fromLTRB(indent ? 16 : 0, 4, 6, 4),
    child: pw.Text(
      text,
      textAlign: right ? pw.TextAlign.right : pw.TextAlign.left,
      style: pw.TextStyle(
        fontSize: grey ? 9 : 10,
        color: grey ? PdfColors.grey700 : PdfColors.black,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      ),
    ),
  );
}

/// Mở hộp thoại in của trình duyệt/thiết bị, có thể lưu thành PDF.
Future<void> printInvoicePdf(Uint8List bytes, String name) =>
    Printing.layoutPdf(name: name, onLayout: (_) async => bytes);
