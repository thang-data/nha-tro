import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:rental_manager/data/repository.dart';
import 'package:rental_manager/screens/invoice_pdf.dart';

void main() {
  test('buildInvoicePdf tạo file PDF hợp lệ cho hóa đơn có thu tiền', () async {
    final repo = MockRentalRepository(clock: () => DateTime(2026, 10, 20));
    await repo.recordPayment(
      invoiceId: 'INV-2610-001',
      amount: 500000,
      method: 'transfer',
      reference: 'FT999',
      idempotencyKey: 'k-pdf',
    );
    final invoice = await repo.getInvoice('INV-2610-001');

    final bytes = await buildInvoicePdf(
      invoice: invoice,
      siteName: 'TP1',
      regular: pw.Font.helvetica(),
      bold: pw.Font.helveticaBold(),
    );

    expect(bytes.length, greaterThan(1000));
    expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
  });
}
