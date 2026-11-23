import 'package:flutter/material.dart';
import '../../models/report.dart';
import '../../services/api_service.dart';
import '../../utils/translations.dart';
import '../../widgets/shimmer_loading.dart';
import '../../widgets/animated_list_item.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/report_widgets.dart';

class CustomerReportsScreen extends StatefulWidget {
  final List<MonthlyReport>? initialReports;
  const CustomerReportsScreen({super.key, this.initialReports});

  @override
  State<CustomerReportsScreen> createState() => _CustomerReportsScreenState();
}

class _CustomerReportsScreenState extends State<CustomerReportsScreen> {
  List<MonthlyReport>? _reports;
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initialReports != null) {
      _reports = widget.initialReports;
      _loading = false;
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      _reports = await ApiService.getMyReports();
    } catch (e) {
      _error = e;
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.monthlyReports)),
      body: _buildBody(s),
    );
  }

  Widget _buildBody(S s) {
    if (_loading) return const SkeletonList(count: 3);
    if (_error != null) return ErrorState(message: _error!, onRetry: _load);

    final reports = _reports ?? [];
    if (reports.isEmpty) {
      return EmptyState(
        icon: Icons.assignment_outlined,
        title: s.noReportsYet,
        subtitle: s.noReportsSubtitle,
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: reports.length,
        itemBuilder: (ctx, i) => AnimatedListItem(
          index: i,
          child: ReportCard(report: reports[i]),
        ),
      ),
    );
  }
}
