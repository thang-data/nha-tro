import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repository.dart';
import 'common.dart';

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key, this.repository});

  final RentalRepository? repository;

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  late final Future<List<ActivityEntry>> _future =
      (widget.repository ?? appRepository).listActivity();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ActivityEntry>>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text('Không tải được dữ liệu: ${snap.error}'));
        }
        final entries = snap.data;
        if (entries == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return PageScaffold(
          title: 'Nhật ký hoạt động',
          children: [
            for (final e in entries)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.history),
                  title: Text(e.action),
                  subtitle: Text('${e.actor} · ${formatDateTime(e.time)}'),
                ),
              ),
          ],
        );
      },
    );
  }
}
