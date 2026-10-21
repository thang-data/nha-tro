import 'package:flutter/material.dart';

import '../core/money.dart';
import '../data/models.dart';
import '../data/repository.dart';

/// Danh mục dịch vụ & phí khác của từng cơ sở. Gắn vào phòng làm ở chi tiết phòng.
class ServicesScreen extends StatefulWidget {
  const ServicesScreen({super.key, this.repository});

  final RentalRepository? repository;

  @override
  State<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesData {
  const _ServicesData(this.sites, this.services);
  final List<Site> sites;
  final List<Service> services;
}

class _ServicesScreenState extends State<ServicesScreen> {
  String? _siteId;
  late Future<_ServicesData> _future;

  RentalRepository get _repo => widget.repository ?? appRepository;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_ServicesData> _load() async {
    final sites = await _repo.listSites();
    if (mounted && _siteId == null && sites.isNotEmpty) {
      // FAB nằm ngoài FutureBuilder, cần setState để bật lại khi đã có cơ sở.
      setState(() => _siteId = sites.first.id);
    }
    final services = _siteId == null
        ? <Service>[]
        : await _repo.listServices(siteId: _siteId);
    return _ServicesData(sites, services);
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  Future<void> _toggle(Service s, bool active) async {
    await _repo.updateService(s.copyWith(active: active));
    _reload();
  }

  Future<void> _edit(Service? existing) async {
    final draft = await showDialog<_ServiceDraft>(
      context: context,
      builder: (_) => _ServiceDialog(existing: existing),
    );
    if (draft == null || !mounted) return;
    try {
      if (existing == null) {
        await _repo.createService(
          siteId: _siteId!,
          name: draft.name,
          unitPrice: draft.unitPrice,
          unit: draft.unit,
        );
      } else {
        await _repo.updateService(
          existing.copyWith(
            name: draft.name,
            unitPrice: draft.unitPrice,
            unit: draft.unit,
          ),
        );
      }
    } on ArgumentError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('${e.message}')));
      return;
    }
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dịch vụ & phí khác')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _siteId == null ? null : () => _edit(null),
        icon: const Icon(Icons.add),
        label: const Text('Thêm dịch vụ'),
      ),
      body: FutureBuilder<_ServicesData>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Không tải được dữ liệu: ${snap.error}'));
          }
          final data = snap.data;
          if (data == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
            children: [
              DropdownButtonFormField<String>(
                initialValue: _siteId,
                decoration: const InputDecoration(
                  labelText: 'Cơ sở',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final s in data.sites)
                    DropdownMenuItem(value: s.id, child: Text(s.name)),
                ],
                onChanged: (v) {
                  _siteId = v;
                  _reload();
                },
              ),
              const SizedBox(height: 12),
              Text(
                'Dịch vụ tạo ở đây dùng chung cho cơ sở. Gắn vào từng phòng ở chi tiết phòng.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              if (data.services.isEmpty)
                const Card(child: ListTile(title: Text('Chưa có dịch vụ nào')))
              else
                for (final s in data.services)
                  Card(
                    child: ListTile(
                      onTap: () => _edit(s),
                      title: Text(s.name),
                      subtitle: Text(
                        '${formatVnd(s.unitPrice)} · ${serviceUnitLabel(s.unit)}'
                        ' · ${s.active ? 'Đang dùng' : 'Đã tắt'}',
                      ),
                      trailing: Switch(
                        value: s.active,
                        onChanged: (v) => _toggle(s, v),
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

String serviceUnitLabel(ServiceUnit unit) => switch (unit) {
  ServiceUnit.monthly => 'theo tháng × số lượng',
  ServiceUnit.fixed => 'cố định mỗi tháng',
};

class _ServiceDraft {
  const _ServiceDraft(this.name, this.unitPrice, this.unit);
  final String name;
  final int unitPrice;
  final ServiceUnit unit;
}

class _ServiceDialog extends StatefulWidget {
  const _ServiceDialog({this.existing});

  final Service? existing;

  @override
  State<_ServiceDialog> createState() => _ServiceDialogState();
}

class _ServiceDialogState extends State<_ServiceDialog> {
  late final _nameCtrl = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  late final _priceCtrl = TextEditingController(
    text: widget.existing == null ? '' : '${widget.existing!.unitPrice}',
  );
  late ServiceUnit _unit = widget.existing?.unit ?? ServiceUnit.monthly;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameCtrl.text.trim();
    final price = int.tryParse(_priceCtrl.text.trim());
    if (name.isEmpty) {
      setState(() => _error = 'Nhập tên dịch vụ');
      return;
    }
    if (price == null || price <= 0) {
      setState(() => _error = 'Đơn giá phải lớn hơn 0');
      return;
    }
    Navigator.of(context).pop(_ServiceDraft(name, price, _unit));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Thêm dịch vụ' : 'Sửa dịch vụ'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const ValueKey('service-name'),
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Tên dịch vụ',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('service-price'),
              controller: _priceCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Đơn giá (đ)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<ServiceUnit>(
              segments: const [
                ButtonSegment(
                  value: ServiceUnit.monthly,
                  label: Text('Theo tháng'),
                ),
                ButtonSegment(value: ServiceUnit.fixed, label: Text('Cố định')),
              ],
              selected: {_unit},
              onSelectionChanged: (s) => setState(() => _unit = s.first),
            ),
            const SizedBox(height: 8),
            Text(
              _unit == ServiceUnit.monthly
                  ? 'Thu theo đơn giá × số lượng gắn trong từng phòng.'
                  : 'Thu một lần mỗi tháng, số lượng luôn là 1.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
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
