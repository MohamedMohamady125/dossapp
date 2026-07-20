import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/athlete.dart';
import '../../services/api_service.dart';
import '../../utils/theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/shimmer_loading.dart';
import '../../widgets/empty_state.dart';

class AthletesScreen extends StatefulWidget {
  final int branchId;
  const AthletesScreen({super.key, required this.branchId});

  @override
  State<AthletesScreen> createState() => _AthletesScreenState();
}

class _AthletesScreenState extends State<AthletesScreen> {
  List<AthleteDetail>? _athletes;
  bool _loading = true;
  String? _error;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      _athletes = await ApiService.getBranchAthletes(widget.branchId);
    } catch (e) {
      _error = e.toString();
    }
    setState(() => _loading = false);
  }

  List<AthleteDetail> get _filtered {
    if (_athletes == null) return [];
    if (_search.isEmpty) return _athletes!;
    final q = _search.toLowerCase();
    return _athletes!.where((a) =>
      a.name.toLowerCase().contains(q) ||
      a.athleteNumber.toString().contains(q) ||
      (a.level?.toLowerCase().contains(q) ?? false)
    ).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SkeletonList(count: 6, hasAvatar: true);
    if (_error != null) {
      return ErrorState(message: _error!, onRetry: _load);
    }

    final list = _filtered;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            decoration: const InputDecoration(
              hintText: 'Search athletes...',
              prefixIcon: Icon(Icons.search),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _search = v),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              Text(
                '${formatNumber(list.length)} athletes',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
              const Spacer(),
              if (_athletes != null)
                Text(
                  '${_athletes!.where((a) => a.hasAccount).length} provisioned',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: list.isEmpty
                ? ListView(
                    children: [
                      SizedBox(
                        height: MediaQuery.of(context).size.height * 0.5,
                        child: EmptyState(
                          icon: Icons.search_off_rounded,
                          title: 'No athletes found',
                          subtitle: _search.isNotEmpty
                              ? 'No results for "$_search"'
                              : 'This branch has no athletes yet',
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    itemCount: list.length,
                    // No AnimatedListItem here — causes jank on fast scroll with 1500+ athletes
                    itemBuilder: (ctx, i) => _buildAthleteRow(list[i]),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildAthleteRow(AthleteDetail a) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: a.hasAccount ? AppColors.primary : AppColors.surfaceVariant,
        child: Text(
          'M${a.athleteNumber}',
          style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w600,
            color: a.hasAccount ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
      title: Text(a.name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text([
        if (a.level != null) a.level!,
        if (a.type != null) a.type!,
        if (a.bill != null) 'Bill: ${formatMoney(a.bill)}',
        if (a.pay != null) 'Paid: ${formatMoney(a.pay)}',
      ].join(' \u2022 '), style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (a.receiptNo != null)
            const Icon(Icons.check_circle, color: AppColors.success, size: 20),
          if (a.hasAccount)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Icon(Icons.person, color: AppColors.primary, size: 20),
            ),
          const Icon(Icons.chevron_right, color: AppColors.textMuted),
        ],
      ),
      onTap: () => _showAthleteDetail(a),
    );
  }

  void _showAthleteDetail(AthleteDetail a) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (ctx, scroll) => Container(
          decoration: const BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: _AthleteDetailSheet(athlete: a, onProvision: _load),
        ),
      ),
    );
  }
}

class _AthleteDetailSheet extends StatefulWidget {
  final AthleteDetail athlete;
  final VoidCallback onProvision;

  const _AthleteDetailSheet({required this.athlete, required this.onProvision});

  @override
  State<_AthleteDetailSheet> createState() => _AthleteDetailSheetState();
}

class _AthleteDetailSheetState extends State<_AthleteDetailSheet> {
  bool _markingPaid = false;
  bool _markedPaid = false;
  String? _receiptNumber;

  Future<void> _markAsPaid() async {
    setState(() => _markingPaid = true);
    try {
      final result = await ApiService.markAsPaid(widget.athlete.branchId, widget.athlete.athleteNumber);
      if (mounted) {
        setState(() {
          _markedPaid = true;
          _receiptNumber = result['receipt_number'];
        });
        widget.onProvision();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
    if (mounted) setState(() => _markingPaid = false);
  }

  @override
  Widget build(BuildContext context) {
    final athlete = widget.athlete;
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        // ── Drag handle ──
        Center(
          child: Container(
            margin: const EdgeInsets.only(top: 12, bottom: 4),
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),

        // ── Gradient Header ──
        Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.2),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 52, height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Text(
                    'M${athlete.athleteNumber}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      athlete.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      athlete.branch,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              if (athlete.hasAccount)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.verified_user_rounded, color: Colors.white, size: 14),
                      SizedBox(width: 4),
                      Text('Active', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // ── Personal Section ──
        _sectionHeader('Personal'),
        _infoRow(Icons.school_rounded, 'Level', athlete.level),
        _infoRow(Icons.category_rounded, 'Type', athlete.type),
        _infoRow(Icons.cake_rounded, 'Age', athlete.age?.toStringAsFixed(1)),
        _infoRow(Icons.calendar_month_rounded, 'DOB', athlete.dateOfBirth),
        _infoRow(Icons.wc_rounded, 'Gender', athlete.gender == 'M' ? 'Male' : athlete.gender == 'F' ? 'Female' : athlete.gender),

        const SizedBox(height: 8),

        // ── Enrollment Section ──
        _sectionHeader('Enrollment'),
        _infoRow(Icons.date_range_rounded, 'Days', athlete.days),
        _infoRow(Icons.event_repeat_rounded, 'Sessions', athlete.sessions),
        _infoRow(Icons.hub_rounded, 'Segment', athlete.segment),
        _infoRow(Icons.receipt_rounded, 'Bill', athlete.bill != null ? formatMoney(athlete.bill) : null),
        _infoRow(Icons.payments_rounded, 'Paid', athlete.pay != null ? formatMoney(athlete.pay) : null),
        _infoRow(Icons.receipt_long_rounded, 'Receipt No.', athlete.receiptNo),
        _infoRow(Icons.comment_rounded, 'Comment', athlete.comment),

        const SizedBox(height: 8),

        // ── Contact Section ──
        _sectionHeader('Contact'),
        _infoRow(Icons.phone_rounded, 'Phone 1', athlete.phone1),
        _infoRow(Icons.phone_android_rounded, 'Phone 2', athlete.phone2),

        // ── Schedule ──
        if (athlete.schedule.isNotEmpty) ...[
          const SizedBox(height: 8),
          _sectionHeader('Schedule'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  for (int i = 0; i < athlete.schedule.length; i++) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: AppColors.secondaryLight,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.pool_rounded, size: 16, color: AppColors.secondary),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  athlete.schedule[i].dayPair ?? 'Unscheduled',
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                ),
                                if (athlete.schedule[i].timeBlock != null)
                                  Text(
                                    athlete.schedule[i].timeBlock!,
                                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                  ),
                              ],
                            ),
                          ),
                          if (athlete.schedule[i].coach != null)
                            Text(
                              athlete.schedule[i].coach!,
                              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                            ),
                        ],
                      ),
                    ),
                    if (i < athlete.schedule.length - 1)
                      const Divider(height: 1, indent: 46),
                  ],
                ],
              ),
            ),
          ),
        ],

        // ── Mark as Paid ──
        if (athlete.bill != null || athlete.pay != null) ...[
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _markedPaid
                ? Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.successLight,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.success.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 24),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Marked as Paid', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.success, fontSize: 16)),
                            if (_receiptNumber != null)
                              Text('Receipt: $_receiptNumber', style: const TextStyle(color: AppColors.success, fontSize: 13)),
                          ],
                        )),
                      ],
                    ),
                  )
                : FilledButton.icon(
                    onPressed: _markingPaid ? null : _markAsPaid,
                    icon: _markingPaid
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.paid_rounded),
                    label: Text(_markingPaid ? 'Marking...' : 'Mark as Paid (${formatMoney(athlete.bill ?? athlete.pay)})'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.success,
                      minimumSize: const Size(double.infinity, 52),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
          ),
        ],

        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _ProvisionButton(
            branchId: athlete.branchId,
            athleteNumber: athlete.athleteNumber,
            onDone: widget.onProvision,
            alreadyProvisioned: athlete.hasAccount,
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.textMuted,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String? value) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: AppColors.textSecondary),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: AppColors.textMuted, fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProvisionButton extends StatefulWidget {
  final int branchId;
  final int athleteNumber;
  final VoidCallback onDone;
  final bool alreadyProvisioned;

  const _ProvisionButton({
    required this.branchId,
    required this.athleteNumber,
    required this.onDone,
    this.alreadyProvisioned = false,
  });

  @override
  State<_ProvisionButton> createState() => _ProvisionButtonState();
}

class _ProvisionButtonState extends State<_ProvisionButton> {
  bool _loading = false;
  String? _code;
  String? _pass;
  String? _sentTo;

  bool _wasProvisioned = false;

  Future<void> _provision(String method) async {
    setState(() => _loading = true);
    try {
      final Map<String, dynamic> result;
      if (widget.alreadyProvisioned || _wasProvisioned) {
        // Already has an account — reset password
        result = await ApiService.reprovisionAccount(widget.branchId, widget.athleteNumber, method);
      } else {
        result = await ApiService.provisionAccount(widget.branchId, widget.athleteNumber, method);
        _wasProvisioned = true;
      }
      if (mounted) {
        setState(() {
          _code = result['login_code'] ?? '';
          _pass = result['temp_password'] ?? '';
          _sentTo = result['sent_to'];
        });
        widget.onDone();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: SizedBox(
            width: 28, height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.primary),
          ),
        ),
      );
    }

    final hasCredentials = _code != null && _pass != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Show credentials if available
        if (hasCredentials) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.successLight,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: AppColors.success),
                const SizedBox(width: 8),
                Text(
                  widget.alreadyProvisioned ? 'Password Reset' : 'Account Created',
                  style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _CopyableField(label: 'Login Code', value: _code!),
          const SizedBox(height: 12),
          _CopyableField(label: 'Temp Password', value: _pass!),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.copy_all, size: 18),
            label: const Text('Copy Both'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: 'Login Code: $_code\nPassword: $_pass'));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Credentials copied to clipboard')),
              );
            },
          ),
          if (_sentTo != null) ...[
            const SizedBox(height: 8),
            Text('Sent to: $_sentTo', style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
          ],
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),
        ],

        // Always show the action buttons
        FilledButton.icon(
          icon: Icon(widget.alreadyProvisioned && !hasCredentials ? Icons.refresh_rounded : Icons.person_add_rounded),
          label: Text(widget.alreadyProvisioned && !hasCredentials
              ? 'Reset Password & Show Credentials'
              : hasCredentials
                  ? 'Reset Password Again'
                  : 'Provision Account (Show Credentials)'),
          onPressed: () => _provision('in_person'),
          style: FilledButton.styleFrom(
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.send_rounded),
          label: Text(widget.alreadyProvisioned && !hasCredentials
              ? 'Reset Password & Send via SMS/WhatsApp'
              : hasCredentials
                  ? 'Reset & Send Again'
                  : 'Provision & Send via SMS/WhatsApp'),
          onPressed: () => _provision('both'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ],
    );
  }
}

class _CopyableField extends StatelessWidget {
  final String label;
  final String value;

  const _CopyableField({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: SelectableText(
                  value,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: IconButton(
                  icon: const Icon(Icons.copy_rounded, size: 20, color: AppColors.primary),
                  tooltip: 'Copy',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: value));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('$label copied'), duration: const Duration(seconds: 1)),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
