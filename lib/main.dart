import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'auth/access.dart';
import 'auth/sign_in_gate.dart';
import 'core/theme/app_theme.dart';
import 'data/billing.dart';
import 'data/repository.dart';
import 'firebase_options.dart';
import 'screens/activity_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/expenses_screen.dart';
import 'screens/invoices_screen.dart';
import 'screens/members_screen.dart';
import 'screens/sites_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.web);
  runApp(const RentalManagerApp());
}

class RentalManagerApp extends StatelessWidget {
  const RentalManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Quản lý nhà trọ',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: SignInGate(signedInBuilder: (_) => const AppShell()),
    );
  }
}

class _Destination {
  const _Destination(this.label, this.icon, this.selectedIcon, this.builder);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final WidgetBuilder builder;
}

/// Nhân viên không thấy Nhật ký và Thành viên (rules cũng chặn phía server).
List<_Destination> _destinationsFor({
  required bool fullAccess,
  required bool superAdmin,
}) => [
  _Destination(
    'Tổng quan',
    Icons.dashboard_outlined,
    Icons.dashboard,
    (_) => const DashboardScreen(),
  ),
  _Destination(
    'Cơ sở',
    Icons.apartment_outlined,
    Icons.apartment,
    (_) => const SitesScreen(),
  ),
  _Destination(
    'Hóa đơn',
    Icons.receipt_long_outlined,
    Icons.receipt_long,
    (_) => const InvoicesScreen(),
  ),
  if (fullAccess)
    _Destination(
      'Nhật ký',
      Icons.history_outlined,
      Icons.history,
      (_) => const ActivityScreen(),
    ),
  if (fullAccess)
    _Destination(
      'Thành viên',
      Icons.group_outlined,
      Icons.group,
      (_) => const MembersScreen(),
    ),
  if (superAdmin)
    _Destination(
      'Chi phí',
      Icons.request_quote_outlined,
      Icons.request_quote,
      (_) => const ExpensesScreen(),
    ),
];

/// Điện thoại: thanh điều hướng dưới. Máy tính/tablet rộng: rail bên trái.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    // Mở app là tự lập hóa đơn kỳ hiện tại còn thiếu (chạy lại an toàn, phòng đã có hóa đơn bị bỏ qua).
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoInvoiceCurrent());
  }

  Future<void> _autoInvoiceCurrent() async {
    try {
      await appRepository.syncUnpaidRents();
      final result = await appRepository.proposeInvoices(
        period: periodOf(DateTime.now()),
      );
      if (result.created > 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Đã tự lập ${result.created} hóa đơn kỳ này')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Tự lập hóa đơn lỗi: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 800;
    final destinations = _destinationsFor(
      fullAccess: isAdminUser,
      superAdmin: isSuperAdminUser,
    );
    final index = _index < destinations.length ? _index : 0;
    final page = destinations[index].builder(context);

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: index,
              labelType: NavigationRailLabelType.all,
              onDestinationSelected: (i) => setState(() => _index = i),
              trailing: const Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: IconTheme(
                      data: IconThemeData(color: Colors.white70),
                      child: LogoutButton(),
                    ),
                  ),
                ),
              ),
              destinations: [
                for (final d in destinations)
                  NavigationRailDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon),
                    label: Text(d.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: page),
          ],
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          SafeArea(child: page),
          const Positioned(
            top: 0,
            right: 0,
            child: SafeArea(child: LogoutButton()),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (final d in destinations)
            NavigationDestination(
              icon: Icon(d.icon),
              selectedIcon: Icon(d.selectedIcon),
              label: d.label,
            ),
        ],
      ),
    );
  }
}
