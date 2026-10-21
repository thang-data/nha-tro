import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Super admin: toàn quyền, cấp/gỡ admin và nhân viên. Phải khớp với firestore.rules.
const superAdminEmail = 'nguyenducthang.it190801@gmail.com';

enum AccessRole { superAdmin, admin, staff }

class AccessProfile {
  const AccessProfile({
    required this.email,
    required this.role,
    this.siteIds = const {},
  });

  final String email;
  final AccessRole role;

  /// Cơ sở nhân viên được xem và sửa. Super admin và admin không dùng trường này.
  final Set<String> siteIds;

  /// Toàn quyền dữ liệu (super admin hoặc admin).
  bool get hasFullAccess => role != AccessRole.staff;

  /// Chỉ super admin được cấp quyền admin.
  bool get canManageAdmins => role == AccessRole.superAdmin;
}

AccessProfile? _current;

/// Quyền của tài khoản đang đăng nhập. Null khi chưa đăng nhập (chỉ xảy ra trong test).
AccessProfile? get currentAccess => _current;

void setCurrentAccess(AccessProfile? access) => _current = access;

/// Toàn quyền dữ liệu. Khi chưa đăng nhập (test) không giới hạn ở phía UI.
bool get isAdminUser => _current?.hasFullAccess ?? true;

/// Chỉ super admin. Khi chưa đăng nhập (test) không giới hạn ở phía UI.
bool get isSuperAdminUser =>
    _current?.role == AccessRole.superAdmin || _current == null;

/// Trả về quyền của tài khoản, hoặc null nếu chưa được cấp quyền.
Future<AccessProfile?> loadAccess(User user) async {
  final email = user.email;
  if (email == null || !user.emailVerified) return null;
  if (email == superAdminEmail) {
    return AccessProfile(email: email, role: AccessRole.superAdmin);
  }
  final doc = await FirebaseFirestore.instance
      .collection('members')
      .doc(email)
      .get();
  if (!doc.exists) return null;
  final data = doc.data() ?? const {};
  final sites = (data['sites'] as List?)?.cast<String>() ?? const [];
  return switch (data['role']) {
    'admin' => AccessProfile(email: email, role: AccessRole.admin),
    'staff' => AccessProfile(
      email: email,
      role: AccessRole.staff,
      siteIds: sites.toSet(),
    ),
    _ => null,
  };
}

class StaffMember {
  const StaffMember({
    required this.email,
    required this.role,
    required this.siteIds,
  });

  final String email;
  final AccessRole role;
  final Set<String> siteIds;
}

Stream<List<StaffMember>> watchMembers() {
  return FirebaseFirestore.instance
      .collection('members')
      .snapshots()
      .map(
        (snap) => [
          for (final d in snap.docs)
            StaffMember(
              email: d.id,
              role: d.data()['role'] == 'admin'
                  ? AccessRole.admin
                  : AccessRole.staff,
              siteIds: ((d.data()['sites'] as List?) ?? const [])
                  .cast<String>()
                  .toSet(),
            ),
        ],
      );
}

/// Ghi quyền thành viên. Admin chỉ ghi được vai trò staff (rules chặn phần còn lại).
Future<void> saveMember(String email, AccessRole role, Set<String> siteIds) {
  return FirebaseFirestore.instance.collection('members').doc(email).set({
    'role': role == AccessRole.admin ? 'admin' : 'staff',
    'sites': role == AccessRole.admin ? <String>[] : siteIds.toList(),
  });
}

Future<void> removeMember(String email) {
  return FirebaseFirestore.instance.collection('members').doc(email).delete();
}
