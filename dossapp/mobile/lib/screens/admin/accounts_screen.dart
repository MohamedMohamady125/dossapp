import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/athlete.dart';
import '../../services/api_service.dart';
import '../../services/app_refresh.dart';
import '../../services/locale_provider.dart';
import '../../utils/formatters.dart';
import '../../utils/theme.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/shimmer_loading.dart';
import '../../widgets/ui_kit.dart';
import 'athletes_screen.dart';

/// Who is using the app, who was given a login and has not signed up, and
/// who has no login yet. Built for the rollout: the front desk opens it to
/// see how far along the branch is and who to chase next.
class AccountsScreen extends StatefulWidget {
  final int branchId;
  const AccountsScreen({super.key, required this.branchId});

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

enum _Stage { waiting, noLogin, signedUp }

class _AccountsScreenState extends State<AccountsScreen> with AutoRefresh {
  List<AthleteDetail>? _athletes;
  bool _loading = true;
  Object? _error;
  String _search = '';
  _Stage? _filter;
  Timer? _debounce;

  @override
  Future<void> silentReload() => _load();

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
    // The list stays on screen during a refresh; only the first load shows
    // a skeleton (Doherty Threshold: never blank a screen that has data).
    final isInitial = _athletes == null;
    if (isInitial) setState(() { _loading = true; _error = null; });
    try {
      final all = await ApiService.getBranchAthletes(widget.branchId);
      // This month's swimmers, plus anyone who already has a login
      _athletes = all.where((a) => _enrolled(a) || a.hasAccount).toList();
      _error = null;
    } catch (e) {
      if (isInitial) _error = e;
    }
    if (mounted) setState(() => _loading = false);
  }

  static bool _enrolled(AthleteDetail a) => a.type != null || a.days != null || a.schedule.isNotEmpty;

  static _Stage _stageOf(AthleteDetail a) =>
      a.accountCompleted ? _Stage.signedUp : (a.hasAccount ? _Stage.waiting : _Stage.noLogin);

  bool get _ar => context.read<LocaleProvider>().isArabic;
  String _t(String en, String ar) => _ar ? ar : en;

  /// "today", "yesterday", "5 days ago", in the app's language.
  String _ago(DateTime when) {
    final days = DateTime.now().difference(when.toLocal()).inDays;
    if (days <= 0) return _t('today', 'النهارده');
    if (days == 1) return _t('yesterday', 'امبارح');
    if (_ar) return days == 2 ? 'من يومين' : (days <= 10 ? 'من $days أيام' : 'من $days يوم');
    return '$days days ago';
  }

  List<AthleteDetail> get _visible {
    var list = _athletes ?? const <AthleteDetail>[];
    if (_search.isNotEmpty) {
      final q = _search.trim().toLowerCase().replaceFirst(RegExp(r'^[m#](?=\d)'), '');
      list = list.where((a) => a.name.toLowerCase().contains(q) || a.athleteNumber.toString().contains(q)).toList();
    } else if (_filter != null) {
      list = list.where((a) => _stageOf(a) == _filter).toList();
    }
    // Whoever needs a nudge first: longest wait at the top, then people with
    // no login, then the ones already in (most recently active first).
    int rank(AthleteDetail a) => switch (_stageOf(a)) { _Stage.waiting => 0, _Stage.noLogin => 1, _Stage.signedUp => 2 };
    final sorted = [...list];
    sorted.sort((a, b) {
      final byStage = rank(a).compareTo(rank(b));
      if (byStage != 0) return byStage;
      switch (_stageOf(a)) {
        case _Stage.waiting:
          return (a.invitedAt ?? DateTime(2100)).compareTo(b.invitedAt ?? DateTime(2100));
        case _Stage.signedUp:
          return (b.lastLoginAt ?? DateTime(2000)).compareTo(a.lastLoginAt ?? DateTime(2000));
        case _Stage.noLogin:
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      }
    });
    return sorted;
  }

  Future<void> _remind(AthleteDetail a) async {
    final messenger = ScaffoldMessenger.of(context);
    final text = Uri.encodeComponent(a.credentialsMessage ?? '');
    final phone = a.whatsappPhone ?? '';
    final url = phone.isNotEmpty ? 'https://wa.me/$phone?text=$text' : 'https://wa.me/?text=$text';
    try {
      final opened = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!opened) throw Exception('not opened');
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(_t('WhatsApp did not open on this phone', 'الواتساب مفتحش على الموبايل ده'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleProvider>(); // rebuild when the language changes
    if (_loading) return const SkeletonList(count: 6, hasAvatar: true);
    if (_error != null) return ErrorState(message: _error!, onRetry: _load);

    final all = _athletes ?? const <AthleteDetail>[];
    final signedUp = all.where((a) => _stageOf(a) == _Stage.signedUp).length;
    final waiting = all.where((a) => _stageOf(a) == _Stage.waiting).length;
    final noLogin = all.where((a) => _stageOf(a) == _Stage.noLogin).length;
    final list = _visible;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: _progressCard(signedUp, all.length),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            onChanged: (v) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 300), () {
                if (mounted) setState(() => _search = v);
              });
            },
            decoration: InputDecoration(
              hintText: _t('Search by name or number', 'دوّر بالاسم أو الرقم'),
              prefixIcon: const Icon(Icons.search, size: 20),
            ),
          ),
        ),
        // The three numbers are also the three filters (Hick's Law)
        if (_search.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Expanded(child: _tile(_Stage.waiting, Icons.hourglass_top_rounded, AppColors.warningDark, waiting, _t('Not signed up', 'لسه مسجّلش'))),
                const SizedBox(width: 8),
                Expanded(child: _tile(_Stage.noLogin, Icons.person_off_outlined, AppColors.textSecondary, noLogin, _t('No login', 'من غير حساب'))),
                const SizedBox(width: 8),
                Expanded(child: _tile(_Stage.signedUp, Icons.check_circle_rounded, AppColors.success, signedUp, _t('Signed up', 'سجّل'))),
              ],
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                _t('${formatNumber(list.length)} found', 'لقينا ${formatNumber(list.length)}'),
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
                        height: MediaQuery.of(context).size.height * 0.4,
                        child: EmptyState(
                          icon: _filter == _Stage.waiting || _filter == _Stage.noLogin
                              ? Icons.celebration_outlined
                              : Icons.search_off_rounded,
                          title: _search.isNotEmpty
                              ? _t('No swimmer found', 'مفيش سبّاح بالاسم ده')
                              : switch (_filter) {
                                  _Stage.waiting => _t('Nobody is waiting', 'مفيش حد مستني'),
                                  _Stage.noLogin => _t('Everyone has a login', 'كله عنده حساب'),
                                  _ => _t('Nobody here yet', 'مفيش حد هنا لسه'),
                                },
                        ),
                      ),
                    ],
                  )
                : ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, indent: 70),
                    itemBuilder: (ctx, i) => _row(list[i]),
                  ),
          ),
        ),
      ],
    );
  }

  /// How far the rollout is, as one number and a bar (Goal-Gradient Effect).
  Widget _progressCard(int signedUp, int total) {
    final share = total == 0 ? 0.0 : signedUp / total;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(gradient: AppColors.primaryGradient, borderRadius: BorderRadius.circular(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _t('Using the app', 'بيستخدموا التطبيق'),
            style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatNumber(signedUp),
                style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800, height: 1),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  _t('of ${formatNumber(total)} swimmers', 'من ${formatNumber(total)} سبّاح'),
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ),
              const Spacer(),
              Text(
                '${(share * 100).round()}%',
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: share,
              minHeight: 8,
              backgroundColor: Colors.white.withValues(alpha: 0.22),
              valueColor: const AlwaysStoppedAnimation(Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(_Stage stage, IconData icon, Color color, int count, String label) => StatTile(
        icon: icon,
        color: color,
        value: formatNumber(count),
        label: label,
        selected: _filter == stage,
        onTap: () => setState(() => _filter = _filter == stage ? null : stage),
      );

  // One row: who, and one line saying where they are. The only button is
  // the next step for that person (Fitts's Law: it sits under the thumb).
  Widget _row(AthleteDetail a) {
    final stage = _stageOf(a);
    final String line;
    final Color lineColor;
    switch (stage) {
      case _Stage.signedUp:
        final opened = a.lastLoginAt == null
            ? _t('Signed up', 'سجّل')
            : _t('Opened the app ${_ago(a.lastLoginAt!)}', 'فتح التطبيق ${_ago(a.lastLoginAt!)}');
        line = a.hasPush ? opened : '$opened • ${_t('alerts off', 'الإشعارات مقفولة')}';
        lineColor = AppColors.textSecondary;
      case _Stage.waiting:
        line = a.invitedAt == null
            ? _t('Has a login, not signed up', 'عنده حساب ولسه مسجّلش')
            : _t('Got the login ${_ago(a.invitedAt!)}', 'استلم الحساب ${_ago(a.invitedAt!)}');
        lineColor = AppColors.warningDark;
      case _Stage.noLogin:
        line = _t('No login yet', 'لسه معندوش حساب');
        lineColor = AppColors.textSecondary;
    }

    final Widget trailing;
    if (stage == _Stage.signedUp) {
      trailing = const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 22);
    } else if (stage == _Stage.waiting && a.credentialsMessage != null) {
      trailing = OutlinedButton(
        onPressed: () => _remind(a),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Text(_t('Remind', 'فكّره')),
      );
    } else {
      trailing = OutlinedButton(
        onPressed: () => showAthleteDetailSheet(context, a, _load),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Text(stage == _Stage.noLogin ? _t('Create', 'اعمل حساب') : _t('Open', 'افتح')),
      );
    }

    return ListTile(
      contentPadding: const EdgeInsetsDirectional.only(start: 16, end: 12, top: 2, bottom: 2),
      leading: InitialsAvatar(a.name),
      title: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
      subtitle: Text(
        '#${a.athleteNumber} • $line',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 13, color: lineColor),
      ),
      trailing: trailing,
      onTap: () => showAthleteDetailSheet(context, a, _load),
    );
  }
}
