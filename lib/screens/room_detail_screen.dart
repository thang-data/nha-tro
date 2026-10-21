import 'package:flutter/material.dart';

import '../core/money.dart';
import '../core/validators.dart';
import '../data/models.dart';
import '../data/repository.dart';
import 'room_form_screen.dart';
import 'common.dart';
import 'meter_reading_screen.dart';
import 'photo_widgets.dart';
import 'tenant_form_screen.dart';
import 'termination_screen.dart';

class RoomDetailScreen extends StatefulWidget {
  const RoomDetailScreen({super.key, required this.room, this.repository});

  final Room room;
  final RentalRepository? repository;

  @override
  State<RoomDetailScreen> createState() => _RoomDetailScreenState();
}

class _RoomDetailData {
  _RoomDetailData(
    this.room,
    this.contract,
    this.tenant,
    this.readings,
    this.services,
    this.roomServices,
    this.photos,
  );
  final Room room;
  final Contract? contract;
  final Tenant? tenant;
  final List<MeterReading> readings;

  /// Ảnh kiểm tra và thanh lý của phòng (từ các lần thanh lý trước).
  final List<Photo> photos;

  /// Danh mục dịch vụ của cơ sở (cả dịch vụ đang tắt, để đọc tên dịch vụ đã gắn).
  final List<Service> services;
  final List<RoomService> roomServices;

  Service? serviceById(String id) {
    for (final s in services) {
      if (s.id == id) return s;
    }
    return null;
  }
}

String _serviceSubtitle(_RoomDetailData d, RoomService rs) {
  final service = d.serviceById(rs.serviceId);
  if (service == null) return 'Số lượng ${rs.quantity}';
  final price = formatVnd(service.unitPrice);
  return service.unit == ServiceUnit.fixed
      ? '$price/kỳ · cố định'
      : '$price/đơn vị × ${rs.quantity} mỗi kỳ';
}

class _AttachChoice {
  const _AttachChoice(this.serviceId, this.quantity);
  final String serviceId;
  final int quantity;
}

class _AttachServiceDialog extends StatefulWidget {
  const _AttachServiceDialog({required this.candidates});

  final List<Service> candidates;

  @override
  State<_AttachServiceDialog> createState() => _AttachServiceDialogState();
}

class _AttachServiceDialogState extends State<_AttachServiceDialog> {
  final _qtyCtrl = TextEditingController(text: '1');
  String? _serviceId;
  String? _qtyError;

  Service? get _selected {
    for (final s in widget.candidates) {
      if (s.id == _serviceId) return s;
    }
    return null;
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final service = _selected;
    if (service == null) return;
    // Dịch vụ cố định luôn tính số lượng 1.
    if (service.unit == ServiceUnit.fixed) {
      Navigator.of(context).pop(_AttachChoice(service.id, 1));
      return;
    }
    final qty = int.tryParse(_qtyCtrl.text.trim());
    if (qty == null || qty < 1) {
      setState(() => _qtyError = 'Số lượng phải từ 1 trở lên');
      return;
    }
    Navigator.of(context).pop(_AttachChoice(service.id, qty));
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    final fixed = selected?.unit == ServiceUnit.fixed;
    return AlertDialog(
      title: const Text('Gắn dịch vụ vào phòng'),
      content: widget.candidates.isEmpty
          ? const Text(
              'Không còn dịch vụ nào đang bật để gắn. Thêm dịch vụ ở mục Dịch vụ & phí khác.',
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  key: const ValueKey('attach-service'),
                  decoration: const InputDecoration(
                    labelText: 'Dịch vụ',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final s in widget.candidates)
                      DropdownMenuItem(
                        value: s.id,
                        child: Text('${s.name} · ${formatVnd(s.unitPrice)}'),
                      ),
                  ],
                  onChanged: (v) => setState(() => _serviceId = v),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('attach-quantity'),
                  controller: _qtyCtrl,
                  enabled: !fixed,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Số lượng',
                    helperText: fixed ? 'Dịch vụ cố định: luôn là 1' : null,
                    errorText: _qtyError,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => _qtyError = null,
                ),
              ],
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: selected == null ? null : _submit,
          child: const Text('Gắn'),
        ),
      ],
    );
  }
}

class _DueDaysDialog extends StatefulWidget {
  const _DueDaysDialog({required this.initial});

  final int initial;

  @override
  State<_DueDaysDialog> createState() => _DueDaysDialogState();
}

class _DueDaysDialogState extends State<_DueDaysDialog> {
  late final _ctrl = TextEditingController(text: '${widget.initial}');
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final error = validatePaymentDueDaysInput(_ctrl.text);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop(int.parse(_ctrl.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Hạn thanh toán (ngày)'),
      content: TextField(
        key: const ValueKey('room-due-days-edit'),
        controller: _ctrl,
        autofocus: true,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: 'Số ngày từ ngày 1 của kỳ',
          helperText: 'Từ $minPaymentDueDays đến $maxPaymentDueDays ngày',
          errorText: _error,
          border: const OutlineInputBorder(),
        ),
        onChanged: (_) => _error = null,
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Lưu')),
      ],
    );
  }
}

class _ContractEditDialog extends StatefulWidget {
  const _ContractEditDialog({required this.rent, required this.deposit});

  final int rent;
  final int deposit;

  @override
  State<_ContractEditDialog> createState() => _ContractEditDialogState();
}

class _ContractEditDialogState extends State<_ContractEditDialog> {
  late final _rentCtrl = TextEditingController(text: '${widget.rent}');
  late final _depositCtrl = TextEditingController(text: '${widget.deposit}');
  String? _error;

  @override
  void dispose() {
    _rentCtrl.dispose();
    _depositCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final rent = int.tryParse(_rentCtrl.text.trim());
    final deposit = int.tryParse(_depositCtrl.text.trim());
    if (rent == null || rent <= 0) {
      setState(() => _error = 'Giá thuê phải lớn hơn 0');
      return;
    }
    if (deposit == null || deposit < 0) {
      setState(() => _error = 'Tiền cọc không được âm');
      return;
    }
    Navigator.of(context).pop((rent: rent, deposit: deposit));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Sửa hợp đồng'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const ValueKey('contract-rent-edit'),
            controller: _rentCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Giá thuê (đ/tháng)',
              helperText: 'Đồng thời là giá phòng',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('contract-deposit-edit'),
            controller: _depositCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Tiền cọc (đ)',
              errorText: _error,
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Lưu')),
      ],
    );
  }
}

class _RoomDetailScreenState extends State<RoomDetailScreen> {
  late Future<_RoomDetailData> _future;

  RentalRepository get _repo => widget.repository ?? appRepository;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_RoomDetailData> _load() async {
    var room = await _repo.getRoom(widget.room.id);
    var contract = await _repo.activeContractForRoom(room.id);
    if (contract != null && contract.rent != room.rent) {
      // Dữ liệu cũ: giá phòng đã sửa nhưng hợp đồng còn giá cũ. Đưa hợp đồng về giá phòng hiện tại.
      room = await _repo.updateRoom(room);
      contract = await _repo.activeContractForRoom(room.id);
    }
    final tenant = contract == null
        ? null
        : await _repo.getTenant(contract.tenantId);
    final readings = await _repo.listMeterReadings(roomId: room.id);
    final services = await _repo.listServices(siteId: room.siteId);
    final roomServices = await _repo.listRoomServices(room.id);
    final photos = await _repo.listRoomPhotos(room.id);
    return _RoomDetailData(
      room,
      contract,
      tenant,
      readings.reversed.toList(),
      services,
      roomServices,
      photos,
    );
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  /// Sửa thông tin phòng. Sau khi lưu quay về danh sách để tiêu đề và số liệu luôn đúng.
  Future<void> _editRoom() async {
    final saved = await Navigator.of(context).push<Room>(
      MaterialPageRoute(
        builder: (_) =>
            RoomFormScreen(room: widget.room, repository: widget.repository),
      ),
    );
    if (saved != null && mounted) Navigator.of(context).pop();
  }

  Future<void> _editDueDays(Room room) async {
    final days = await showDialog<int>(
      context: context,
      builder: (_) => _DueDaysDialog(initial: room.paymentDueDays),
    );
    if (days == null) return;
    await _repo.updateRoomDueDays(room.id, days);
    _reload();
  }

  Future<void> _attachService(_RoomDetailData d) async {
    final attached = {for (final rs in d.roomServices) rs.serviceId};
    final candidates = [
      for (final s in d.services)
        if (s.active && !attached.contains(s.id)) s,
    ];
    final picked = await showDialog<_AttachChoice>(
      context: context,
      builder: (_) => _AttachServiceDialog(candidates: candidates),
    );
    if (picked == null) return;
    await _repo.attachService(
      roomId: d.room.id,
      serviceId: picked.serviceId,
      quantity: picked.quantity,
    );
    _reload();
  }

  Future<void> _detachService(RoomService rs) async {
    await _repo.detachService(rs.id);
    _reload();
  }

  Future<void> _terminate(Room room) async {
    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            TerminationScreen(room: room, repository: widget.repository),
      ),
    );
    if (done == true) _reload();
  }

  Future<void> _reopen(Room room) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mở lại cho thuê?'),
        content: const Text('Phòng sẽ chuyển sang Trống để ký hợp đồng mới.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Mở lại'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _repo.updateRoom(
      room.copyWith(status: RoomStatus.vacant, clearTenant: true),
    );
    _reload();
  }

  Future<void> _editContract(Contract contract) async {
    final picked = await showDialog<({int rent, int deposit})>(
      context: context,
      builder: (_) =>
          _ContractEditDialog(rent: contract.rent, deposit: contract.deposit),
    );
    if (picked == null) return;
    try {
      await _repo.updateContract(
        contract.copyWith(rent: picked.rent, deposit: picked.deposit),
      );
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Lưu hợp đồng thất bại: $e')));
    }
  }

  Future<void> _addTenant(Room room) async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            TenantFormScreen(room: room, repository: widget.repository),
      ),
    );
    if (ok == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Phòng ${widget.room.code}'),
        actions: [
          IconButton(
            tooltip: 'Sửa thông tin phòng',
            icon: const Icon(Icons.edit_note),
            onPressed: _editRoom,
          ),
        ],
      ),
      body: FutureBuilder<_RoomDetailData>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Lỗi: ${snap.error}'));
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final d = snap.data!;
          final canRent =
              d.room.status == RoomStatus.vacant ||
              d.room.status == RoomStatus.reserved;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tầng ${d.room.floor} · Giá thuê ${formatVnd(d.room.rent)}/tháng',
                      ),
                      const SizedBox(height: 4),
                      Text('Trạng thái: ${d.room.status.label}'),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Hạn thanh toán: ${d.room.paymentDueDays} ngày',
                            ),
                          ),
                          IconButton(
                            tooltip: 'Sửa hạn thanh toán',
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => _editDueDays(d.room),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Người thuê & hợp đồng',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              if (d.contract == null || d.tenant == null)
                const Card(
                  child: ListTile(
                    title: Text('Chưa có hợp đồng đang hiệu lực'),
                  ),
                )
              else
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: Text(d.tenant!.fullName),
                    trailing: IconButton(
                      tooltip: 'Sửa hợp đồng',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => _editContract(d.contract!),
                    ),
                    subtitle: Text(
                      'SĐT ${d.tenant!.phone}\nBắt đầu ${formatDate(d.contract!.startDate)} · ${formatVnd(d.contract!.rent)}/tháng\nTiền cọc ${formatVnd(d.contract!.deposit)}',
                    ),
                    isThreeLine: true,
                  ),
                ),
              const SizedBox(height: 12),
              if (canRent)
                FilledButton.icon(
                  onPressed: () => _addTenant(d.room),
                  icon: const Icon(Icons.person_add_alt),
                  label: const Text('Thêm người thuê & hợp đồng'),
                ),
              if (d.room.status == RoomStatus.occupied && d.contract != null)
                OutlinedButton.icon(
                  onPressed: () => _terminate(d.room),
                  icon: const Icon(Icons.logout),
                  label: const Text('Thanh lý hợp đồng'),
                ),
              if (d.room.status == RoomStatus.expired)
                OutlinedButton.icon(
                  onPressed: () => _reopen(d.room),
                  icon: const Icon(Icons.restore),
                  label: const Text('Mở lại cho thuê'),
                ),
              if (d.photos.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'Ảnh kiểm tra & thanh lý',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                SavedPhotoStrip(
                  data: [
                    for (final p in d.photos)
                      if (p.kind != PhotoKind.paymentProof) p.data,
                  ],
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Dịch vụ đang gắn',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _attachService(d),
                    icon: const Icon(Icons.add),
                    label: const Text('Thêm dịch vụ'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (d.roomServices.isEmpty)
                const Card(child: ListTile(title: Text('Chưa gắn dịch vụ nào')))
              else
                for (final rs in d.roomServices)
                  Card(
                    child: ListTile(
                      title: Text(d.serviceById(rs.serviceId)?.name ?? '?'),
                      subtitle: Text(_serviceSubtitle(d, rs)),
                      trailing: IconButton(
                        tooltip: 'Gỡ khỏi phòng',
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: () => _detachService(rs),
                      ),
                    ),
                  ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Lịch sử chỉ số',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              MeterReadingScreen(repository: widget.repository),
                        ),
                      );
                      _reload();
                    },
                    icon: const Icon(Icons.speed),
                    label: const Text('Nhập chỉ số'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (d.readings.isEmpty)
                const Card(child: ListTile(title: Text('Chưa có chỉ số nào')))
              else
                for (final m in d.readings)
                  Card(
                    child: ListTile(
                      title: Text(
                        '${m.kind == MeterKind.electric ? 'Điện' : 'Nước'} · ${m.period}',
                      ),
                      subtitle: Text(
                        '${m.startValue} → ${m.endValue} (tiêu thụ ${m.consumption})',
                      ),
                      trailing: StatusChip(
                        label: m.status == ReadingStatus.confirmed
                            ? 'Đã chốt'
                            : 'Nháp',
                        color: m.status == ReadingStatus.confirmed
                            ? Colors.green
                            : Colors.orange,
                      ),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}
