import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/money.dart';
import '../data/billing.dart';
import '../data/models.dart';
import '../data/repository.dart';
import 'photo_widgets.dart';

/// Thanh lý hợp đồng: bắt buộc ảnh kiểm tra và ảnh thanh lý, xem trước quyết toán
/// (nợ cũ trừ tiền cọc), rồi chuyển phòng sang Hết hạn.
class TerminationScreen extends StatefulWidget {
  const TerminationScreen({super.key, required this.room, this.repository});

  final Room room;
  final RentalRepository? repository;

  @override
  State<TerminationScreen> createState() => _TerminationScreenState();
}

class _TerminationData {
  const _TerminationData(this.contract, this.tenant, this.unpaid);

  final Contract contract;
  final Tenant? tenant;
  final List<Invoice> unpaid;
}

class _TerminationScreenState extends State<TerminationScreen> {
  late final Future<_TerminationData> _future = _load();
  final _inspection = <Uint8List>[];
  final _liquidation = <Uint8List>[];
  bool _saving = false;

  RentalRepository get _repo => widget.repository ?? appRepository;

  Future<_TerminationData> _load() async {
    final room = widget.room;
    final contract = await _repo.activeContractForRoom(room.id);
    if (contract == null) {
      throw StateError('Phòng ${room.code} không có hợp đồng đang hiệu lực');
    }
    final tenant = await _repo.getTenant(contract.tenantId);
    final invoices = await _repo.listInvoices();
    final unpaid = [
      for (final inv in invoices)
        if (inv.siteId == room.siteId &&
            inv.roomCode == room.code &&
            inv.remaining > 0)
          inv,
    ];
    return _TerminationData(contract, tenant, unpaid);
  }

  Future<void> _addPhoto(List<Uint8List> target) async {
    final bytes = await pickCompressedPhoto(context);
    if (bytes == null || !mounted) return;
    setState(() => target.add(bytes));
  }

  Future<void> _submit() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Thanh lý hợp đồng phòng ${widget.room.code}?'),
        content: const Text(
          'Hợp đồng sẽ kết thúc, người thuê được gỡ khỏi phòng và phòng chuyển sang Hết hạn. '
          'Thao tác này không hoàn tác được.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Thanh lý'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _saving = true);
    try {
      final result = await _repo.terminateContract(
        roomId: widget.room.id,
        inspectionPhotos: _inspection,
        liquidationPhotos: _liquidation,
      );
      if (!mounted) return;
      final settlement = result.settlement;
      final message = settlement == null
          ? 'Đã thanh lý phòng, không còn khoản thu hoàn'
          : settlement.total < 0
          ? 'Đã thanh lý. Cần hoàn lại khách ${formatVnd(-settlement.total)}'
          : 'Đã thanh lý. Khách còn phải trả ${formatVnd(settlement.total)}';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Thanh lý thất bại: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text('Thanh lý phòng ${widget.room.code}')),
      body: FutureBuilder<_TerminationData>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Lỗi: ${snap.error}'));
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final d = snap.data!;
          final lines = settlementLines(
            unpaid: d.unpaid,
            deposit: d.contract.deposit,
          );
          final total = linesTotal(lines);
          final ready = _inspection.isNotEmpty && _liquidation.isNotEmpty;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(d.tenant?.fullName ?? 'Người thuê'),
                  subtitle: Text(
                    'Tiền cọc ${formatVnd(d.contract.deposit)} · '
                    'Giá thuê ${formatVnd(d.contract.rent)}/tháng',
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('Ảnh kiểm tra phòng', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              const Text('Bắt buộc ít nhất 1 ảnh'),
              const SizedBox(height: 8),
              PhotoPickerStrip(
                photos: _inspection,
                onAdd: () => _addPhoto(_inspection),
                onRemove: (i) => setState(() => _inspection.removeAt(i)),
              ),
              const SizedBox(height: 16),
              Text('Ảnh thanh lý', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              const Text('Bắt buộc ít nhất 1 ảnh'),
              const SizedBox(height: 8),
              PhotoPickerStrip(
                photos: _liquidation,
                onAdd: () => _addPhoto(_liquidation),
                onRemove: (i) => setState(() => _liquidation.removeAt(i)),
              ),
              const SizedBox(height: 16),
              Text('Quyết toán', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              if (lines.isEmpty)
                const Card(
                  child: ListTile(
                    title: Text('Không còn nợ và không có tiền cọc để trừ'),
                  ),
                )
              else
                Card(
                  child: Column(
                    children: [
                      for (final l in lines)
                        ListTile(
                          title: Text(l.label),
                          subtitle: l.description.isEmpty
                              ? null
                              : Text(l.description),
                          trailing: Text(formatVnd(l.amount)),
                        ),
                      ListTile(
                        title: Text(
                          total < 0 ? 'Hoàn lại khách' : 'Khách còn phải trả',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        trailing: Text(
                          formatVnd(total.abs()),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: (!ready || _saving) ? null : _submit,
                icon: const Icon(Icons.logout),
                label: Text(_saving ? 'Đang thanh lý...' : 'Thanh lý hợp đồng'),
              ),
              if (!ready)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Cần chọn ảnh kiểm tra và ảnh thanh lý trước khi thanh lý.',
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
