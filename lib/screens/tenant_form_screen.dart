import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repository.dart';
import 'common.dart';

/// Thêm người thuê và ký hợp đồng cho một phòng trống/đã đặt cọc.
class TenantFormScreen extends StatefulWidget {
  const TenantFormScreen({super.key, required this.room, this.repository});

  final Room room;
  final RentalRepository? repository;

  @override
  State<TenantFormScreen> createState() => _TenantFormScreenState();
}

class _TenantFormScreenState extends State<TenantFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _citizenCtrl = TextEditingController();
  late final TextEditingController _rentCtrl = TextEditingController(
    text: '${widget.room.rent}',
  );
  final _depositCtrl = TextEditingController(text: '0');
  late DateTime _startDate = DateTime.now();
  bool _saving = false;

  RentalRepository get _repo => widget.repository ?? appRepository;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _citizenCtrl.dispose();
    _rentCtrl.dispose();
    _depositCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final tenant = await _repo.createTenant(
        fullName: _nameCtrl.text,
        phone: _phoneCtrl.text,
        citizenId: _citizenCtrl.text,
      );
      await _repo.createContract(
        roomId: widget.room.id,
        tenantId: tenant.id,
        startDate: _startDate,
        rent: int.parse(_rentCtrl.text),
        deposit: int.parse(_depositCtrl.text),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on RoomNotAvailableException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Người thuê phòng ${widget.room.code}')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              key: const ValueKey('tenant-name'),
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Họ và tên',
                border: OutlineInputBorder(),
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Vui lòng nhập họ tên'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('tenant-phone'),
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Số điện thoại',
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                final clean = (v ?? '').replaceAll(' ', '');
                return RegExp(r'^(0|\+84)(3|5|7|8|9)\d{8}$').hasMatch(clean)
                    ? null
                    : 'Số điện thoại Việt Nam không hợp lệ';
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('tenant-citizen'),
              controller: _citizenCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'CCCD (12 số)',
                border: OutlineInputBorder(),
              ),
              validator: (v) => RegExp(r'^\d{12}$').hasMatch(v ?? '')
                  ? null
                  : 'CCCD phải gồm đúng 12 chữ số',
            ),
            const SizedBox(height: 24),
            Text('Hợp đồng', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            TextFormField(
              controller: _rentCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Giá thuê (đ/tháng)',
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                final n = int.tryParse(v ?? '');
                return (n == null || n <= 0) ? 'Giá thuê phải lớn hơn 0' : null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('contract-deposit'),
              controller: _depositCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Tiền cọc (đ)',
                helperText: 'Sẽ được trừ khi thanh lý hợp đồng',
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                final n = int.tryParse(v ?? '');
                return (n == null || n < 0) ? 'Tiền cọc không được âm' : null;
              },
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.event),
              label: Text('Ngày bắt đầu: ${formatDate(_startDate)}'),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: const Text('Lưu và ký hợp đồng'),
            ),
          ],
        ),
      ),
    );
  }
}
