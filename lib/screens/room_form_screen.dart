import 'package:flutter/material.dart';

import '../core/validators.dart';
import '../data/models.dart';
import '../data/repository.dart';

class RoomFormScreen extends StatefulWidget {
  const RoomFormScreen({super.key, this.siteId, this.room, this.repository});

  final String? siteId;

  /// Phòng cần sửa. Null nghĩa là thêm phòng mới.
  final Room? room;
  final RentalRepository? repository;

  @override
  State<RoomFormScreen> createState() => _RoomFormScreenState();
}

class _RoomFormScreenState extends State<RoomFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _codeCtrl = TextEditingController(text: widget.room?.code);
  late final _floorCtrl = TextEditingController(
    text: '${widget.room?.floor ?? 1}',
  );
  late final _rentCtrl = TextEditingController(
    text: widget.room == null ? null : '${widget.room!.rent}',
  );
  late final _dueDaysCtrl = TextEditingController(
    text: '${widget.room?.paymentDueDays ?? defaultPaymentDueDays}',
  );
  List<Site> _sites = const [];
  String? _siteId;
  String? _codeError;
  bool _saving = false;

  RentalRepository get _repo => widget.repository ?? appRepository;

  @override
  void initState() {
    super.initState();
    _repo.listSites().then((s) {
      if (!mounted) return;
      setState(() {
        _sites = s;
        _siteId =
            widget.room?.siteId ??
            widget.siteId ??
            (s.isEmpty ? null : s.first.id);
      });
    });
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _floorCtrl.dispose();
    _rentCtrl.dispose();
    _dueDaysCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _siteId == null) return;
    setState(() => _saving = true);
    try {
      final existing = widget.room;
      final room = existing == null
          ? await _repo.createRoom(
              siteId: _siteId!,
              code: _codeCtrl.text,
              floor: int.parse(_floorCtrl.text),
              rent: int.parse(_rentCtrl.text),
              paymentDueDays: int.parse(_dueDaysCtrl.text.trim()),
            )
          : await _repo.updateRoom(
              Room(
                id: existing.id,
                siteId: _siteId!,
                code: _codeCtrl.text,
                floor: int.parse(_floorCtrl.text),
                status: existing.status,
                rent: int.parse(_rentCtrl.text),
                tenantName: existing.tenantName,
                paymentDueDays: int.parse(_dueDaysCtrl.text.trim()),
              ),
            );
      if (!mounted) return;
      Navigator.of(context).pop(room);
    } on ArgumentError catch (e) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message.toString())));
    } on DuplicateRoomCodeException {
      setState(() {
        _codeError = 'Mã phòng đã tồn tại trong cơ sở này';
        _saving = false;
      });
      _formKey.currentState!.validate();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.room == null ? 'Thêm phòng' : 'Sửa phòng'),
      ),
      body: _sites.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _siteId,
                    decoration: const InputDecoration(
                      labelText: 'Cơ sở',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final s in _sites)
                        DropdownMenuItem(value: s.id, child: Text(s.name)),
                    ],
                    onChanged: (v) => setState(() => _siteId = v),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const ValueKey('room-code'),
                    controller: _codeCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Mã phòng',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => _codeError = null,
                    validator: (v) {
                      if (_codeError != null) return _codeError;
                      return (v == null || v.trim().isEmpty)
                          ? 'Vui lòng nhập mã phòng'
                          : null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _floorCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Tầng',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      final n = int.tryParse(v ?? '');
                      return (n == null || n < 0)
                          ? 'Tầng phải là số ≥ 0'
                          : null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const ValueKey('room-rent'),
                    controller: _rentCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Giá thuê (đ/tháng)',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      final n = int.tryParse(v ?? '');
                      return (n == null || n <= 0)
                          ? 'Giá thuê phải lớn hơn 0'
                          : null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const ValueKey('room-due-days'),
                    controller: _dueDaysCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Hạn thanh toán (ngày)',
                      helperText: 'Tính từ ngày 1 của kỳ, từ 1 đến 60',
                      border: OutlineInputBorder(),
                    ),
                    validator: validatePaymentDueDaysInput,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: const Text('Lưu phòng'),
                  ),
                ],
              ),
            ),
    );
  }
}
