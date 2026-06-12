import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../utils/theme.dart';
import '../../utils/formatters.dart';

class AnalyticsScreen extends StatefulWidget {
  final int branchId;
  final bool isAdmin;
  const AnalyticsScreen({super.key, required this.branchId, required this.isAdmin});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;
  String _scope = 'branch';
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
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
      _data = await ApiService.getAnalytics(scope: _scope, branchId: _scope == 'branch' ? widget.branchId : null);
      _animController.forward(from: 0);
    } catch (e) {
      _error = e.toString();
    }
    setState(() => _loading = false);
  }

  Widget _animatedItem(int index, Widget child) {
    final delay = (index * 0.06).clamp(0.0, 0.6);
    return AnimatedBuilder(
      animation: _animController,
      builder: (ctx, c) {
        final value = Curves.easeOutCubic.transform(
          ((_animController.value - delay) / (1 - delay)).clamp(0.0, 1.0),
        );
        return Transform.translate(
          offset: Offset(0, 24 * (1 - value)),
          child: Opacity(opacity: value, child: c),
        );
      },
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (widget.isAdmin)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                _scopeChip('Branch', 'branch'),
                const SizedBox(width: 8),
                _scopeChip('Academy-wide', 'academy'),
              ],
            ),
          ),
        if (_loading)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (_error != null)
          Expanded(child: Center(child: Text(_error!, style: const TextStyle(color: AppColors.error))))
        else
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: _buildAnalytics().asMap().entries.map((e) => _animatedItem(e.key, e.value)).toList(),
              ),
            ),
          ),
      ],
    );
  }

  Widget _scopeChip(String label, String value) {
    final selected = _scope == value;
    return GestureDetector(
      onTap: () { _scope = value; _load(); },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label, style: TextStyle(
          fontSize: 13, fontWeight: FontWeight.w600,
          color: selected ? Colors.white : AppColors.textSecondary,
        )),
      ),
    );
  }

  List<Widget> _buildAnalytics() {
    if (_data == null) return [];
    final widgets = <Widget>[];
    final isAcademy = _data!.containsKey('academy_totals');

    if (isAcademy) {
      final t = _data!['academy_totals'];
      widgets.add(_heroCard(
        title: 'Academy Overview',
        stats: [
          _HeroStat('Athletes', formatNumber(t['total_athletes']), Icons.people),
          _HeroStat('Collected', formatMoney(t['total_collected']), Icons.payments),
          _HeroStat('Paid', formatNumber(t['paid_count']), Icons.check_circle),
        ],
      ));
      final branches = _data!['branches'] as Map<String, dynamic>? ?? {};
      widgets.add(_branchComparisonCard(branches));
      widgets.add(const SizedBox(height: 8));
      widgets.add(const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('All Branches Combined', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
      ));
      widgets.add(_aggregatedAnalytics(branches));
      return widgets;
    }

    final branches = _data!['branches'] as Map<String, dynamic>? ?? {};
    for (final entry in branches.entries) {
      final b = entry.value as Map<String, dynamic>;
      final c = b['collection'] as Map<String, dynamic>? ?? {};

      // Hero stats
      widgets.add(_heroCard(
        title: b['name'] ?? 'Branch',
        stats: [
          _HeroStat('Enrolled', formatNumber(c['total_enrolled'] ?? b['total_athletes']), Icons.people),
          _HeroStat('Collected', formatMoney(c['total_collected'] ?? 0), Icons.payments),
          _HeroStat('Paid', formatNumber(c['paid_count'] ?? 0), Icons.check_circle),
        ],
      ));

      // Retention funnel
      final funnel = (b['retention_funnel'] as List?) ?? [];
      if (funnel.isNotEmpty) widgets.add(_funnelCard(funnel));

      // Age pyramid
      final ageBuckets = b['age_buckets'] as Map<String, dynamic>? ?? {};
      final ageStats = b['age_stats'] as Map<String, dynamic>? ?? {};
      if (ageBuckets.isNotEmpty) widgets.add(_agePyramidCard(ageBuckets, ageStats));

      // Day demand
      final dayDemand = b['day_demand'] as Map<String, dynamic>? ?? {};
      if (dayDemand.isNotEmpty) {
        widgets.add(_barCard('Day Demand', dayDemand,
          subtitle: 'Number of swimmers enrolled per day combination',
          icon: Icons.calendar_today));
      }

      // Product type
      final types = b['enrollment_by_type'] as Map<String, dynamic>? ?? {};
      if (types.isNotEmpty) widgets.add(_barCard('Product Type', types,
        subtitle: 'Number of swimmers in each class type (Class, Private, Semi-Private, etc.)',
        icon: Icons.category));

      // Segment
      final segments = b['segment_mix'] as Map<String, dynamic>? ?? {};
      if (segments.isNotEmpty) widgets.add(_barCard('Segment Mix', segments,
        subtitle: 'Number of swimmers by enrollment source (GEMS school vs outside)',
        icon: Icons.school));

      // Revenue by segment
      final revBySeg = b['revenue_by_segment'] as Map<String, dynamic>? ?? {};
      if (revBySeg.isNotEmpty) widgets.add(_revenueCard('Revenue by Segment', revBySeg));

      // Gender
      final gender = b['gender_split'] as Map<String, dynamic>? ?? {};
      if (gender.isNotEmpty) widgets.add(_genderCard(gender));

      // Gender x level
      final gbl = b['gender_by_level'] as Map<String, dynamic>? ?? {};
      if (gbl.isNotEmpty) widgets.add(_genderByLevelCard(gbl));

      // Coach load
      final coaches = b['coach_load'] as Map<String, dynamic>? ?? {};
      if (coaches.isNotEmpty) widgets.add(_barCard('Coach Load', coaches,
        subtitle: 'Number of swimmers assigned to each coach',
        icon: Icons.person));

      // Data quality
      final dq = b['data_quality'] as Map<String, dynamic>? ?? {};
      if (dq.isNotEmpty) widgets.add(_dataQualityCard(dq));

      widgets.add(const SizedBox(height: 16));
    }
    return widgets;
  }

  // ── HERO STATS CARD ──
  Widget _heroCard({required String title, required List<_HeroStat> stats}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, Color(0xFF283593)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.25), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w500)),
          const SizedBox(height: 16),
          Row(
            children: stats.map((s) => Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(s.icon, color: Colors.white38, size: 20),
                  const SizedBox(height: 6),
                  Text(s.value, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(s.label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                ],
              ),
            )).toList(),
          ),
        ],
      ),
    );
  }

  // ── BRANCH COMPARISON ──
  Widget _branchComparisonCard(Map<String, dynamic> branches) {
    return _card(
      icon: Icons.compare_arrows, title: 'Branch Comparison',
      child: Column(
        children: [
          Row(children: const [
            Expanded(flex: 3, child: Text('Branch', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textMuted))),
            Expanded(flex: 2, child: Text('Athletes', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textMuted), textAlign: TextAlign.right)),
            Expanded(flex: 2, child: Text('Paid', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textMuted), textAlign: TextAlign.right)),
            Expanded(flex: 3, child: Text('Collected', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textMuted), textAlign: TextAlign.right)),
          ]),
          const Divider(height: 16),
          for (final entry in branches.entries)
            () {
              final b = entry.value as Map<String, dynamic>;
              final c = b['collection'] as Map<String, dynamic>? ?? {};
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  Expanded(flex: 3, child: Text(b['name'] ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
                  Expanded(flex: 2, child: Text(formatNumber(b['total_athletes']), style: const TextStyle(fontSize: 13), textAlign: TextAlign.right)),
                  Expanded(flex: 2, child: Text(formatNumber(c['paid_count'] ?? 0), style: const TextStyle(fontSize: 13), textAlign: TextAlign.right)),
                  Expanded(flex: 3, child: Text(formatMoney(c['total_collected'] ?? 0), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600), textAlign: TextAlign.right)),
                ]),
              );
            }(),
        ],
      ),
    );
  }

  Widget _aggregatedAnalytics(Map<String, dynamic> branches) {
    final Map<String, int> allLevels = {}, allTypes = {}, allSegments = {}, allGender = {}, allAgeBuckets = {}, allDays = {};
    for (final b in branches.values) {
      final bd = b as Map<String, dynamic>;
      _merge(allLevels, bd['enrollment_by_level'] as Map<String, dynamic>? ?? {});
      _merge(allTypes, bd['enrollment_by_type'] as Map<String, dynamic>? ?? {});
      _merge(allSegments, bd['segment_mix'] as Map<String, dynamic>? ?? {});
      _merge(allGender, bd['gender_split'] as Map<String, dynamic>? ?? {});
      _merge(allAgeBuckets, bd['age_buckets'] as Map<String, dynamic>? ?? {});
      _merge(allDays, bd['day_demand'] as Map<String, dynamic>? ?? {});
    }
    final widgets = <Widget>[];
    if (allLevels.isNotEmpty) widgets.add(_barCard('Enrollment by Level', _toDyn(allLevels), icon: Icons.stairs));
    if (allAgeBuckets.isNotEmpty) widgets.add(_agePyramidCard(_toDyn(allAgeBuckets), {}));
    if (allDays.isNotEmpty) widgets.add(_barCard('Day Demand', _toDyn(allDays), icon: Icons.calendar_today));
    if (allTypes.isNotEmpty) widgets.add(_barCard('Product Type', _toDyn(allTypes), icon: Icons.category));
    if (allSegments.isNotEmpty) widgets.add(_barCard('Segment Mix', _toDyn(allSegments), icon: Icons.school));
    if (allGender.isNotEmpty) widgets.add(_genderCard(_toDyn(allGender)));
    return Column(children: widgets);
  }

  void _merge(Map<String, int> t, Map<String, dynamic> s) { for (final e in s.entries) t[e.key] = (t[e.key] ?? 0) + (e.value as int); }
  Map<String, dynamic> _toDyn(Map<String, int> m) => m.map((k, v) => MapEntry(k, v));

  // ── FUNNEL ──
  Widget _funnelCard(List<dynamic> funnel) {
    final maxCount = funnel.isNotEmpty ? (funnel.first['count'] as int) : 1;
    return _card(
      icon: Icons.filter_list, title: 'Swimmer Levels',
      subtitle: 'Number of swimmers at each level \u2022 Sorted highest to lowest',
      child: Column(
        children: [
          for (final f in funnel) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                SizedBox(width: 80, child: Text(f['level'], style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: maxCount > 0 ? (f['count'] as int) / maxCount : 0),
                      duration: const Duration(milliseconds: 700),
                      curve: Curves.easeOutCubic,
                      builder: (ctx, value, _) => Stack(children: [
                        Container(height: 22, decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(4))),
                        FractionallySizedBox(
                          widthFactor: value,
                          child: Container(height: 22, decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(4),
                          )),
                        ),
                      ]),
                    ),
                  ),
                ),
                SizedBox(width: 40, child: Text(formatNumber(f['count']), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12), textAlign: TextAlign.right)),
                SizedBox(width: 45, child: Text('${f['pct_of_top'] ?? ''}%',
                    style: const TextStyle(fontSize: 11, color: AppColors.textMuted), textAlign: TextAlign.right)),
              ]),
            ),
          ],
        ],
      ),
    );
  }

  // ── AGE PYRAMID ──
  Widget _agePyramidCard(Map<String, dynamic> buckets, Map<String, dynamic> stats) {
    final order = ['Under 5', '5-7', '8-10', '11-13', '14-17', '18+'];
    final maxVal = buckets.values.fold<int>(0, (m, v) { final val = v as int; return val > m ? val : m; });
    return _card(
      icon: Icons.bar_chart, title: 'Age Distribution',
      subtitle: 'Number of swimmers in each age group${stats['avg'] != null ? ' \u2022 Avg ${stats['avg']} yrs' : ''}${(stats['missing_dob'] ?? 0) > 0 ? ' \u2022 ${stats['missing_dob']} missing DOB' : ''}',
      child: Column(
        children: [
          for (final age in order) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                SizedBox(width: 55, child: Text(age, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))),
                Expanded(child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Stack(children: [
                    Container(height: 20, color: AppColors.surfaceVariant),
                    FractionallySizedBox(widthFactor: maxVal > 0 ? ((buckets[age] ?? 0) as int) / maxVal : 0,
                      child: Container(height: 20, decoration: BoxDecoration(color: AppColors.secondary.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(4)))),
                  ]),
                )),
                SizedBox(width: 40, child: Text(formatNumber(buckets[age] ?? 0), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12), textAlign: TextAlign.right)),
              ]),
            ),
          ],
        ],
      ),
    );
  }

  // ── GENDER ──
  Widget _genderCard(Map<String, dynamic> g) {
    final m = (g['M'] ?? 0) as int, f = (g['F'] ?? 0) as int, u = (g['Unknown'] ?? 0) as int;
    final t = m + f + u;
    return _card(icon: Icons.wc, title: 'Gender Split', subtitle: 'Number of male vs female swimmers', child: Column(children: [
      if (t > 0) ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Row(children: [
          if (m > 0) Expanded(flex: m, child: Container(height: 32, color: const Color(0xFF3B82F6),
            alignment: Alignment.center, child: Text('${(m * 100 / t).round()}% M', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)))),
          if (f > 0) Expanded(flex: f, child: Container(height: 32, color: const Color(0xFFEC4899),
            alignment: Alignment.center, child: Text('${(f * 100 / t).round()}% F', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)))),
          if (u > 0) Expanded(flex: u, child: Container(height: 32, color: AppColors.textMuted,
            alignment: Alignment.center, child: Text('${(u * 100 / t).round()}% ?', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)))),
        ]),
      ),
      const SizedBox(height: 10),
      Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
        _genderStat('Male', m, const Color(0xFF3B82F6)),
        _genderStat('Female', f, const Color(0xFFEC4899)),
        if (u > 0) _genderStat('Unknown', u, AppColors.textMuted),
      ]),
    ]));
  }

  Widget _genderStat(String label, int count, Color color) {
    return Column(children: [
      Text(formatNumber(count), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: color)),
      Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
    ]);
  }

  // ── GENDER × LEVEL ──
  Widget _genderByLevelCard(Map<String, dynamic> data) {
    final levels = ['P.p1','P.p2','St.1','St.2','St.3','St.4.1','St.5.1','St.6.1','St.7.1'].where((l) => data.containsKey(l)).toList();
    if (levels.isEmpty) return const SizedBox.shrink();
    return _card(icon: Icons.stacked_bar_chart, title: 'Gender by Level', subtitle: 'Male vs female swimmers at each level \u2022 Shows which gender drops off faster', child: Column(children: [
      for (final lvl in levels) ...[
        () {
          final d = data[lvl] as Map<String, dynamic>;
          final m = (d['M'] ?? 0) as int, f = (d['F'] ?? 0) as int, t = m + f;
          return Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(children: [
            SizedBox(width: 45, child: Text(lvl, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500))),
            Expanded(child: t > 0 ? ClipRRect(borderRadius: BorderRadius.circular(3), child: Row(children: [
              if (m > 0) Expanded(flex: m, child: Container(height: 16, color: const Color(0xFF3B82F6).withValues(alpha: 0.7))),
              if (f > 0) Expanded(flex: f, child: Container(height: 16, color: const Color(0xFFEC4899).withValues(alpha: 0.5))),
            ])) : const SizedBox.shrink()),
            SizedBox(width: 50, child: Text('$m / $f', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500), textAlign: TextAlign.right)),
          ]));
        }(),
      ],
      const SizedBox(height: 8),
      Row(children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: const Color(0xFF3B82F6), borderRadius: BorderRadius.circular(2))),
        const Text(' Male  ', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        Container(width: 10, height: 10, decoration: BoxDecoration(color: const Color(0xFFEC4899), borderRadius: BorderRadius.circular(2))),
        const Text(' Female', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
      ]),
    ]));
  }

  // ── REVENUE ──
  Widget _revenueCard(String title, Map<String, dynamic> data) {
    final sorted = data.entries.toList()..sort((a, b) => ((b.value as num) - (a.value as num)).toInt());
    final total = sorted.fold<double>(0, (s, e) => s + (e.value as num).toDouble());
    return _card(icon: Icons.monetization_on, iconColor: AppColors.success, title: title, subtitle: 'Amount collected in EGP per segment \u2022 Total: ${formatMoney(total)}', child: Column(
      children: [for (final e in sorted) Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [
        Expanded(flex: 2, child: Text(e.key, style: const TextStyle(fontSize: 13))),
        Expanded(flex: 3, child: ClipRRect(borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(value: total > 0 ? (e.value as num) / total : 0, backgroundColor: AppColors.surfaceVariant, color: AppColors.success, minHeight: 8))),
        const SizedBox(width: 8),
        Text(formatMoney(e.value), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
      ]))],
    ));
  }

  // ── DATA QUALITY ──
  Widget _dataQualityCard(Map<String, dynamic> dq) {
    final total = (dq['total'] ?? 1) as int;
    final pct = dq['completeness_pct'] ?? 0;
    final fields = [
      ('Missing Phone', dq['no_phone'] ?? 0),
      ('Missing DOB', dq['no_dob'] ?? 0),
      ('Missing Level', dq['no_level'] ?? 0),
      ('Missing Type', dq['no_type'] ?? 0),
      ('Missing Gender', dq['no_gender'] ?? 0),
      ('Missing Days', dq['no_days'] ?? 0),
    ];
    final scoreColor = (pct as num) > 80 ? AppColors.success : (pct as num) > 60 ? AppColors.warning : AppColors.error;
    return _card(
      icon: Icons.health_and_safety, iconColor: scoreColor, title: 'Data Quality',
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: scoreColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
        child: Text('$pct%', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: scoreColor)),
      ),
      subtitle: 'Number of swimmers with missing info in Excel \u2022 Higher = more data entry needed',
      child: Column(children: [
        for (final (label, value) in fields)
          if ((value as int) > 0) Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(children: [
            Expanded(flex: 2, child: Text(label, style: const TextStyle(fontSize: 13))),
            Expanded(flex: 3, child: ClipRRect(borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(value: total > 0 ? value / total : 0, backgroundColor: AppColors.surfaceVariant,
                color: value / total > 0.3 ? AppColors.error : AppColors.warning, minHeight: 6))),
            const SizedBox(width: 8),
            Text('${formatNumber(value)}/$total', style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12, color: AppColors.textSecondary)),
          ])),
      ]),
    );
  }

  // ── REUSABLE BAR CARD ──
  Widget _barCard(String title, Map<String, dynamic> data, {String? subtitle, IconData? icon}) {
    final sorted = data.entries.toList()..sort((a, b) => ((b.value as num) - (a.value as num)).toInt());
    final total = sorted.fold<int>(0, (s, e) => s + (e.value as int));
    return _card(icon: icon, title: title, subtitle: subtitle, child: Column(
      children: [for (final e in sorted) Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(children: [
        Expanded(flex: 2, child: Text(e.key, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))),
        Expanded(flex: 3, child: ClipRRect(borderRadius: BorderRadius.circular(4),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: total > 0 ? (e.value as int) / total : 0),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            builder: (ctx, value, _) => LinearProgressIndicator(
              value: value, backgroundColor: AppColors.surfaceVariant,
              color: AppColors.primary.withValues(alpha: 0.6), minHeight: 8,
            ),
          ),
        )),
        const SizedBox(width: 8),
        Text(formatNumber(e.value), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
      ]))],
    ));
  }

  // ── BASE CARD WRAPPER ──
  Widget _card({IconData? icon, Color? iconColor, required String title, String? subtitle, Widget? trailing, required Widget child}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              if (icon != null) ...[
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: (iconColor ?? AppColors.primary).withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
                  child: Icon(icon, size: 16, color: iconColor ?? AppColors.primary),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.textPrimary))),
              if (trailing != null) trailing,
            ]),
            if (subtitle != null) Padding(
              padding: EdgeInsets.only(top: 2, left: icon != null ? 32.0 : 0),
              child: Text(subtitle, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class _HeroStat {
  final String label, value;
  final IconData icon;
  _HeroStat(this.label, this.value, this.icon);
}
