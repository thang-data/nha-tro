import 'package:flutter/material.dart';

import '../auth/access.dart';
import '../data/models.dart';
import '../data/repository.dart';
import 'common.dart';

/// Admin cấp quyền nhân viên và chọn cơ sở họ được xem/sửa.
class MembersScreen extends StatelessWidget {
  const MembersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context, null),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Thêm thành viên'),
      ),
      body: StreamBuilder<List<StaffMember>>(
        stream: watchMembers(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Không tải được: ${snap.error}'));
          }
          final members = snap.data;
          if (members == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return PageScaffold(
            title: 'Thành viên',
            children: [
              if (members.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Chưa có thành viên nhân viên nào.'),
                ),
              for (final m in members)
                Card(
                  child: ListTile(
                    // Admin chỉ sửa được nhân viên; admin khác do super admin quản lý.
                    enabled: _canEdit(m),
                    leading: Icon(
                      m.role == AccessRole.admin
                          ? Icons.admin_panel_settings_outlined
                          : Icons.badge_outlined,
                    ),
                    title: Text(m.email),
                    subtitle: Text(
                      m.role == AccessRole.admin
                          ? 'Admin · toàn quyền dữ liệu'
                          : 'Nhân viên · ${m.siteIds.length} cơ sở',
                    ),
                    onTap: _canEdit(m) ? () => _openEditor(context, m) : null,
                    trailing: _canEdit(m)
                        ? IconButton(
                            tooltip: 'Gỡ quyền',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _confirmRemove(context, m),
                          )
                        : null,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  bool _canEdit(StaffMember m) =>
      (currentAccess?.canManageAdmins ?? true) || m.role == AccessRole.staff;

  Future<void> _openEditor(BuildContext context, StaffMember? member) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _MemberEditor(member: member),
    );
  }

  Future<void> _confirmRemove(BuildContext context, StaffMember member) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Gỡ quyền nhân viên?'),
        content: Text('${member.email} sẽ không còn truy cập được dữ liệu.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Gỡ quyền'),
          ),
        ],
      ),
    );
    if (ok == true) await removeMember(member.email);
  }
}

class _MemberEditor extends StatefulWidget {
  const _MemberEditor({this.member});

  final StaffMember? member;

  @override
  State<_MemberEditor> createState() => _MemberEditorState();
}

class _MemberEditorState extends State<_MemberEditor> {
  late final TextEditingController _email = TextEditingController(
    text: widget.member?.email ?? '',
  );
  late final Set<String> _siteIds = {...?widget.member?.siteIds};
  late AccessRole _role = widget.member?.role ?? AccessRole.staff;
  late final Future<List<Site>> _sites = appRepository.listSites();
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final email = _email.text.trim().toLowerCase();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      setState(() => _error = 'Email không hợp lệ');
      return;
    }
    if (email == superAdminEmail) {
      setState(() => _error = 'Email này là super admin, không cần thêm');
      return;
    }
    if (_role == AccessRole.staff && _siteIds.isEmpty) {
      setState(() => _error = 'Chọn ít nhất một cơ sở cho nhân viên');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await saveMember(email, _role, _siteIds);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = 'Lưu thất bại: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.member == null;
    return AlertDialog(
      title: Text(isNew ? 'Thêm thành viên' : 'Sửa quyền nhân viên'),
      content: SizedBox(
        width: 420,
        child: FutureBuilder<List<Site>>(
          future: _sites,
          builder: (context, snap) {
            final sites = snap.data ?? const <Site>[];
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _email,
                  enabled: isNew,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email Google',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                if (currentAccess?.canManageAdmins ?? false)
                  DropdownButtonFormField<AccessRole>(
                    initialValue: _role,
                    decoration: const InputDecoration(
                      labelText: 'Vai trò',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: AccessRole.staff,
                        child: Text('Nhân viên'),
                      ),
                      DropdownMenuItem(
                        value: AccessRole.admin,
                        child: Text('Admin (toàn quyền dữ liệu)'),
                      ),
                    ],
                    onChanged: (v) => setState(() => _role = v ?? _role),
                  ),
                if (_role == AccessRole.staff) ...[
                  const SizedBox(height: 16),
                  const Text('Cơ sở được xem và sửa'),
                  for (final s in sites)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(s.name),
                      value: _siteIds.contains(s.id),
                      onChanged: (v) => setState(() {
                        if (v == true) {
                          _siteIds.add(s.id);
                        } else {
                          _siteIds.remove(s.id);
                        }
                      }),
                    ),
                  if (snap.connectionState == ConnectionState.done &&
                      sites.isEmpty)
                    const Text('Chưa có cơ sở nào. Hãy tạo cơ sở trước.'),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Lưu'),
        ),
      ],
    );
  }
}
