import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../utils/theme.dart';
import '../../utils/formatters.dart';

class PaymentsScreen extends StatefulWidget {
  final int branchId;
  const PaymentsScreen({super.key, required this.branchId});

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>>? _payments;
  bool _loading = true;
  String? _error;
  String _statusFilter = '';
  String _search = '';
  late AnimationController _animController;

  String get _currentPeriodRaw => DateTime.now().toString().substring(0, 7);

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _load();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      _payments = await ApiService.getBranchPayments(
        widget.branchId,
        period: _currentPeriodRaw,
        status: _statusFilter.isEmpty ? null : _statusFilter,
      );
      _animController.forward(from: 0);
    } catch (e) {
      _error = e.toString();
    }
    setState(() => _loading = false);
  }

  List<Map<String, dynamic>> get _filtered {
    if (_payments == null) return [];
    if (_search.isEmpty) return _payments!;
    final q = _search.toLowerCase();
    return _payments!.where((p) =>
      (p['athlete_name'] ?? '').toString().toLowerCase().contains(q) ||
      (p['athlete_number'] ?? '').toString().contains(q) ||
      (p['amount_paid'] ?? '').toString().contains(q)
    ).toList();
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;

    // Compute summary
    double totalCollected = 0;
    int paidCount = 0;
    if (_payments != null) {
      for (final p in _payments!) {
        if (p['status'] == 'paid') {
          paidCount++;
          totalCollected += num.tryParse(p['amount_paid']?.toString() ?? '0')?.toDouble() ?? 0;
        }
      }
    }

    return Column(
      children: [
        // ── Summary Header ──
        if (!_loading && _payments != null)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF059669), Color(0xFF047857)],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(formatPeriod(_currentPeriodRaw), style: const TextStyle(color: Colors.white60, fontSize: 12)),
                    const SizedBox(height: 4),
                    Text(formatMoney(totalCollected), style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                  ],
                )),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(20)),
                  child: Text('$paidCount paid', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                ),
              ],
            ),
          ),

        // ── Search + Filter ──
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Search by name or number...',
                    hintStyle: const TextStyle(fontSize: 14),
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  onChanged: (v) => setState(() => _search = v),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
                child: PopupMenuButton<String>(
                  icon: Icon(Icons.filter_list, size: 20, color: _statusFilter.isEmpty ? AppColors.textSecondary : AppColors.primary),
                  tooltip: 'Filter status',
                  position: PopupMenuPosition.under,
                  onSelected: (v) { _statusFilter = v; _load(); },
                  itemBuilder: (ctx) => [
                    _filterItem('', 'All', Icons.list),
                    _filterItem('paid', 'Paid', Icons.check_circle_outline),
                    _filterItem('pending', 'Pending', Icons.pending_outlined),
                  ],
                ),
              ),
            ],
          ),
        ),

        // ── List ──
        if (_loading)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (_error != null)
          Expanded(child: Center(child: Text(_error!, style: const TextStyle(color: AppColors.error))))
        else if (list.isEmpty)
          Expanded(child: Center(child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.search_off, size: 48, color: AppColors.textMuted),
              const SizedBox(height: 12),
              Text(_search.isNotEmpty ? 'No results for "$_search"' : 'No payments for this period',
                style: const TextStyle(color: AppColors.textSecondary)),
            ],
          )))
        else
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                itemCount: list.length,
                itemBuilder: (ctx, i) {
                  final delay = (i * 0.05).clamp(0.0, 0.5);
                  return AnimatedBuilder(
                    animation: _animController,
                    builder: (ctx, child) {
                      final value = Curves.easeOut.transform(
                        ((_animController.value - delay) / (1 - delay)).clamp(0.0, 1.0),
                      );
                      return Transform.translate(
                        offset: Offset(0, 20 * (1 - value)),
                        child: Opacity(opacity: value, child: child),
                      );
                    },
                    child: _paymentCard(list[i]),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }

  PopupMenuItem<String> _filterItem(String value, String label, IconData icon) {
    return PopupMenuItem(
      value: value,
      child: Row(children: [
        Icon(icon, size: 18, color: _statusFilter == value ? AppColors.primary : AppColors.textMuted),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(fontWeight: _statusFilter == value ? FontWeight.w600 : FontWeight.w400)),
      ]),
    );
  }

  Widget _paymentCard(Map<String, dynamic> p) {
    final isPaid = p['status'] == 'paid';
    final name = p['athlete_name'] ?? 'Athlete #${p['athlete_number']}';
    final level = p['level'] ?? '';
    final type = p['athlete_type'] ?? '';
    final subtitle = [level, type].where((s) => s.isNotEmpty).join(' \u2022 ');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              color: isPaid ? AppColors.successLight : AppColors.warningLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '#',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: isPaid ? AppColors.success : AppColors.warning),
            )),
          ),
          const SizedBox(width: 12),
          // Name + details
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
              if (subtitle.isNotEmpty)
                Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ],
          )),
          // Amount + status
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(formatMoney(p['amount_paid']), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(height: 3),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: isPaid ? AppColors.successLight : AppColors.warningLight,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  (p['status'] as String).toUpperCase(),
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                    color: isPaid ? AppColors.success : AppColors.warning),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
