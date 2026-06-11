import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/athlete.dart';
import '../../services/api_service.dart';
import '../../utils/theme.dart';
import '../../utils/formatters.dart';

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
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_error!, style: const TextStyle(color: Colors.red)),
          FilledButton(onPressed: _load, child: const Text('Retry')),
        ],
      ));
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
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _search = v),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Text('${formatNumber(list.length)} athletes', style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView.builder(
              itemCount: list.length,
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
      title: Text(a.name),
      subtitle: Text([
        if (a.level != null) a.level!,
        if (a.type != null) a.type!,
        if (a.pay != null) formatMoney(a.pay),
      ].join(' \u2022 '), style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (a.receiptNo != null)
            const Icon(Icons.check_circle, color: Color(0xFF2E7D32), size: 20),
          if (a.hasAccount)
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Icon(Icons.person, color: Color(0xFF1A237E), size: 20),
            ),
          const Icon(Icons.chevron_right),
        ],
      ),
      onTap: () => _showAthleteDetail(a),
    );
  }

  void _showAthleteDetail(AthleteDetail a) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (ctx, scroll) => _AthleteDetailSheet(athlete: a, onProvision: _load),
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
      padding: const EdgeInsets.all(20),
      children: [
        Center(
          child: Container(
            width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
          ),
        ),
        const SizedBox(height: 16),
        Text(athlete.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        Text('M${athlete.athleteNumber} | ${athlete.branch}', style: const TextStyle(color: Colors.grey)),
        const Divider(height: 24),

        _row('Level', athlete.level),
        _row('Type', athlete.type),
        _row('Age', athlete.age?.toStringAsFixed(1)),
        _row('DOB', athlete.dateOfBirth),
        _row('Gender', athlete.gender == 'M' ? 'Male' : athlete.gender == 'F' ? 'Female' : athlete.gender),
        _row('Days', athlete.days),
        _row('Sessions', athlete.sessions),
        _row('Segment', athlete.segment),
        _row('Pay', athlete.pay != null ? '${athlete.pay} EGP' : null),
        _row('Phone 1', athlete.phone1),
        _row('Phone 2', athlete.phone2),
        _row('Receipt No.', athlete.receiptNo),
        _row('Comment', athlete.comment),

        if (athlete.schedule.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text('Schedule', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          for (final s in athlete.schedule)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text('${s.dayPair ?? ""} ${s.timeBlock ?? ""} — ${s.coach ?? ""}'),
            ),
        ],

        // ── Mark as Paid ──
        if (athlete.pay != null) ...[
          const SizedBox(height: 24),
          if (_markedPaid)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Color(0xFF2E7D32), size: 28),
                  const SizedBox(width: 12),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Marked as Paid', style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF2E7D32), fontSize: 16)),
                      if (_receiptNumber != null)
                        Text('Receipt: $_receiptNumber', style: const TextStyle(color: Color(0xFF2E7D32), fontSize: 13)),
                    ],
                  )),
                ],
              ),
            )
          else
            FilledButton.icon(
              onPressed: _markingPaid ? null : _markAsPaid,
              icon: _markingPaid
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.paid),
              label: Text(_markingPaid ? 'Marking...' : 'Mark as Paid (${athlete.pay} EGP)'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32),
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
        ],

        const SizedBox(height: 16),
        _ProvisionButton(
          branchId: athlete.branchId,
          athleteNumber: athlete.athleteNumber,
          onDone: widget.onProvision,
          alreadyProvisioned: athlete.hasAccount,
        ),
      ],
    );
  }

  Widget _row(String label, String? value) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 100, child: Text(label, style: const TextStyle(color: Colors.grey))),
          Expanded(child: Text(value)),
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
    if (_loading) return const Center(child: CircularProgressIndicator());

    final hasCredentials = _code != null && _pass != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Show credentials if available
        if (hasCredentials) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: Color(0xFF2E7D32)),
                const SizedBox(width: 8),
                Text(
                  widget.alreadyProvisioned ? 'Password Reset' : 'Account Created',
                  style: const TextStyle(color: Color(0xFF2E7D32), fontWeight: FontWeight.bold),
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
            Text('Sent to: $_sentTo', style: const TextStyle(color: Colors.grey)),
          ],
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),
        ],

        // Always show the action buttons
        FilledButton.icon(
          icon: Icon(widget.alreadyProvisioned && !hasCredentials ? Icons.refresh : Icons.person_add),
          label: Text(widget.alreadyProvisioned && !hasCredentials
              ? 'Reset Password & Show Credentials'
              : hasCredentials
                  ? 'Reset Password Again'
                  : 'Provision Account (Show Credentials)'),
          onPressed: () => _provision('in_person'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.send),
          label: Text(widget.alreadyProvisioned && !hasCredentials
              ? 'Reset Password & Send via SMS/WhatsApp'
              : hasCredentials
                  ? 'Reset & Send Again'
                  : 'Provision & Send via SMS/WhatsApp'),
          onPressed: () => _provision('both'),
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
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F5F5),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Row(
            children: [
              Expanded(
                child: SelectableText(
                  value,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy, size: 20),
                tooltip: 'Copy',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: value));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('$label copied'), duration: const Duration(seconds: 1)),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}
