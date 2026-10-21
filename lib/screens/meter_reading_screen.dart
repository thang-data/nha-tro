import 'package:flutter/material.dart';

import '../data/billing.dart';
import '../data/models.dart';
import '../data/repository.dart';

/// Nhập chỉ số điện (kWh) và nước (m³) liên tiếp cho các phòng đang thuê.
/// Chỉ số đầu được điền sẵn từ kỳ đã chốt gần nhất.
class MeterReadingScreen extends StatefulWidget {
  const MeterReadingScreen({super.key, this.repository});

  final RentalRepository? repository;

  @override
  State<MeterReadingScreen> createState() => _MeterReadingScreenState();
}

class _RoomRow {
  _RoomRow(this.room, {int? electricStart, int? waterStart})
    : electricStart = TextEditingController(
        text: electricStart?.toString() ?? '',
      ),
      electricEnd = TextEditingController(),
      waterStart = TextEditingController(text: waterStart?.toString() ?? ''),
      waterEnd = TextEditingController();

  final Room room;
  final TextEditingController electricStart;
  final TextEditingController electricEnd;
  final TextEditingController waterStart;
  final TextEditingController waterEnd;

  List<TextEditingController> get all => [
    electricStart,
    electricEnd,
    waterStart,
    waterEnd,
  ];

  void dispose() {
    for (final c in all) {
      c.dispose();
    }
  }
}

String? rangeError(TextEditingController start, TextEditingController end) {
  final s = int.tryParse(start.text);
  final e = int.tryParse(end.text);
  if (s == null || e == null) return null;
  return e < s ? 'Cuối phải ≥ đầu' : null;
}

class _MeterReadingScreenState extends State<MeterReadingScreen> {
  final _periodCtrl = TextEditingController(text: _currentPeriod());
  late Future<List<_RoomRow>> _future;
  List<_RoomRow> _rows = const [];
  bool _saving = false;

  RentalRepository get _repo => widget.repository ?? appRepository;

  static String _currentPeriod() => periodOf(DateTime.now());

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _periodCtrl.dispose();
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  Future<List<_RoomRow>> _load() async {
    final occupied = await _repo.listRooms(status: RoomStatus.occupied);
    final readings = await _repo.listMeterReadings();
    int? lastEnd(String roomId, MeterKind kind) {
      int? value;
      for (final m in readings) {
        if (m.roomId == roomId &&
            m.kind == kind &&
            m.status == ReadingStatus.confirmed) {
          value = m.endValue;
        }
      }
      return value;
    }

    _rows = [
      for (final r in occupied)
        _RoomRow(
          r,
          electricStart: lastEnd(r.id, MeterKind.electric),
          waterStart: lastEnd(r.id, MeterKind.water),
        ),
    ];
    return _rows;
  }

  bool get _hasRangeError => _rows.any(
    (r) =>
        rangeError(r.electricStart, r.electricEnd) != null ||
        rangeError(r.waterStart, r.waterEnd) != null,
  );

  void _toast(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _save({required bool confirm}) async {
    final period = _periodCtrl.text.trim();
    if (period.isEmpty) return _toast('Vui lòng nhập kỳ tính tiền');
    if (_hasRangeError) {
      return _toast('Có chỉ số cuối nhỏ hơn đầu, vui lòng sửa trước khi lưu');
    }

    final filled = _rows
        .where((r) => r.all.any((c) => c.text.trim().isNotEmpty))
        .toList();
    if (filled.isEmpty) return _toast('Chưa có chỉ số nào để lưu');
    if (confirm) {
      for (final r in _rows) {
        if (r.all.any((c) => c.text.trim().isEmpty)) {
          return _toast(
            'Phòng ${r.room.code} chưa nhập đủ chỉ số, không thể chốt kỳ',
          );
        }
      }
    }

    setState(() => _saving = true);
    final submitted = <String>[];
    var failed = false;
    try {
      for (final r in filled) {
        final pairs = [
          (MeterKind.electric, r.electricStart, r.electricEnd),
          (MeterKind.water, r.waterStart, r.waterEnd),
        ];
        for (final (kind, s, e) in pairs) {
          if (s.text.trim().isEmpty || e.text.trim().isEmpty) continue;
          final reading = await _repo.submitMeterReading(
            roomId: r.room.id,
            period: period,
            kind: kind,
            startValue: int.parse(s.text),
            endValue: int.parse(e.text),
          );
          submitted.add(reading.id);
        }
      }
      if (confirm) {
        for (final id in submitted) {
          await _repo.confirmMeterReading(id);
        }
      }
    } on ArgumentError catch (e) {
      failed = true;
      if (mounted) _toast('${e.message}');
    } on StateError catch (e) {
      failed = true;
      if (mounted) _toast(e.message);
    } catch (e) {
      failed = true;
      if (mounted) _toast('Lưu chỉ số thất bại: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    if (!mounted || failed || submitted.isEmpty) return;
    if (!confirm) {
      _toast('Đã lưu nháp ${submitted.length} chỉ số');
      return;
    }
    // Chốt kỳ xong thì tự lập hóa đơn cho các phòng đã đủ chỉ số.
    final invoiced = await _autoInvoice(period);
    if (!mounted) return;
    _toast('Đã chốt kỳ $period cho ${filled.length} phòng$invoiced');
    Navigator.of(context).pop(true);
  }

  /// Lập hóa đơn tự động cho kỳ. Trả về đoạn ghi chú cho thông báo, rỗng nếu không lập được.
  Future<String> _autoInvoice(String period) async {
    try {
      final result = await _repo.proposeInvoices(period: period);
      return result.created == 0 ? '' : ', tự lập ${result.created} hóa đơn';
    } catch (e) {
      return ' (lập hóa đơn lỗi: $e)';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nhập chỉ số điện nước')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving ? null : () => _save(confirm: false),
                      child: const Text('Lưu nháp'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _saving ? null : () => _save(confirm: true),
                      child: const Text('Chốt kỳ'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      body: FutureBuilder<List<_RoomRow>>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(
                controller: _periodCtrl,
                decoration: const InputDecoration(
                  labelText: 'Kỳ tính tiền',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              if (_rows.isEmpty)
                const Card(
                  child: ListTile(title: Text('Không có phòng đang thuê')),
                )
              else
                for (final r in _rows)
                  _RoomRowCard(row: r, onChanged: () => setState(() {})),
            ],
          );
        },
      ),
    );
  }
}

class _RoomRowCard extends StatelessWidget {
  const _RoomRowCard({required this.row, required this.onChanged});

  final _RoomRow row;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final code = row.room.code;
    final eErr = rangeError(row.electricStart, row.electricEnd);
    final wErr = rangeError(row.waterStart, row.waterEnd);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Phòng $code', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            _meterRow(
              label: 'Điện (kWh)',
              startKey: ValueKey('elec-start-$code'),
              endKey: ValueKey('elec-end-$code'),
              start: row.electricStart,
              end: row.electricEnd,
              error: eErr,
            ),
            const SizedBox(height: 8),
            _meterRow(
              label: 'Nước (m³)',
              startKey: ValueKey('water-start-$code'),
              endKey: ValueKey('water-end-$code'),
              start: row.waterStart,
              end: row.waterEnd,
              error: wErr,
            ),
          ],
        ),
      ),
    );
  }

  Widget _meterRow({
    required String label,
    required Key startKey,
    required Key endKey,
    required TextEditingController start,
    required TextEditingController end,
    required String? error,
  }) {
    final s = int.tryParse(start.text);
    final e = int.tryParse(end.text);
    final consumption = (s != null && e != null && e >= s)
        ? 'tiêu thụ ${e - s}'
        : '';
    return Row(
      children: [
        Expanded(flex: 3, child: Text(label)),
        Expanded(
          flex: 4,
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  key: startKey,
                  controller: start,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Đầu',
                    isDense: true,
                  ),
                  onChanged: (_) => onChanged(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  key: endKey,
                  controller: end,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Cuối',
                    isDense: true,
                    errorText: error,
                  ),
                  onChanged: (_) => onChanged(),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 64,
          child: Text(consumption, style: const TextStyle(fontSize: 12)),
        ),
      ],
    );
  }
}
