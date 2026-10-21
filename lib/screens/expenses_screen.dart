import 'package:flutter/material.dart';

import '../core/money.dart';
import '../data/billing.dart';
import '../data/models.dart';
import '../data/repository.dart';
import 'common.dart';

/// Chi phí trong tháng hiện tại. Chỉ super admin mở được trang này.
class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key, this.repository});

  final RentalRepository? repository;

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesData {
  const _ExpensesData(this.sites, this.expenses);
  final List<Site> sites;
  final List<Expense> expenses;
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  late Future<_ExpensesData> _future;

  RentalRepository get _repo => widget.repository ?? appRepository;

  String get _period => periodOf(DateTime.now());

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_ExpensesData> _load() async {
    final sites = await _repo.listSites();
    final expenses = [...await _repo.listExpenses(period: _period)]
      ..sort((a, b) => b.date.compareTo(a.date));
    return _ExpensesData(sites, expenses);
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _edit(_ExpensesData data, {Expense? expense}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _ExpenseDialog(
        repository: _repo,
        sites: data.sites,
        expense: expense,
      ),
    );
    if (saved == true) _reload();
  }

  Future<void> _delete(Expense expense) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa khoản chi phí?'),
        content: Text('${expense.category} · ${formatVnd(expense.amount)}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _repo.deleteExpense(expense.id);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_ExpensesData>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text('Không tải được dữ liệu: ${snap.error}'));
        }
        final data = snap.data;
        if (data == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final siteNames = {for (final s in data.sites) s.id: s.name};
        final total = expensesOf(data.expenses, _period);
        return Scaffold(
          floatingActionButton: FloatingActionButton.extended(
            onPressed: data.sites.isEmpty ? null : () => _edit(data),
            icon: const Icon(Icons.add),
            label: const Text('Thêm chi phí'),
          ),
          body: PageScaffold(
            title: 'Chi phí $_period',
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Expanded(child: Text('Tổng chi phí trong tháng')),
                      Text(
                        formatVnd(total),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (data.expenses.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: Text('Chưa có khoản chi phí nào trong tháng'),
                  ),
                )
              else
                for (final e in data.expenses)
                  Card(
                    child: ListTile(
                      onTap: () => _edit(data, expense: e),
                      title: Text('${e.category} · ${formatVnd(e.amount)}'),
                      subtitle: Text(
                        [
                          formatDate(e.date),
                          siteNames[e.siteId] ?? e.siteId,
                          if (e.note.isNotEmpty) e.note,
                        ].join(' · '),
                      ),
                      trailing: IconButton(
                        tooltip: 'Xóa',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _delete(e),
                      ),
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }
}

class _ExpenseDialog extends StatefulWidget {
  const _ExpenseDialog({
    required this.repository,
    required this.sites,
    this.expense,
  });

  final RentalRepository repository;
  final List<Site> sites;

  /// Khoản cần sửa. Null nghĩa là thêm mới.
  final Expense? expense;

  @override
  State<_ExpenseDialog> createState() => _ExpenseDialogState();
}

class _ExpenseDialogState extends State<_ExpenseDialog> {
  late String? _siteId = widget.expense?.siteId ?? widget.sites.first.id;
  late String _category = widget.expense?.category ?? expenseCategories.first;
  late DateTime _date = widget.expense?.date ?? DateTime.now();
  late final _amount = TextEditingController(
    text: widget.expense == null ? '' : '${widget.expense!.amount}',
  );
  late final _note = TextEditingController(text: widget.expense?.note);
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    final amount = int.tryParse(_amount.text.replaceAll(RegExp(r'[^0-9]'), ''));
    if (_siteId == null) {
      setState(() => _error = 'Chọn cơ sở');
      return;
    }
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Số tiền phải lớn hơn 0');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.saveExpense(
        Expense(
          id:
              widget.expense?.id ??
              'exp-${DateTime.now().microsecondsSinceEpoch}',
          siteId: _siteId!,
          date: _date,
          category: _category,
          amount: amount,
          note: _note.text.trim(),
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = 'Lưu thất bại: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.expense == null ? 'Thêm chi phí' : 'Sửa chi phí'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _siteId,
                decoration: const InputDecoration(
                  labelText: 'Cơ sở',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final s in widget.sites)
                    DropdownMenuItem(value: s.id, child: Text(s.name)),
                ],
                onChanged: (v) => setState(() => _siteId = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: const InputDecoration(
                  labelText: 'Loại chi phí',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final c in expenseCategories)
                    DropdownMenuItem(value: c, child: Text(c)),
                ],
                onChanged: (v) => setState(() => _category = v ?? _category),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_today_outlined),
                label: Text('Ngày ${formatDate(_date)}'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _amount,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Số tiền (đ)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _note,
                decoration: const InputDecoration(
                  labelText: 'Ghi chú',
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
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
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
