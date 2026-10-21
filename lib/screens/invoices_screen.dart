import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/money.dart';
import '../data/billing.dart';
import '../data/models.dart';
import '../data/repository.dart';
import 'common.dart';
import 'invoice_pdf.dart';
import 'meter_reading_screen.dart';
import 'photo_widgets.dart';

String _methodLabel(String method) => switch (method) {
  'transfer' => 'Chuyển khoản',
  Payment.settlementMethod => 'Chuyển sang hóa đơn thanh lý',
  _ => 'Tiền mặt',
};

/// Xem ảnh chứng từ đã lưu của một khoản thu.
Future<void> _showProof(
  BuildContext context,
  RentalRepository repo,
  String photoId,
) async {
  final photo = await repo.getPhoto(photoId);
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Ảnh chứng từ'),
      content: photo == null
          ? const Text('Không tìm thấy ảnh')
          : Image.memory(base64Decode(photo.data), fit: BoxFit.contain),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Đóng'),
        ),
      ],
    ),
  );
}

class InvoicesScreen extends StatefulWidget {
  const InvoicesScreen({super.key, this.repository});

  final RentalRepository? repository;

  @override
  State<InvoicesScreen> createState() => _InvoicesScreenState();
}

class _InvoicesScreenState extends State<InvoicesScreen> {
  late Future<List<Invoice>> _future;

  RentalRepository get _repo => widget.repository ?? appRepository;

  @override
  void initState() {
    super.initState();
    _future = _repo.listInvoices();
  }

  void _reload() {
    setState(() {
      _future = _repo.listInvoices();
    });
  }

  Future<void> _openMeterEntry() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => MeterReadingScreen(repository: widget.repository),
      ),
    );
    _reload();
  }

  /// Lập hóa đơn kỳ hiện tại ngay và cho biết phòng nào chưa lập được, và vì sao.
  Future<void> _proposeNow() async {
    final period = periodOf(DateTime.now());
    try {
      final result = await _repo.proposeInvoices(period: period);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Đã lập ${result.created} hóa đơn $period'),
          content: SizedBox(
            width: 420,
            child: result.skipped.isEmpty
                ? const Text('Không có phòng nào bị bỏ qua.')
                : SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Chưa lập được:'),
                        const SizedBox(height: 8),
                        for (final line in result.skipped) Text('• $line'),
                      ],
                    ),
                  ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Đóng'),
            ),
          ],
        ),
      );
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Lập hóa đơn thất bại: $e')));
    }
  }

  Future<void> _openInvoice(Invoice invoice) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => InvoiceDetailScreen(
          invoice: invoice,
          repository: widget.repository,
        ),
      ),
    );
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openMeterEntry,
        icon: const Icon(Icons.electric_meter_outlined),
        label: const Text('Nhập chỉ số'),
      ),
      body: FutureBuilder<List<Invoice>>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Không tải được dữ liệu: ${snap.error}'));
          }
          final invoices = snap.data;
          if (invoices == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return PageScaffold(
            title: 'Hóa đơn',
            children: [
              if (invoices.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Chưa có hóa đơn nào.'),
                        const SizedBox(height: 8),
                        const Text(
                          'Hóa đơn được lập tự động khi chốt chỉ số điện và nước của kỳ. '
                          'Phòng cần có hợp đồng đang thuê, cơ sở cần đơn giá điện và nước (mục Cơ sở).',
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: _proposeNow,
                          icon: const Icon(Icons.receipt_long),
                          label: Text(
                            'Lập hóa đơn ${periodOf(DateTime.now())}',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              for (final inv in invoices)
                _InvoiceCard(invoice: inv, onTap: () => _openInvoice(inv)),
            ],
          );
        },
      ),
    );
  }
}

class _InvoiceCard extends StatelessWidget {
  const _InvoiceCard({required this.invoice, required this.onTap});
  final Invoice invoice;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (invoice.statusAt(DateTime.now())) {
      InvoiceStatus.paid => ('Đã thu đủ', Colors.green),
      InvoiceStatus.overdue => ('Quá hạn', Colors.red),
      InvoiceStatus.partial => ('Thu một phần', Colors.orange),
      InvoiceStatus.unpaid => ('Chưa thu', Colors.blueGrey),
    };

    return Card(
      child: ListTile(
        onTap: onTap,
        title: Text('${invoice.roomCode} · ${invoice.period}'),
        subtitle: Text(
          '${invoice.tenant}\nHạn ${formatDate(invoice.dueDate)} · còn ${formatVnd(invoice.remaining)}',
        ),
        isThreeLine: true,
        trailing: StatusChip(label: label, color: color),
      ),
    );
  }
}

class InvoiceDetailScreen extends StatefulWidget {
  const InvoiceDetailScreen({
    super.key,
    required this.invoice,
    this.repository,
  });

  final Invoice invoice;
  final RentalRepository? repository;

  @override
  State<InvoiceDetailScreen> createState() => _InvoiceDetailScreenState();
}

class _InvoiceDetailScreenState extends State<InvoiceDetailScreen> {
  late Invoice _invoice = widget.invoice;

  RentalRepository get _repo => widget.repository ?? appRepository;

  Future<void> _exportPdf() async {
    try {
      final sites = await _repo.listSites();
      var siteName = '';
      for (final s in sites) {
        if (s.id == _invoice.siteId) siteName = s.name;
      }
      final bytes = await buildInvoicePdf(
        invoice: _invoice,
        siteName: siteName,
      );
      await printInvoicePdf(bytes, '${_invoice.id}.pdf');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Xuất PDF thất bại: $e')));
    }
  }

  Future<void> _recordPayment() async {
    final paid = await showModalBottomSheet<Payment>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PaymentSheet(
        invoiceId: _invoice.id,
        remaining: _invoice.remaining,
        repository: _repo,
      ),
    );
    if (paid == null) return;
    final fresh = await _repo.getInvoice(_invoice.id);
    if (!mounted) return;
    setState(() => _invoice = fresh);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Đã ghi nhận thu ${formatVnd(paid.amount)}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final invoice = _invoice;
    final remaining = invoice.remaining;
    return Scaffold(
      appBar: AppBar(
        title: Text(invoice.id),
        actions: [
          IconButton(
            tooltip: 'Xuất PDF',
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: _exportPdf,
          ),
        ],
      ),
      body: PageScaffold(
        title: '${invoice.roomCode} · ${invoice.period}',
        children: [
          const SizedBox(height: 16),
          Text(
            'Chi tiết hóa đơn',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _line('Số phòng', invoice.roomCode),
                  _line('Kỳ', invoice.period),
                  _line('Người thuê', invoice.tenant),
                  const Divider(),
                  for (final row in receiptRows(invoice)) _receiptLine(row),
                  const Divider(),
                  _line('Còn phải trả', formatVnd(remaining), bold: true),
                  _line('Hạn thanh toán', formatDate(invoice.dueDate)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Lịch sử thu tiền',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (invoice.payments.isEmpty)
            const Card(child: ListTile(title: Text('Chưa có giao dịch thu')))
          else
            for (var i = 0; i < invoice.payments.length; i++)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.payments_outlined),
                  title: Text(
                    'Thu lần ${i + 1} · ${_methodLabel(invoice.payments[i].method)}',
                  ),
                  subtitle: Text(
                    [
                      formatDateTime(invoice.payments[i].paidAt),
                      if (invoice.payments[i].reference != null)
                        'Mã: ${invoice.payments[i].reference}',
                    ].join(' · '),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(formatVnd(invoice.payments[i].amount)),
                      if (invoice.payments[i].proofPhotoId != null)
                        IconButton(
                          tooltip: 'Xem ảnh chứng từ',
                          icon: const Icon(Icons.image_outlined),
                          onPressed: () => _showProof(
                            context,
                            _repo,
                            invoice.payments[i].proofPhotoId!,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: remaining == 0 ? null : _recordPayment,
            icon: const Icon(Icons.add_card),
            label: const Text('Ghi nhận thu tiền'),
          ),
        ],
      ),
    );
  }

  Widget _receiptLine(ReceiptRow row) {
    final style = TextStyle(
      fontWeight: row.bold ? FontWeight.bold : FontWeight.normal,
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(row.indent ? 16 : 0, 3, 0, 3),
      child: Row(
        children: [
          Expanded(child: Text(row.label, style: style)),
          if (row.note.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(
                row.note,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.outline,
                  fontSize: 12,
                ),
              ),
            ),
          Text(row.value, style: style),
        ],
      ),
    );
  }

  Widget _line(String label, String value, {bool bold = false}) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}

/// Bottom sheet ghi nhận một khoản thu. Khóa idempotency tạo một lần khi mở sheet,
/// nên bấm lưu lại nhiều lần vẫn chỉ ghi một khoản.
class _PaymentSheet extends StatefulWidget {
  const _PaymentSheet({
    required this.invoiceId,
    required this.remaining,
    required this.repository,
  });

  final String invoiceId;
  final int remaining;
  final RentalRepository repository;

  @override
  State<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<_PaymentSheet> {
  final _amountCtrl = TextEditingController();
  final _refCtrl = TextEditingController();
  final _idempotencyKey = _newIdempotencyKey();
  String _method = 'cash';
  final _proof = <Uint8List>[];
  bool _saving = false;
  String? _error;

  static String _newIdempotencyKey() =>
      'pay-${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(0x7fffffff)}';

  @override
  void dispose() {
    _amountCtrl.dispose();
    _refCtrl.dispose();
    super.dispose();
  }

  Future<void> _addProof() async {
    final bytes = await pickCompressedPhoto(context);
    if (bytes == null || !mounted) return;
    setState(() => _proof.add(bytes));
  }

  Future<void> _submit() async {
    final amount = int.tryParse(
      _amountCtrl.text.replaceAll(RegExp(r'[^0-9]'), ''),
    );
    final reference = _refCtrl.text.trim();
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Số tiền phải lớn hơn 0');
      return;
    }
    if (amount > widget.remaining) {
      setState(
        () =>
            _error = 'Không được vượt số còn nợ ${formatVnd(widget.remaining)}',
      );
      return;
    }
    if (_method == 'transfer' && reference.isEmpty) {
      setState(() => _error = 'Chuyển khoản cần mã tham chiếu');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final payment = await widget.repository.recordPayment(
        invoiceId: widget.invoiceId,
        amount: amount,
        method: _method,
        reference: reference.isEmpty ? null : reference,
        idempotencyKey: _idempotencyKey,
        proof: _proof.isEmpty ? null : _proof.first,
      );
      if (mounted) Navigator.of(context).pop(payment);
    } on PaymentExceedsRemainingException catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } on ArgumentError catch (e) {
      if (mounted) setState(() => _error = '${e.message}');
    } catch (e) {
      if (mounted) setState(() => _error = 'Ghi nhận thu thất bại: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Ghi nhận thu tiền',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text('Còn phải trả: ${formatVnd(widget.remaining)}'),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('payment-amount'),
            controller: _amountCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Số tiền thu',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'cash', label: Text('Tiền mặt')),
              ButtonSegment(value: 'transfer', label: Text('Chuyển khoản')),
            ],
            selected: {_method},
            onSelectionChanged: (s) => setState(() => _method = s.first),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('payment-reference'),
            controller: _refCtrl,
            decoration: const InputDecoration(
              labelText: 'Mã tham chiếu (chuyển khoản)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          PhotoPickerStrip(
            photos: _proof,
            max: 1,
            onAdd: _addProof,
            onRemove: (i) => setState(() => _proof.removeAt(i)),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _saving ? null : _submit,
            child: Text(_saving ? 'Đang lưu...' : 'Xác nhận thu tiền'),
          ),
        ],
      ),
    );
  }
}
