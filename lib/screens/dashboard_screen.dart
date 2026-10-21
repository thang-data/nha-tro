import 'package:flutter/material.dart';

import '../auth/access.dart';
import '../core/money.dart';
import '../data/billing.dart';
import '../data/models.dart';
import '../data/repository.dart';
import 'common.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, this.repository});

  final RentalRepository? repository;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardData {
  const _DashboardData({
    required this.siteCount,
    required this.rooms,
    required this.overdue,
    required this.collected,
    required this.receivable,
    required this.revenue,
    required this.expenses,
    required this.siteNames,
  });

  final int siteCount;
  final List<Room> rooms;
  final List<Invoice> overdue;
  final int collected;
  final int receivable;
  final RevenueSummary? revenue;

  /// Chi phí trong kỳ. Chỉ có khi là super admin.
  final int? expenses;
  final Map<String, String> siteNames;
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<_DashboardData> _future;

  RentalRepository get _repo => widget.repository ?? appRepository;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_DashboardData> _load() async {
    final sites = await _repo.listSites();
    final rooms = await _repo.listRooms();
    final invoices = await _repo.listInvoices();
    final now = DateTime.now();
    final revenue = isSuperAdminUser
        ? await _repo.revenueForPeriod(periodOf(now))
        : null;
    final expenseList = isSuperAdminUser
        ? await _repo.listExpenses(period: periodOf(now))
        : null;
    return _DashboardData(
      revenue: revenue,
      expenses: expenseList == null
          ? null
          : expensesOf(expenseList, periodOf(now)),
      siteNames: {for (final s in sites) s.id: s.name},
      siteCount: sites.length,
      rooms: rooms,
      overdue: [
        for (final i in invoices)
          if (i.statusAt(now) == InvoiceStatus.overdue) i,
      ],
      collected: invoices.fold<int>(0, (s, i) => s + i.paid),
      receivable: invoices.fold<int>(0, (s, i) => s + i.remaining),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_DashboardData>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text('Không tải được dữ liệu: ${snap.error}'));
        }
        final data = snap.data;
        if (data == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final vacant = data.rooms
            .where((r) => r.status == RoomStatus.vacant)
            .length;
        return PageScaffold(
          title: 'Tổng quan',
          children: [
            if (data.revenue != null)
              _RevenueCard(
                period: periodOf(DateTime.now()),
                revenue: data.revenue!,
                expenses: data.expenses ?? 0,
                siteNames: data.siteNames,
              ),
            GridView.count(
              crossAxisCount: MediaQuery.sizeOf(context).width >= 800 ? 4 : 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.7,
              children: [
                _Stat('Cơ sở', '${data.siteCount}', Icons.apartment),
                _Stat(
                  'Phòng trống',
                  '$vacant / ${data.rooms.length}',
                  Icons.meeting_room_outlined,
                ),
                _Stat(
                  'Đã thu',
                  formatVnd(data.collected),
                  Icons.payments_outlined,
                ),
                _Stat(
                  'Công nợ',
                  formatVnd(data.receivable),
                  Icons.warning_amber_outlined,
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'Hóa đơn quá hạn (${data.overdue.length})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (data.overdue.isEmpty)
              const Card(
                child: ListTile(title: Text('Không có hóa đơn quá hạn')),
              )
            else
              for (final inv in data.overdue)
                Card(
                  child: ListTile(
                    title: Text('${inv.roomCode} · ${inv.tenant}'),
                    subtitle: Text(
                      '${inv.period} · hạn ${formatDate(inv.dueDate)}',
                    ),
                    trailing: Text(
                      formatVnd(inv.remaining),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
            const SizedBox(height: 20),
            Text(
              'Ví dụ tính tiền (phòng A101, tháng 10)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            _BillPreview(),
          ],
        );
      },
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, this.icon);
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, color: scheme.primary),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: Theme.of(context).textTheme.titleLarge),
            ),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// Hiển thị breakdown từ hàm tính tiền thật, không hard-code tổng.
class _BillPreview extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final b = calculateInvoice(
      rent: 3000000,
      kwhUsed: 120,
      electricityRate: 3500,
      m3Used: 8,
      waterRate: 20000,
      services: 100000,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _row('Tiền phòng', b.rent),
            _row('Điện: 120 kWh × 3.500đ', b.electricity),
            _row('Nước: 8 m³ × 20.000đ', b.water),
            _row('Internet và dịch vụ', b.services),
            const Divider(),
            _row('Tổng hóa đơn', b.total, bold: true),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, int amount, {bool bold = false}) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(formatVnd(amount), style: style),
        ],
      ),
    );
  }
}

class _RevenueCard extends StatelessWidget {
  const _RevenueCard({
    required this.period,
    required this.revenue,
    required this.expenses,
    required this.siteNames,
  });

  final String period;
  final RevenueSummary revenue;
  final int expenses;
  final Map<String, String> siteNames;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Doanh thu $period', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              formatVnd(revenue.total),
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            for (final entry in revenue.bySite.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(child: Text(siteNames[entry.key] ?? entry.key)),
                    Text(formatVnd(entry.value)),
                  ],
                ),
              ),
            if (revenue.bySite.isEmpty)
              const Text('Chưa có khoản thu trong kỳ này'),
            const Divider(height: 24),
            Row(
              children: [
                const Expanded(child: Text('Chi phí')),
                Text(formatVnd(expenses)),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Expanded(child: Text('Lợi nhuận')),
                Text(
                  formatVnd(revenue.total - expenses),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
