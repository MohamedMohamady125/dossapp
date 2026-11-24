import '../../widgets/motion.dart';
import '../../utils/app_error.dart';
import '../../services/app_refresh.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import '../../services/locale_provider.dart';
import '../../utils/translations_staff.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/athlete.dart';
import '../../services/api_service.dart';
import '../../utils/theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/shimmer_loading.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/ui_kit.dart';
import '../reports/report_editor_screen.dart';

class AthletesScreen extends StatefulWidget {
  final int branchId;
  const AthletesScreen({super.key, required this.branchId});

  @override
  State<AthletesScreen> createState() => _AthletesScreenState();
}

class _AthletesScreenState extends State<AthletesScreen> with AutoRefresh {
  SS get t => SS.read(context);

  @override
  Future<void> silentReload() => _load();

  List<AthleteDetail>? _athletes;
  bool _loading = true;
  Object? _error;
  String _search = '';
  // Staff work on this month's swimmers; the full historical roster is one
  // tap away (Pareto, Hick's Law: a default plus one alternative).
  bool _enrolledOnly = true;
  // Tapping a summary tile narrows the list to that group: 'paid', 'unpaid'
  // or 'noprice' (Hick's Law: the numbers are the filters).
  String? _status;
  Timer? _debounce;

  static bool _isEnrolled(AthleteDetail a) => a.type != null || a.days != null || a.schedule.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    // Only show skeleton on initial load, not on refresh
    final isInitial = _athletes == null;
    if (isInitial) setState(() { _loading = true; _error = null; });
    try {
      _athletes = await ApiService.getBranchAthletes(widget.branchId);
    } catch (e) {
      if (isInitial) _error = e;
    }
    if (mounted) setState(() => _loading = false);
  }

  static bool _noPrice(AthleteDetail a) => !a.isPaid && a.bill == null && _isEnrolled(a);
  static bool _unpaid(AthleteDetail a) => !a.isPaid && a.bill != null && _isEnrolled(a);

  List<AthleteDetail> get _filtered {
    if (_athletes == null) return [];
    if (_search.isEmpty && _status != null) {
      return _athletes!.where((a) => switch (_status) {
        'paid' => a.isPaid && _isEnrolled(a),
        'unpaid' => _unpaid(a),
        _ => _noPrice(a),
      }).toList();
    }
    // Searching looks through everyone, so a swimmer is never "missing"
    // because of the filter (Postel's Law).
    if (_search.isEmpty) {
      return _enrolledOnly ? _athletes!.where(_isEnrolled).toList() : _athletes!;
    }
    final q = _search.trim().toLowerCase().replaceFirst(RegExp(r'^[m#](?=\d)'), '');
    return _athletes!.where((a) =>
      a.name.toLowerCase().contains(q) ||
      a.athleteNumber.toString().contains(q) ||
      (a.level?.toLowerCase().contains(q) ?? false)
    ).toList();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _search = value);
    });
  }

  // Loading, error and content replace each other with a soft fade
  @override
  Widget build(BuildContext context) {
    return FadeThrough(
      stateKey: _loading ? 'loading' : _error != null ? 'error' : 'content',
      child: _content(context),
    );
  }

  Widget _content(BuildContext context) {
    context.watch<LocaleProvider>(); // rebuild when the language changes
    if (_loading) return const SkeletonList(count: 6, hasAvatar: true);
    if (_error != null) {
      return ErrorState(message: _error!, onRetry: _load);
    }

    final list = _filtered;
    final all = _athletes ?? const <AthleteDetail>[];
    final enrolledCount = all.where(_isEnrolled).length;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            decoration: InputDecoration(
              hintText: t.searchByNameOrNumber,
              prefixIcon: Icon(Icons.search),
              isDense: true,
            ),
            onChanged: _onSearchChanged,
          ),
        ),
        if (_search.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Row(
              children: [
                Expanded(child: StatTile(
                  icon: Icons.pool_rounded, color: AppColors.primary,
                  value: formatNumber(enrolledCount), label: t.thisMonth,
                  selected: _status == null && _enrolledOnly,
                  onTap: () => setState(() { _status = null; _enrolledOnly = true; }),
                )),
                const SizedBox(width: 8),
                Expanded(child: StatTile(
                  icon: Icons.check_circle_rounded, color: AppColors.success,
                  value: formatNumber(all.where((a) => a.isPaid && _isEnrolled(a)).length), label: t.paid,
                  selected: _status == 'paid',
                  onTap: () => setState(() => _status = _status == 'paid' ? null : 'paid'),
                )),
                const SizedBox(width: 8),
                Expanded(child: StatTile(
                  icon: Icons.account_balance_wallet_rounded, color: AppColors.accent,
                  value: formatNumber(all.where(_unpaid).length), label: t.notPaid,
                  selected: _status == 'unpaid',
                  onTap: () => setState(() => _status = _status == 'unpaid' ? null : 'unpaid'),
                )),
                const SizedBox(width: 8),
                Expanded(child: StatTile(
                  icon: Icons.sell_rounded, color: AppColors.warningDark,
                  value: formatNumber(all.where(_noPrice).length), label: t.noPrice,
                  selected: _status == 'noprice',
                  onTap: () => setState(() => _status = _status == 'noprice' ? null : 'noprice'),
                )),
              ],
            ),
          ),
        if (_search.isEmpty && _status == null && enrolledCount != all.length)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: true, label: Text(t.thisMonthCount(enrolledCount))),
                  ButtonSegment(value: false, label: Text(t.everyoneCount(all.length))),
                ],
                selected: {_enrolledOnly},
                onSelectionChanged: (v) => setState(() => _enrolledOnly = v.first),
              ),
            ),
          )
        else if (_search.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                '${formatNumber(list.length)} found',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
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
                          title: t.noSwimmersFound,
                          subtitle: _search.isNotEmpty
                              ? t.nothingFoundFor(_search)
                              : t.branchHasNoSwimmers,
                        ),
                      ),
                    ],
                  )
                : ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, indent: 70),
                    // No AnimatedListItem here — causes jank on fast scroll with 1500+ athletes
                    itemBuilder: (ctx, i) => _buildAthleteRow(list[i]),
                  ),
          ),
        ),
      ],
    );
  }

  // One row = who, what class, and a single status in words. The old row had
  // up to three unlabelled icons and a five-part subtitle (Cognitive Load).
  Widget _buildAthleteRow(AthleteDetail a) {
    final noPrice = a.bill == null && a.billMissing != null && _isEnrolled(a);
    final classLine = [
      if (a.level != null) a.level!,
      if (a.type != null && a.type != a.level) a.type!,
    ].join(' \u2022 ');
    final subtitle = [
      swimmerId(a.athleteNumber),
      if (classLine.isNotEmpty) classLine,
      if (!_isEnrolled(a)) t.notInClassThisMonth,
    ].join(' \u2022 ');

    // Exactly one status, by priority: paid, then a missing price, then what is owed.
    final Widget? status;
    if (a.isPaid) {
      status = StatusPill(t.paid, AppColors.success, icon: Icons.check_rounded);
    } else if (noPrice) {
      status = StatusPill(t.noPrice, AppColors.warningDark);
    } else if (a.bill != null && _isEnrolled(a)) {
      status = Text(t.money(a.bill), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary));
    } else {
      status = null;
    }

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: InitialsAvatar(a.name),
      title: Text(a.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status != null) status,
        ],
      ),
      onTap: () => _showAthleteDetail(a),
    );
  }

  void _showAthleteDetail(AthleteDetail a) => showAthleteDetailSheet(context, a, _load);
}

/// The swimmer card, shared by the swimmers list and the app accounts page
/// so both open the same thing (Jakob's Law).
void showAthleteDetailSheet(BuildContext context, AthleteDetail a, VoidCallback onChanged) {
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
        child: _AthleteDetailSheet(athlete: a, onProvision: onChanged),
      ),
    ),
  );
}

class _AthleteDetailSheet extends StatefulWidget {
  final AthleteDetail athlete;
  final VoidCallback onProvision;

  const _AthleteDetailSheet({required this.athlete, required this.onProvision});

  @override
  State<_AthleteDetailSheet> createState() => _AthleteDetailSheetState();
}

class _AthleteDetailSheetState extends State<_AthleteDetailSheet> {
  SS get t => SS.read(context);

  bool _markingPaid = false;
  bool _markedPaid = false;
  String? _receiptNumber;

  Future<void> _showPaymentMethodDialog() async {
    final method = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.howDidTheyPay, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        content: Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: () => Navigator.pop(ctx, 'cash'),
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  decoration: BoxDecoration(
                    color: AppColors.successLight,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.money_rounded, size: 36, color: AppColors.success),
                      SizedBox(height: 8),
                      Text(t.cash, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.success)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: InkWell(
                onTap: () => Navigator.pop(ctx, 'card'),
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  decoration: BoxDecoration(
                    color: AppColors.primarySurface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.credit_card_rounded, size: 36, color: AppColors.primary),
                      SizedBox(height: 8),
                      Text(t.card, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.primary)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (method != null) {
      _markAsPaid(method);
    }
  }

  Future<void> _markAsPaid(String paymentMethod) async {
    setState(() => _markingPaid = true);
    try {
      final result = await ApiService.markAsPaid(widget.athlete.branchId, widget.athlete.athleteNumber, paymentMethod: paymentMethod);
      if (mounted) {
        setState(() {
          _markedPaid = true;
          _receiptNumber = result['receipt_number'];
        });
        widget.onProvision();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppError.messageFor(e))));
      }
    }
    if (mounted) setState(() => _markingPaid = false);
  }

  Future<void> _showSetBillDialog() async {
    final controller = TextEditingController();
    final amount = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.setAmountTitle, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
          autofocus: true,
          decoration: InputDecoration(
            labelText: t.amountEgp,
            prefixIcon: Icon(Icons.payments_outlined, size: 20),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t.cancel)),
          FilledButton(
            onPressed: () {
              final val = double.tryParse(controller.text.trim());
              if (val != null && val > 0) {
                Navigator.pop(ctx, val);
              }
            },
            child: Text(t.save),
          ),
        ],
      ),
    );
    if (amount != null && mounted) {
      try {
        await ApiService.setAthleteBill(widget.athlete.branchId, widget.athlete.athleteNumber, amount);
        if (mounted) {
          Navigator.pop(context); // Close detail sheet
          widget.onProvision(); // Reload list
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(t.amountSetTo(amount))),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppError.messageFor(e))));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleProvider>(); // rebuild when the language changes
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

        // ── Who ──
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              InitialsAvatar(athlete.name, size: 56),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      athlete.name,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${swimmerId(athlete.athleteNumber)} \u2022 ${athlete.branch}',
                      style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
                    ),
                    if (athlete.accountCompleted || athlete.hasAccount) ...[
                      const SizedBox(height: 6),
                      StatusPill(
                        athlete.accountCompleted ? t.usesTheApp : t.invitedToApp,
                        athlete.accountCompleted ? AppColors.primary : AppColors.textSecondary,
                        icon: Icons.phone_iphone_rounded,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),

        // ── Payment first: it is why staff open this sheet (Pareto), and its
        //    button is the only filled one here (Von Restorff). ──
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _paymentBlock(athlete),
        ),

        // ── App login: second, while the parent still has to sign up. It
        //    disappears once they do, so the card gets shorter over time. ──
        if (!athlete.accountCompleted) ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _ProvisionButton(
              branchId: athlete.branchId,
              athleteNumber: athlete.athleteNumber,
              phone: athlete.phone1,
              onDone: widget.onProvision,
              alreadyProvisioned: athlete.hasAccount,
              savedCode: athlete.loginCode,
              savedPassword: athlete.tempPassword,
              savedMessage: athlete.credentialsMessage,
              whatsappPhone: athlete.whatsappPhone,
            ),
          ),
        ],

        // ── Class ──
        _group(t.classTitle, Icons.pool_rounded, AppColors.primary, [
          _infoRow(t.level, athlete.level),
          if (athlete.type != athlete.level) _infoRow(t.classType, athlete.type),
          _infoRow(t.days, athlete.days),
          _infoRow(t.sessions, athlete.sessions),
          _infoRow(t.membership, athlete.segment),
          for (final slot in athlete.schedule)
            _infoRow(
              slot.dayPair ?? t.schedule,
              [if (slot.timeBlock != null) slot.timeBlock!, if (slot.coach != null) t.coachNamed(slot.coach!)].join(' \u2022 '),
            ),
        ]),

        // ── Contact ──
        _group(t.contact, Icons.phone_rounded, AppColors.primary, [
          _infoRow(t.phone1, athlete.phone1),
          _infoRow(t.phone2, athlete.phone2),
        ]),

        // ── Personal ──
        _group(t.aboutSwimmer, Icons.person_rounded, AppColors.primary, [
          _infoRow(t.age, athlete.age?.toStringAsFixed(1)),
          _infoRow(t.birthDate, athlete.dateOfBirth),
          _infoRow('Gender', t.genderOf(athlete.gender)),
          _infoRow(t.note, athlete.comment),
        ]),

        // ── Secondary actions, outlined so they do not compete ──
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: OutlinedButton.icon(
            icon: const Icon(Icons.assignment_outlined, size: 18),
            label: Text(t.monthlyReport),
            style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ReportEditorScreen(
                  branchId: athlete.branchId,
                  athleteNumber: athlete.athleteNumber,
                  athleteName: athlete.name,
                ),
              ),
            ),
          ),
        ),

        const SizedBox(height: 32),
      ],
    );
  }

  Widget _paymentBlock(AthleteDetail athlete) {
    final paid = athlete.isPaid || _markedPaid;
    final receipt = _receiptNumber ?? athlete.receiptNo;

    if (paid) {
      final amount = _markedPaid && athlete.bill != null ? athlete.bill : athlete.pay;
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.successLight.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.success.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 30),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  amount != null ? t.paidAmount(amount) : t.paid,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.textPrimary),
                ),
                Text(
                  [
                    if (receipt != null) t.receiptNo(receipt),
                    if (athlete.bill != null) t.priceIs(athlete.bill),
                  ].join(' \u2022 '),
                  style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
              ],
            )),
          ],
        ),
      );
    }

    if (athlete.bill != null) {
      return FilledButton(
        onPressed: _markingPaid ? null : _showPaymentMethodDialog,
        child: _markingPaid
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Text('Mark as paid \u2022 ${formatMoney(athlete.bill)}'),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.warningLight,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.noPriceForClass, style: const TextStyle(color: AppColors.warningDark, fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(
            athlete.billMissing ?? t.addPriceHelp,
            style: const TextStyle(color: AppColors.warningDark, fontSize: 13),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => _showSetBillDialog(),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 44),
              backgroundColor: Colors.white,
            ),
            child: Text(t.setAmountForSwimmer),
          ),
        ],
      ),
    );
  }

  // A titled card of label/value rows (Common Region). Renders nothing when
  // every row is empty, so staff never see a heading with no content.
  Widget _group(String title, IconData icon, Color color, List<Widget?> rows) {
    final shown = rows.whereType<Widget>().toList();
    if (shown.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                IconBadge(icon, color: color, size: 28),
                const SizedBox(width: 8),
                Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                for (var i = 0; i < shown.length; i++) ...[
                  shown[i],
                  if (i < shown.length - 1) const Divider(height: 1),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget? _infoRow(String label, String? value) {
    if (value == null || value.isEmpty) return null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: const TextStyle(fontSize: 14, color: AppColors.textSecondary)),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
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
  final String? phone;
  final VoidCallback onDone;
  final bool alreadyProvisioned;
  // Login details the server still holds because signup is unfinished
  final String? savedCode;
  final String? savedPassword;
  final String? savedMessage;
  final String? whatsappPhone;

  const _ProvisionButton({
    required this.branchId,
    required this.athleteNumber,
    required this.onDone,
    this.phone,
    this.alreadyProvisioned = false,
    this.savedCode,
    this.savedPassword,
    this.savedMessage,
    this.whatsappPhone,
  });

  @override
  State<_ProvisionButton> createState() => _ProvisionButtonState();
}

class _ProvisionButtonState extends State<_ProvisionButton> {
  SS get t => SS.read(context);

  bool _loading = false;
  String? _code;
  String? _pass;
  String? _message;
  String? _waPhone;
  // Set after this staff member creates or resets, to confirm it worked
  String? _justDone;

  bool _wasProvisioned = false;

  @override
  void initState() {
    super.initState();
    _code = widget.savedCode;
    _pass = widget.savedPassword;
    _message = widget.savedMessage;
    _waPhone = widget.whatsappPhone;
  }

  Future<void> _provision() async {
    setState(() => _loading = true);
    try {
      final Map<String, dynamic> result;
      final isReset = widget.alreadyProvisioned || _wasProvisioned;
      if (isReset) {
        result = await ApiService.reprovisionAccount(widget.branchId, widget.athleteNumber, 'in_person');
      } else {
        result = await ApiService.provisionAccount(widget.branchId, widget.athleteNumber, 'in_person');
        _wasProvisioned = true;
      }
      if (mounted) {
        setState(() {
          _code = result['login_code'] ?? '';
          _pass = result['temp_password'] ?? '';
          _message = result['credentials_message'] ?? _message;
          _waPhone = result['whatsapp_phone'] ?? _waPhone;
          _justDone = isReset ? t.newPasswordCreated : t.loginCreated;
        });
        widget.onDone();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppError.messageFor(e))));
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  /// The text comes from the server so the academy can reword it without an
  /// app update; the fallback only covers an older server.
  String get _whatsAppText => _message ?? t.whatsAppFallback(_code ?? '', _pass ?? '');

  Future<void> _sendViaWhatsApp() async {
    if (_code == null || _pass == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final notOpened = t.whatsAppNotOpened;
    // WhatsApp wants the country code and digits only
    final phone = _waPhone ?? (widget.phone ?? '').replaceAll(RegExp(r'[^\d]'), '');
    final text = Uri.encodeComponent(_whatsAppText);
    final url = phone.isNotEmpty ? 'https://wa.me/$phone?text=$text' : 'https://wa.me/?text=$text';
    try {
      final opened = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!opened) throw Exception('not opened');
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(notOpened)));
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleProvider>(); // rebuild when the language changes
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

    final hasAccount = widget.alreadyProvisioned || _wasProvisioned;
    final hasCode = _code != null && _code!.isNotEmpty;
    final hasPassword = _pass != null && _pass!.isNotEmpty;

    if (!hasAccount) {
      return OutlinedButton.icon(
        icon: const Icon(Icons.person_add_outlined, size: 18),
        label: Text(t.createLogin),
        onPressed: _provision,
        style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
      );
    }

    // One bordered group (Common Region): everything about the login lives here
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                _justDone != null ? Icons.check_circle_rounded : Icons.key_rounded,
                size: 20,
                color: _justDone != null ? AppColors.success : AppColors.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _justDone ?? t.appLoginDetails,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: _justDone != null ? AppColors.success : AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            t.loginDetailsHelp,
            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.35),
          ),
          const SizedBox(height: 12),
          if (hasCode) _CopyableField(label: t.loginCode, value: _code!),
          if (hasPassword) ...[
            const SizedBox(height: 12),
            _CopyableField(label: t.firstPassword, value: _pass!),
            const SizedBox(height: 14),
            // The one standout action on the card (Von Restorff)
            FilledButton.icon(
              icon: const Icon(Icons.send_rounded, size: 18),
              label: Text(t.sendOnWhatsApp),
              onPressed: _sendViaWhatsApp,
              style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.copy_all, size: 18),
                    label: Text(t.copy),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _whatsAppText));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(t.loginDetailsCopied)),
                      );
                    },
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: Text(t.newPassword),
                    onPressed: _provision,
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                  ),
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 10),
            Text(
              t.oldPasswordNotSaved,
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.35),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(t.createNewPassword),
              onPressed: _provision,
              style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
            ),
          ],
        ],
      ),
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
                  tooltip: SS.read(context).copy,
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: value));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(SS.read(context).copied(label)), duration: const Duration(seconds: 1)),
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
