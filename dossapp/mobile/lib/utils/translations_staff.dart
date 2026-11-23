import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/locale_provider.dart';
import 'formatters.dart';

/// Staff side text (admin, branch admin, coach) in plain English and in
/// everyday Egyptian Arabic.
///
/// It reads the same [LocaleProvider] as `S` in translations.dart, so both
/// switch together. It lives in its own file so staff and parent text can be
/// edited without touching each other.
///
/// In `build`:            `final t = SS.of(context);`
/// In a tap or async code: `final t = SS.read(context);`
///
/// Wording rules: one name per thing ("swimmer", "class", "log in", "sheet"),
/// short common words, no idioms, no dashes.
class SS {
  final String _lang;
  SS._(this._lang);

  /// Rebuilds the widget when the language changes. Use inside `build`.
  static SS of(BuildContext context) =>
      SS._(context.watch<LocaleProvider>().locale.languageCode);

  /// For callbacks and async code, where listening is not allowed.
  static SS read(BuildContext context) =>
      SS._(context.read<LocaleProvider>().locale.languageCode);

  static SS fromLocale(Locale locale) => SS._(locale.languageCode);

  bool get isArabic => _lang == 'ar';

  String _t(String en, String ar) => isArabic ? ar : en;

  /// Arabic counts change the noun: 1 سبّاح واحد, 2 سبّاحين, 3 to 10 سبّاحين,
  /// 11 and up سبّاح.
  String _arCount(int n, String one, String two, String few, String many) {
    if (n == 1) return one;
    if (n == 2) return two;
    if (n >= 3 && n <= 10) return '${formatNumber(n)} $few';
    return '${formatNumber(n)} $many';
  }

  // ───────────────────────── Numbers, money, dates ─────────────────────────

  /// 1500 becomes "1,500 EGP" or "1,500 جنيه".
  String money(dynamic value) => '${formatNumber(value)} ${_t('EGP', 'جنيه')}';

  static const _monthsEn = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  static const _monthsAr = [
    'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
    'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
  ];

  String monthName(int month) =>
      (isArabic ? _monthsAr : _monthsEn)[(month - 1).clamp(0, 11)];

  /// "2026-11" becomes "November 2026" or "نوفمبر 2026".
  String period(String value) {
    try {
      final parts = value.split('-');
      return '${monthName(int.parse(parts[1]))} ${int.parse(parts[0])}';
    } catch (_) {
      return value;
    }
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  /// "21/11/2026", the same in both languages.
  String date(String iso) {
    final t = DateTime.tryParse(iso)?.toLocal();
    return t == null ? iso : '${t.day}/${t.month}/${t.year}';
  }

  /// "21/11/2026 14:05".
  String dateTime(String iso) {
    final t = DateTime.tryParse(iso)?.toLocal();
    return t == null ? iso : '${t.day}/${t.month}/${t.year} ${_two(t.hour)}:${_two(t.minute)}';
  }

  /// "Just now", "5 minutes ago", "Today 14:05" or "21 November, 14:05" from
  /// an ISO string or a Unix time in seconds.
  String when(dynamic value) {
    if (value == null) return '';
    final raw = value.toString();
    DateTime? t = DateTime.tryParse(raw);
    if (t == null) {
      final seconds = double.tryParse(raw);
      if (seconds != null) {
        t = DateTime.fromMillisecondsSinceEpoch((seconds * 1000).round(), isUtc: true);
      }
    }
    if (t == null) return raw;
    t = t.toLocal();
    final now = DateTime.now();
    final diff = now.difference(t);
    if (!diff.isNegative && diff.inMinutes < 1) return _t('Just now', 'دلوقتي');
    if (!diff.isNegative && diff.inMinutes < 60) {
      final m = diff.inMinutes;
      return _t(
        '$m minute${m == 1 ? '' : 's'} ago',
        'من ${_arCount(m, 'دقيقة', 'دقيقتين', 'دقايق', 'دقيقة')}',
      );
    }
    final clock = '${_two(t.hour)}:${_two(t.minute)}';
    final sameDay = t.year == now.year && t.month == now.month && t.day == now.day;
    if (sameDay) return _t('Today $clock', 'النهارده $clock');
    return _t('${t.day} ${monthName(t.month)}, $clock', '${t.day} ${monthName(t.month)}، $clock');
  }

  /// "today", "yesterday" or "5 days ago" for a past date.
  String daysAgo(int days) {
    if (days <= 0) return today;
    if (days == 1) return yesterday;
    return _t('$days days ago', 'من ${_arCount(days, 'يوم', 'يومين', 'أيام', 'يوم')}');
  }

  String get today => _t('today', 'النهارده');
  String get yesterday => _t('yesterday', 'امبارح');

  /// "1 swimmer", "12 swimmers" / "سبّاح واحد", "12 سبّاح".
  String swimmersCount(int n) => _t(
        '${formatNumber(n)} swimmer${n == 1 ? '' : 's'}',
        _arCount(n, 'سبّاح واحد', 'سبّاحين', 'سبّاحين', 'سبّاح'),
      );

  // ───────────────────────────── Shared words ──────────────────────────────

  String get cancel => _t('Cancel', 'إلغاء');
  String get confirm => _t('Confirm', 'تأكيد');
  String get done => _t('Done', 'تمام');
  String get save => _t('Save', 'احفظ');
  String get delete => _t('Delete', 'امسح');
  String get edit => _t('Edit', 'عدّل');
  String get copy => _t('Copy', 'انسخ');
  String get required => _t('Required', 'مطلوب');
  String get refresh => _t('Refresh', 'حدّث');
  String get all => _t('All', 'الكل');
  String get branch => _t('Branch', 'الفرع');
  String get branches => _t('Branches', 'الفروع');
  String get swimmers => _t('Swimmers', 'السبّاحين');
  String get swimmer => _t('Swimmer', 'سبّاح');
  String get coach => _t('Coach', 'كابتن');
  String get paid => _t('Paid', 'اتدفع');
  String get notPaid => _t('Not paid', 'لسه مدفعش');
  String get collected => _t('Collected', 'المتحصّل');
  String get email => _t('Email', 'الإيميل');
  String get password => _t('Password', 'كلمة السر');
  String get username => _t('Username', 'اسم المستخدم');
  String get searchByNameOrNumber => _t('Search by name or number', 'دوّر بالاسم أو الرقم');
  String get somethingWentWrong => _t('Something went wrong. Please try again.', 'حصل مشكلة، جرّب تاني');

  String branchNumber(dynamic id) => _t('Branch $id', 'فرع $id');
  String swimmerNumber(dynamic number) => _t('Swimmer #$number', 'سبّاح رقم $number');
  String coachNamed(String name) => _t('Coach $name', 'كابتن $name');
  String receiptNo(dynamic number) => _t('Receipt $number', 'إيصال $number');
  String copied(String what) => _t('$what copied', 'اتنسخ: $what');
  String nothingFoundFor(String query) => _t('Nothing found for "$query"', 'مفيش نتايج لـ "$query"');
  String get tryAnotherSearch => _t('Try another name or number', 'جرّب اسم أو رقم تاني');

  /// How a payment was made, as the server names it.
  String channel(String raw) => switch (raw.trim().toLowerCase()) {
        'cash' => _t('Cash', 'كاش'),
        'card' => _t('Card', 'كارت'),
        'online' => _t('Online', 'أونلاين'),
        _ => raw,
      };

  // ───────────────────── Admin home (ready to wire in) ─────────────────────

  String get tabSwimmers => swimmers;
  String get tabAccounts => _t('Accounts', 'الحسابات');
  String get tabPayments => _t('Payments', 'المدفوعات');
  String get tabAnalytics => _t('Statistics', 'الإحصائيات');
  String get tabPrices => _t('Prices', 'الأسعار');
  String get menuRefresh => _t('Refresh from the sheet', 'حدّث من الشيت');
  String get menuSheetCheck => _t('Sheet check', 'فحص الشيت');
  String get menuBranches => branches;
  String get menuBranchAdmins => branchAdminsTitle;
  String get menuSettings => _t('Settings', 'الإعدادات');
  String get requestsToReturn => _t('Requests to return', 'طلبات الرجوع');
  String get noDataYet => _t('Nothing here yet', 'مفيش بيانات لسه');

  // ─────────────────── Swimmers list and card (ready to wire in) ───────────

  String get thisMonth => _t('This month', 'الشهر ده');
  String get noPrice => _t('No price', 'من غير سعر');
  String thisMonthCount(int n) => _t('This month (${formatNumber(n)})', 'الشهر ده (${formatNumber(n)})');
  String everyoneCount(int n) => _t('Everyone (${formatNumber(n)})', 'الكل (${formatNumber(n)})');
  String get noSwimmersFound => _t('No swimmers found', 'مفيش سبّاحين');
  String get branchHasNoSwimmers => _t('This branch has no swimmers yet', 'الفرع ده مفيهوش سبّاحين لسه');
  String get notInClassThisMonth => _t('Not in a class this month', 'مش في كلاس الشهر ده');

  String get howDidTheyPay => _t('How did they pay?', 'دفع إزاي؟');
  String get cash => _t('Cash', 'كاش');
  String get card => _t('Card', 'كارت');
  String get setAmountTitle => _t('Set the amount', 'حدّد المبلغ');
  String get amountEgp => _t('Amount (EGP)', 'المبلغ (جنيه)');
  String amountSetTo(dynamic amount) => _t('Amount set to ${money(amount)}', 'المبلغ بقى ${money(amount)}');

  String get usesTheApp => _t('Uses the app', 'بيستخدم الأبلكيشن');
  String get invitedToApp => _t('Invited', 'اتبعتله الدعوة');

  String get classTitle => _t('Class', 'الكلاس');
  String get level => _t('Level', 'المستوى');
  String get classType => _t('Class type', 'نوع الكلاس');
  String get days => _t('Days', 'الأيام');
  String get sessions => _t('Sessions', 'عدد الحصص');
  String get membership => _t('Membership', 'العضوية');
  String get schedule => _t('Schedule', 'الجدول');
  String get contact => _t('Contact', 'التواصل');
  String get phone1 => _t('Phone 1', 'موبايل 1');
  String get phone2 => _t('Phone 2', 'موبايل 2');
  String get aboutSwimmer => _t('About', 'بيانات السبّاح');
  String get age => _t('Age', 'السن');
  String get birthDate => _t('Birth date', 'تاريخ الميلاد');
  String get gender => _t('Gender', 'النوع');
  String get male => _t('Male', 'ولد');
  String get female => _t('Female', 'بنت');
  String genderOf(String? code) => code == 'M' ? male : code == 'F' ? female : (code ?? '');
  String get note => _t('Note', 'ملاحظة');
  String get monthlyReport => _t('Monthly report', 'التقرير الشهري');

  String paidAmount(dynamic amount) => _t('Paid ${money(amount)}', 'اتدفع ${money(amount)}');
  String priceIs(dynamic amount) => _t('Price ${money(amount)}', 'السعر ${money(amount)}');
  String get markPaid => _t('Mark as paid', 'سجّل الدفع');
  String markPaidAmount(dynamic amount) => '$markPaid • ${money(amount)}';
  String get noPriceForClass => _t('No price for this class yet', 'الكلاس ده ملوش سعر لسه');
  String get addPriceHelp => _t(
        'Add the price in the Prices tab, or set an amount for this swimmer only.',
        'ضيف السعر من تاب الأسعار، أو حدّد مبلغ للسبّاح ده بس.',
      );
  String get setAmountForSwimmer => _t('Set amount for this swimmer', 'حدّد مبلغ للسبّاح ده');

  // Login details on the swimmer card
  String get appLoginDetails => _t('App login details', 'بيانات دخول الأبلكيشن');
  String get loginDetailsHelp => _t(
        'Shown here until the parent logs in and chooses a password.',
        'هتفضل ظاهرة هنا لحد ما ولي الأمر يدخل ويختار كلمة سر.',
      );
  String get sendOnWhatsApp => _t('Send on WhatsApp', 'ابعت على واتساب');
  String get newPassword => _t('New password', 'كلمة سر جديدة');
  String get createNewPassword => _t('Create new password', 'اعمل كلمة سر جديدة');
  String get createLogin => _t('Create login', 'اعمل حساب');
  String get loginCode => _t('Login code', 'كود الدخول');
  String get firstPassword => _t('First password', 'كلمة السر المؤقتة');
  String get loginDetailsCopied => _t('Login details copied', 'بيانات الدخول اتنسخت');
  String get loginCreated => _t('Login created', 'الحساب اتعمل');
  String get newPasswordCreated => _t('New password created', 'كلمة السر الجديدة اتعملت');
  String get whatsAppNotOpened => _t('Could not open WhatsApp on this phone', 'معرفناش نفتح واتساب على الموبايل ده');
  String get oldPasswordNotSaved => _t(
        'This password is old and is not saved here. Create a new one to see it and send it.',
        'كلمة السر دي قديمة ومش محفوظة هنا. اعمل واحدة جديدة عشان تشوفها وتبعتها.',
      );

  /// Only used when the server did not send its own WhatsApp text.
  String whatsAppFallback(String code, String pass) => _t(
        'Aquathletic Academy\nYour login details:\nLogin code: $code\nPassword: $pass',
        'أكاديمية Aquathletic\nبيانات الدخول:\nكود الدخول: $code\nكلمة السر: $pass',
      );

  // ──────────────────── App sign-ups page (ready to wire in) ───────────────

  String get appSignUps => _t('App sign-ups', 'التسجيل في الأبلكيشن');
  String get signedUp => _t('Signed up', 'سجّلوا');
  String get waiting => _t('Waiting', 'مستنيين');
  String get notInvited => _t('Not invited', 'لسه ما اتبعتلهمش');
  String signedUpOf(int done, int total) => _t(
        '${formatNumber(done)} of ${formatNumber(total)} signed up',
        '${formatNumber(done)} من ${formatNumber(total)} سجّلوا',
      );
  String get signedUpWord => _t('signed up', 'سجّلوا');
  String get ofWord => _t('of', 'من');
  String get invited => _t('Invited', 'اتبعتله');
  String invitedWhen(String when) => _t('Invited $when', 'اتبعتله $when');
  String get lastOpened => _t('Last opened', 'آخر مرة فتح');
  String lastOpenedWhen(String when) => _t('Last opened $when', 'آخر مرة فتح $when');
  String get noLoginYet => _t('No login yet', 'ملوش حساب لسه');
  String get remind => _t('Remind', 'فكّره');
  String get everyoneSignedUp => _t('Everyone has signed up', 'كلهم سجّلوا');
  String get noSwimmersHere => _t('No swimmers here', 'مفيش سبّاحين هنا');

  // ─────────────────────────────── Payments ────────────────────────────────

  String collectedIn(String periodLabel) => _t('Collected in $periodLabel', 'المتحصّل في $periodLabel');
  String paidCount(int n) => _t('${formatNumber(n)} paid', '${formatNumber(n)} دفعوا');
  String get filter => _t('Filter', 'فلتر');
  String get notFinished => _t('Not finished', 'لسه ما كملش');
  String get noPaymentsThisMonth => _t('No payments this month', 'مفيش مدفوعات الشهر ده');
  String get paymentsShowAfterPay => _t(
        'Payments show here after a swimmer pays',
        'المدفوعات هتظهر هنا أول ما سبّاح يدفع',
      );
  String get receiptDownloadFailed => _t('Could not download the receipt', 'معرفناش ننزّل الإيصال');
  String get downloadReceipt => _t('Download receipt', 'نزّل الإيصال');

  // ─────────────────────────────── Statistics ──────────────────────────────

  String get thisBranch => _t('This branch', 'الفرع ده');
  String get allBranches => _t('All branches', 'كل الفروع');
  String get allBranchesTogether => _t('All branches together', 'كل الفروع مع بعض');
  String get compareBranches => _t('Compare branches', 'مقارنة الفروع');
  String get levels => _t('Levels', 'المستويات');
  String get levelsHelp => _t(
        'Swimmers at each level, biggest first',
        'عدد السبّاحين في كل مستوى، من الأكبر للأصغر',
      );
  String get ages => _t('Ages', 'الأعمار');
  String agesHelp({dynamic average, int missing = 0}) => [
        _t('Swimmers in each age group', 'عدد السبّاحين في كل سن'),
        if (average != null) _t('Average age $average', 'متوسط السن $average'),
        if (missing > 0) _t('$missing with no birth date', '$missing من غير تاريخ ميلاد'),
      ].join(' • ');

  /// The server sends age groups as "Under 5", "5-7", "18+".
  String ageGroup(String key) {
    if (key == 'Under 5') return _t('Under 5', 'أقل من 5');
    if (key.endsWith('+')) {
      final n = key.substring(0, key.length - 1);
      return _t('$n and up', '$n وأكبر');
    }
    final parts = key.split('-');
    if (parts.length == 2) return _t('${parts[0]} to ${parts[1]}', '${parts[0]} ل ${parts[1]}');
    return key;
  }

  String get daysTitle => _t('Days', 'الأيام');
  String get daysHelp => _t('Swimmers on each set of days', 'عدد السبّاحين في كل مجموعة أيام');
  String get classTypesHelp => _t('Swimmers in each class type', 'عدد السبّاحين في كل نوع كلاس');
  String get membershipHelp => _t(
        'Swimmers from the school and from outside',
        'سبّاحين المدرسة وسبّاحين من برّه',
      );
  String get collectedByMembership => _t('Collected by membership', 'المتحصّل حسب العضوية');
  String totalIs(String amount) => _t('Total: $amount', 'الإجمالي: $amount');
  String get genderTitle => _t('Male and female', 'ولاد وبنات');
  String get genderHelp => _t('Number of male and female swimmers', 'عدد الولاد وعدد البنات');
  String get maleMany => _t('Male', 'ولاد');
  String get femaleMany => _t('Female', 'بنات');
  String get notSet => _t('Not set', 'مش متسجّل');
  String get genderByLevel => _t('Male and female by level', 'ولاد وبنات في كل مستوى');
  String get genderByLevelHelp => _t(
        'Male and female swimmers at each level',
        'عدد الولاد والبنات في كل مستوى',
      );
  String get swimmersPerCoach => _t('Swimmers per coach', 'سبّاحين كل كابتن');
  String get swimmersPerCoachHelp => _t('Swimmers with each coach', 'عدد السبّاحين مع كل كابتن');
  String get missingInfo => _t('Missing information', 'بيانات ناقصة');
  String get missingInfoHelp => _t(
        'Swimmers with empty cells in the sheet',
        'سبّاحين عندهم خانات فاضية في الشيت',
      );
  String get noPhone => _t('No phone', 'من غير موبايل');
  String get noBirthDate => _t('No birth date', 'من غير تاريخ ميلاد');
  String get noLevel => _t('No level', 'من غير مستوى');
  String get noClassType => _t('No class type', 'من غير نوع كلاس');
  String get noGender => _t('No gender', 'من غير نوع');
  String get noDays => _t('No days', 'من غير أيام');

  // ───────────────────────────────── Prices ────────────────────────────────

  String get priceList => _t('Price list', 'قايمة الأسعار');
  String needsPrice(int n) => n > 0 ? _t('Needs a price ($n)', 'محتاج سعر ($n)') : _t('Needs a price', 'محتاج سعر');
  String get addPrice => _t('Add price', 'ضيف سعر');
  String get editPrice => _t('Edit price', 'عدّل السعر');
  String get className => _t('Class name', 'اسم الكلاس');
  String get classNameHint => _t('Example: Class, Private', 'مثال: كلاس، برايفت');
  String get membershipOptional => _t('Membership (optional)', 'العضوية (اختياري)');
  String get everyone => _t('Everyone', 'الكل');
  String get gemsStudents => _t('Gems students', 'طلبة جيمس');
  String get outsiders => _t('Outsiders', 'من برّه المدرسة');

  /// "Student" and "Outsider" are the values the sheet and server use.
  String segment(String? raw) =>
      raw == null ? '' : raw == 'Student' ? gemsStudents : raw == 'Outsider' ? outsiders : raw;
  String get sessionsOptional => _t('Sessions (optional)', 'عدد الحصص (اختياري)');
  String get sessionsHint => _t('Example: 8 Sessions', 'مثال: 8 Sessions');
  String get priceEgp => _t('Price (EGP)', 'السعر (جنيه)');
  String get priceHint => _t('Example: 1500', 'مثال: 1500');
  String get numbersOnly => _t('Numbers only', 'أرقام بس');
  String get savePrice => _t('Save price', 'احفظ السعر');
  String get deleteThisPrice => _t('Delete this price', 'امسح السعر ده');
  String get deletePriceTitle => _t('Delete price', 'مسح السعر');
  String deletePriceQuestion(String name) => _t('Delete the price for "$name"?', 'تمسح سعر "$name"؟');
  String get priceDeleted => _t('Price deleted', 'السعر اتمسح');
  String get noPricesYet => _t('No prices yet', 'مفيش أسعار لسه');
  String get pricesComeFromSheet => _t(
        'Prices come from the Sk. tab of the sheet. You can also add one here.',
        'الأسعار بتيجي من تاب Sk. في الشيت. وممكن تضيف سعر من هنا.',
      );
  String get monthly => _t('Monthly', 'شهري');
  String get everySwimmerHasPrice => _t('Every swimmer has a price', 'كل السبّاحين ليهم سعر');
  String get nothingToDo => _t('Nothing to do here.', 'مفيش حاجة مطلوبة هنا.');
  String swimmersNeedPrices(int swimmers, int prices) => _t(
        '${swimmersCount(swimmers)} ${swimmers == 1 ? 'has' : 'have'} no bill yet. '
            'Add ${prices == 1 ? 'this price' : 'these $prices prices'} first.',
        '${swimmersCount(swimmers)} من غير فاتورة. '
            'ضيف ${prices == 1 ? 'السعر ده' : 'الـ $prices أسعار دول'} الأول.',
      );
  String andMore(int n) => _t(' and $n more', ' و $n كمان');

  // ──────────────────────────────── Branches ───────────────────────────────

  String get addBranch => _t('Add branch', 'ضيف فرع');
  String get editBranch => _t('Edit branch', 'عدّل الفرع');
  String get shortName => _t(
        'Short name (English letters, no spaces)',
        'اسم مختصر (حروف إنجليزي من غير مسافات)',
      );
  String get shortNameHint => _t('Example: main_branch', 'مثال: main_branch');
  String get shortNameRule => _t('Small letters, numbers and _ only', 'حروف صغيرة وأرقام و _ بس');
  String get nameInApp => _t('Name shown in the app', 'الاسم اللي بيظهر في الأبلكيشن');
  String get nameInAppHint => _t('Example: Madinaty', 'مثال: مدينتي');
  String get sheetId => _t('Google Sheet ID', 'رقم الشيت (Google Sheet ID)');
  String get sheetIdHelp => _t('The part of the sheet link after /d/', 'الجزء اللي في لينك الشيت بعد /d/');
  String get deleteBranchTitle => _t('Delete branch', 'مسح الفرع');
  String deleteBranchQuestion(String name) => _t(
        'Delete "$name"? You cannot undo this.',
        'تمسح "$name"؟ مش هينفع ترجّعه تاني.',
      );
  String get branchDeleted => _t('Branch deleted', 'الفرع اتمسح');
  String get noBranchesYet => _t('No branches yet', 'مفيش فروع لسه');
  String get addFirstBranch => _t('Add your first branch to start.', 'ضيف أول فرع عشان تبدأ.');

  // ───────────────────────────── Branch admins ─────────────────────────────

  String get branchAdminsTitle => _t('Branch admins', 'أدمن الفروع');
  String get addBranchAdmin => _t('Add branch admin', 'ضيف أدمن فرع');
  String get noBranchAdminsYet => _t('No branch admins yet', 'مفيش أدمن فروع لسه');
  String get tapBelowToAdd => _t('Tap the button below to add one.', 'دوس على الزرار اللي تحت عشان تضيف واحد.');
  String get turnedOff => _t('Off', 'موقوف');
  String get waitingOne => _t('Waiting', 'مستني');
  String get hasNotLoggedIn => _t('Has not logged in', 'لسه ما دخلش');
  String get turnOff => _t('Turn off', 'وقّف');
  String get turnOn => _t('Turn on', 'شغّل');
  String get addBranchFirst => _t('Add a branch first', 'ضيف فرع الأول');
  String get chooseBranch => _t('Choose a branch', 'اختار فرع');
  String get emailNotCorrect => _t('This email is not correct', 'الإيميل ده مش صح');
  String get create => _t('Create', 'اعمل الحساب');
  String get branchAdminAdded => _t('Branch admin added', 'الأدمن اتضاف');
  String branchIs(String name) => _t('Branch: $name', 'الفرع: $name');
  String get giveLoginDetails => _t(
        'Give these login details to the branch admin. They will choose a new password the first time they log in.',
        'ادّي بيانات الدخول دي للأدمن. هيختار كلمة سر جديدة أول مرة يدخل.',
      );
  String loginDetailsText(String user, String pass) => _t(
        'Username: $user\nPassword: $pass',
        'اسم المستخدم: $user\nكلمة السر: $pass',
      );
  String newPasswordQuestion(String name) => _t(
        'Make a new password for $name? The old one will stop working.',
        'تعمل كلمة سر جديدة لـ $name؟ القديمة هتتلغي.',
      );
  String get turnOffAdminTitle => _t('Turn off this admin?', 'توقّف الأدمن ده؟');
  String get turnOnAdminTitle => _t('Turn on this admin?', 'تشغّل الأدمن ده؟');
  String cannotLogIn(String name) => _t('$name will not be able to log in.', '$name مش هيقدر يدخل.');
  String canLogInAgain(String name) => _t('$name will be able to log in again.', '$name هيقدر يدخل تاني.');

  // ─────────────────────────────── Sheet check ─────────────────────────────

  String get sheetOk => _t('OK', 'تمام');
  String get sheetNotLoaded => _t('Not loaded', 'ماتحمّلش');
  String sheetProblems(int n) => _t(
        '$n problem${n == 1 ? '' : 's'}',
        _arCount(n, 'مشكلة واحدة', 'مشكلتين', 'مشاكل', 'مشكلة'),
      );
  String get problems => _t('Problems', 'المشاكل');
  String get appLastReadSheet => _t('App last read the sheet', 'آخر مرة الأبلكيشن قرا الشيت');
  String get sheetLastEdited => _t('Sheet last edited', 'آخر تعديل في الشيت');

  // ──────────────────────────── Requests to return ─────────────────────────

  String get requestAccepted => _t(
        'Accepted. The swimmer can use the app again.',
        'اتقبل. السبّاح يقدر يستخدم الأبلكيشن تاني.',
      );
  String get rejectRequestTitle => _t('Reject request', 'رفض الطلب');
  String get parentWillBeTold => _t('The parent will be told the place is taken.', 'ولي الأمر هيتبلّغ إن المكان اتاخد.');
  String get noteToParentOptional => _t('Note to the parent (optional)', 'رسالة لولي الأمر (اختياري)');
  String get noteToParentHint => _t('Example: The place went to another swimmer', 'مثال: المكان راح لسبّاح تاني');
  String get requestRejected => _t('Request rejected', 'الطلب اترفض');
  String get reject => _t('Reject', 'ارفض');
  String get accept => _t('Accept', 'اقبل');
  String get statusWaiting => _t('Waiting', 'مستني');
  String get statusAccepted => _t('Accepted', 'اتقبل');
  String get statusRejected => _t('Rejected', 'اترفض');

  /// `status` is the server value: pending, approved or declined.
  String requestStatus(String status) => switch (status) {
        'approved' => statusAccepted,
        'declined' => statusRejected,
        _ => statusWaiting,
      };
  String noRequests(String status) => switch (status) {
        'approved' => _t('No accepted requests', 'مفيش طلبات مقبولة'),
        'declined' => _t('No rejected requests', 'مفيش طلبات مرفوضة'),
        _ => _t('No waiting requests', 'مفيش طلبات مستنية'),
      };
  String get newRequestsShowHere => _t('New requests will show here.', 'الطلبات الجديدة هتظهر هنا.');
  String get attendance => _t('Attendance', 'الحضور');
  String get percent => _t('Percent', 'النسبة');
  String get payment => _t('Payment', 'الدفع');
  String get sessionsShort => _t('Sessions', 'الحصص');
  String sentOn(String when) => _t('Sent on $when', 'اتبعت يوم $when');

  // ────────────────────────────────── Coach ────────────────────────────────

  String get noClassesYet => _t('No classes yet', 'مفيش حصص لسه');
  String get classesShowAfterSheet => _t(
        'Your classes show here after they are added to the sheet.',
        'حصصك هتظهر هنا أول ما تتضاف في الشيت.',
      );
  String get classes => _t('Classes', 'حصص');
  String get swimmersWord => _t('Swimmers', 'سبّاحين');
  String get daysNotSet => _t('Days not set', 'الأيام لسه متحددتش');

  // ───────────────────────────────── Reports ───────────────────────────────

  String get pdfUpTo10Mb => _t('PDF file, up to 10 MB', 'ملف PDF، لحد 10 ميجا');
  String megabytes(String size) => _t('$size MB', '$size ميجا');
}
