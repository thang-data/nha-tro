import 'package:flutter/material.dart';

import '../auth/access.dart';
import '../data/models.dart';
import '../data/repository.dart';
import 'common.dart';
import 'room_detail_screen.dart';
import 'room_form_screen.dart';
import 'services_screen.dart';

class SitesScreen extends StatefulWidget {
  const SitesScreen({super.key, this.repository});

  final RentalRepository? repository;

  @override
  State<SitesScreen> createState() => _SitesScreenState();
}

class _SitesData {
  const _SitesData(this.sites, this.rooms);
  final List<Site> sites;
  final List<Room> rooms;
}

class _SitesScreenState extends State<SitesScreen> {
  String? _siteId;
  RoomStatus? _filter;
  late Future<_SitesData> _future;

  RentalRepository get _repo => widget.repository ?? appRepository;

  static const _colors = {
    RoomStatus.vacant: Colors.blueGrey,
    RoomStatus.reserved: Colors.orange,
    RoomStatus.occupied: Colors.green,
    RoomStatus.maintenance: Colors.red,
    RoomStatus.inactive: Colors.grey,
    RoomStatus.expired: Colors.brown,
  };

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_SitesData> _load() async {
    final sites = await _repo.listSites();
    if (mounted && _siteId == null && sites.isNotEmpty) {
      // FAB nằm ngoài FutureBuilder, cần setState để bật lại khi đã có cơ sở.
      setState(() => _siteId = sites.first.id);
    }
    final rooms = await _repo.listRooms(siteId: _siteId);
    return _SitesData(sites, rooms);
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  Future<void> _addRoom() async {
    final created = await Navigator.of(context).push<Room>(
      MaterialPageRoute(
        builder: (_) =>
            RoomFormScreen(siteId: _siteId, repository: widget.repository),
      ),
    );
    if (created != null) _reload();
  }

  Future<void> _addSite() async {
    final created = await showDialog<Site>(
      context: context,
      builder: (_) => _SiteFormDialog(repository: _repo),
    );
    if (created != null) {
      setState(() => _siteId = created.id);
      _reload();
    }
  }

  Future<void> _editSite(Site site) async {
    final saved = await showDialog<Site>(
      context: context,
      builder: (_) => _SiteFormDialog(repository: _repo, site: site),
    );
    if (saved != null) _reload();
  }

  Future<void> _openServices() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ServicesScreen(repository: widget.repository),
      ),
    );
    _reload();
  }

  Future<void> _openRoom(Room room) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            RoomDetailScreen(room: room, repository: widget.repository),
      ),
    );
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _siteId == null ? null : _addRoom,
        icon: const Icon(Icons.add),
        label: const Text('Thêm phòng'),
      ),
      body: FutureBuilder<_SitesData>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Không tải được dữ liệu: ${snap.error}'));
          }
          final data = snap.data;
          if (data == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final list = data.rooms
              .where((r) => _filter == null || r.status == _filter)
              .toList();
          return PageScaffold(
            title: 'Cơ sở & phòng',
            action: Wrap(
              spacing: 8,
              children: [
                if (isAdminUser)
                  TextButton.icon(
                    onPressed: _addSite,
                    icon: const Icon(Icons.add_business_outlined),
                    label: const Text('Thêm cơ sở'),
                  ),
                if (isAdminUser && _siteId != null)
                  TextButton.icon(
                    onPressed: () => _editSite(
                      data.sites.firstWhere((s) => s.id == _siteId),
                    ),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Sửa cơ sở'),
                  ),
                TextButton.icon(
                  onPressed: _openServices,
                  icon: const Icon(Icons.miscellaneous_services_outlined),
                  label: const Text('Dịch vụ'),
                ),
              ],
            ),
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
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Tất cả'),
                    selected: _filter == null,
                    onSelected: (_) => setState(() => _filter = null),
                  ),
                  for (final s in RoomStatus.values.where(
                    (s) => s != RoomStatus.inactive,
                  ))
                    ChoiceChip(
                      label: Text(s.label),
                      selected: _filter == s,
                      onSelected: (_) => setState(() => _filter = s),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (list.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('Không có phòng phù hợp')),
                )
              else
                for (final r in list)
                  _RoomTile(
                    room: r,
                    label: r.status.label,
                    color: _colors[r.status]!,
                    onTap: () => _openRoom(r),
                  ),
            ],
          );
        },
      ),
    );
  }
}

class _RoomTile extends StatelessWidget {
  const _RoomTile({
    required this.room,
    required this.label,
    required this.color,
    required this.onTap,
  });
  final Room room;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          child: Text(room.code, style: const TextStyle(fontSize: 12)),
        ),
        title: Text('Phòng ${room.code} · tầng ${room.floor}'),
        subtitle: Text(room.tenantName ?? 'Chưa có người thuê'),
        trailing: StatusChip(label: label, color: color),
      ),
    );
  }
}

class _SiteFormDialog extends StatefulWidget {
  const _SiteFormDialog({required this.repository, this.site});

  final RentalRepository repository;

  /// Cơ sở cần sửa. Null nghĩa là thêm cơ sở mới.
  final Site? site;

  @override
  State<_SiteFormDialog> createState() => _SiteFormDialogState();
}

class _SiteFormDialogState extends State<_SiteFormDialog> {
  late final _name = TextEditingController(text: widget.site?.name);
  late final _address = TextEditingController(text: widget.site?.address);
  late final _electricRate = TextEditingController(
    text: widget.site == null ? '' : '${widget.site!.electricRate}',
  );
  late final _waterRate = TextEditingController(
    text: widget.site == null ? '' : '${widget.site!.waterRate}',
  );
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _electricRate.dispose();
    _waterRate.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    try {
      final existing = widget.site;
      final electric = int.tryParse(_electricRate.text.trim()) ?? 0;
      final water = int.tryParse(_waterRate.text.trim()) ?? 0;
      final site = existing == null
          ? await widget.repository.createSite(
              name: _name.text,
              address: _address.text,
              electricRate: electric,
              waterRate: water,
            )
          : await widget.repository.updateSite(
              existing.copyWith(
                name: _name.text,
                address: _address.text,
                electricRate: electric,
                waterRate: water,
              ),
            );
      if (mounted) Navigator.of(context).pop(site);
    } on ArgumentError catch (e) {
      setState(() => _error = e.message.toString());
    } catch (e) {
      setState(() => _error = 'Lưu thất bại: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.site == null ? 'Thêm cơ sở' : 'Sửa cơ sở'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Tên cơ sở',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _address,
              decoration: const InputDecoration(
                labelText: 'Địa chỉ',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _electricRate,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Đơn giá điện (đ/kWh)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _waterRate,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Đơn giá nước (đ/m³)',
                border: OutlineInputBorder(),
              ),
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
        FilledButton(onPressed: _save, child: const Text('Lưu')),
      ],
    );
  }
}
