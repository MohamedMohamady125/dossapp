import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/locale_provider.dart';

class S {
  final String _lang;
  S._(this._lang);

  static S of(BuildContext context) {
    final locale = context.watch<LocaleProvider>().locale;
    return S._(locale.languageCode);
  }

  /// Outside build (button handlers, validators): reads the language
  /// without subscribing, which `of` is not allowed to do there.
  static S read(BuildContext context) => S._(context.read<LocaleProvider>().locale.languageCode);

  bool get isArabic => _lang == 'ar';

  /// Use this when you don't have a context (e.g., in initState)
  static S fromLocale(Locale locale) => S._(locale.languageCode);

  String _t(String en, String ar) => _lang == 'ar' ? ar : en;

  // ── App ──
  String get appName => 'Aquathletic';
  String get swimmingAcademy => _t('Swimming Academy', 'أكاديمية سباحة');

  // ── Auth ──
  String get login => _t('Log in', 'تسجيل الدخول');
  String get logout => _t('Log out', 'تسجيل الخروج');
  String get logoutConfirm => _t('Do you want to log out?', 'عايز تسجّل خروج؟');
  String get parentAthlete => _t('Parent or swimmer', 'ولي أمر أو سبّاح');
  String get staff => _t('Staff', 'فريق العمل');
  String get loginCode => _t('Login code', 'كود الدخول');
  String get loginCodeOrEmail => _t('Login code or email', 'كود الدخول أو الإيميل');
  String get loginHelp => _t('Use your email or your login code. The code looks like MAD-1091.', 'ادخل بالإيميل أو بكود الدخول. الكود شكله كده: MAD-1091');
  String get whoIsSwimming => _t('Choose a swimmer', 'اختار السبّاح');
  String get chooseSwimmerSubtitle => _t('Your email has more than one swimmer. Tap one to open it.', 'الإيميل بتاعك عليه أكتر من سبّاح. دوس على واحد عشان تفتحه.');
  String get switchAnytime => _t('To change swimmer later, tap the name at the top of the home screen.', 'تقدر تبدّل في أي وقت. دوس على الاسم اللي فوق في الصفحة الرئيسية.');
  String get switchSwimmer => _t('Change swimmer', 'بدّل السبّاح');
  String get sessionExpired => _t('You were logged out. Please log in again.', 'اتسجّل خروجك. سجّل الدخول تاني.');
  String get confirmingPayment => _t('Checking your payment...', 'بنتأكد من الدفع...');
  String get sendCode => _t('Send code', 'ابعت الكود');
  String codeSentTo(String email) => _t('We sent a 6 digit code to $email. Type it here to save this email.', 'بعتنا كود من 6 أرقام على $email. اكتبه هنا عشان نحفظ الإيميل.');
  String get codeLabel => _t('6 digit code', 'الكود (6 أرقام)');
  String get verifyAndSave => _t('Check and save', 'تأكيد وحفظ');
  String get useDifferentEmail => _t('Use another email', 'استخدم إيميل تاني');
  String get viewingNow => _t('Open now', 'مفتوح دلوقتي');
  String nowViewing(String name) => _t('Now showing $name', 'دلوقتي بتتابع $name');
  String get addSwimmer => _t('Add another swimmer', 'ضيف سبّاح تاني');
  String get addSwimmerHelp => _t('Type the login code and password the front desk gave you for this child. After that, this child opens with your email and password.', 'اكتب كود الدخول وكلمة السر اللي أخدتهم من الاستقبال للطفل ده. بعد كده هيفتح بإيميلك وكلمة السر بتاعتك.');
  String get addSwimmerButton => _t('Add swimmer', 'ضيف السبّاح');
  String swimmerAdded(String name) => _t(name.isEmpty ? 'Swimmer added' : '$name was added', name.isEmpty ? 'السبّاح اتضاف' : '$name اتضاف');
  String get fillCodeAndPassword => _t('Type the login code and the password', 'اكتب كود الدخول وكلمة السر');
  String get username => _t('Username', 'اسم المستخدم');
  String get password => _t('Password', 'كلمة السر');
  String get forgotPassword => _t('Forgot password?', 'نسيت كلمة السر؟');
  String get forgotPasswordTitle => _t('Forgot password', 'نسيت كلمة السر');
  String get forgotPasswordBody => _t('Please ask your branch to reset your password.', 'كلّم الفرع عشان يغيّرولك كلمة السر.');
  String get contactBranch => _t('Contact the branch', 'كلّم الفرع');
  String get required => _t('Required', 'مطلوب');
  String get invalidCredentials => _t('Wrong login details. Check them and try again.', 'البيانات مش مظبوطة. راجعها وجرّب تاني.');
  String get tooManyAttempts => _t('Too many tries. Wait a few minutes, then try again.', 'محاولات كتير. استنى كام دقيقة وجرّب تاني.');

  // ── Change Password ──
  String get changePassword => _t('Change password', 'غيّر كلمة السر');
  String get currentPassword => _t('Current password', 'كلمة السر الحالية');
  String get newPassword => _t('New password', 'كلمة السر الجديدة');
  String get confirmPassword => _t('Repeat password', 'اكتب كلمة السر تاني');
  String get passwordChanged => _t('Password changed', 'كلمة السر اتغيّرت');
  String get passwordTooShort => _t('Use at least 6 characters', 'كلمة السر لازم تكون 6 حروف أو أكتر');
  String get passwordsMustMatch => _t('The two passwords are not the same', 'كلمتين السر مش زي بعض');
  String get createNewPassword => _t('Choose a new password for your account', 'اختار كلمة سر جديدة لحسابك');
  String get passwordStrength => _t('Password strength', 'قوة كلمة السر');
  String get weak => _t('Weak', 'ضعيفة');
  String get fair => _t('OK', 'مقبولة');
  String get good => _t('Good', 'كويسة');
  String get strong => _t('Strong', 'قوية');
  String get veryStrong => _t('Very strong', 'قوية جدًا');
  String get setPassword => _t('Save password', 'احفظ كلمة السر');

  // ── Settings ──
  String get settings => _t('Settings', 'الإعدادات');
  String get profile => _t('Profile', 'حسابي');
  String get language => _t('Language', 'اللغة');
  String get english => _t('English', 'الإنجليزية');
  String get arabic => _t('Arabic', 'العربية');
  String get changeEmail => _t('Change email', 'غيّر الإيميل');
  String get email => _t('Email', 'الإيميل');
  String get newEmail => _t('New email', 'الإيميل الجديد');
  String get emailUpdated => _t('Email changed', 'الإيميل اتغيّر');
  String get invalidEmail => _t('This email does not look right', 'الإيميل ده مش مظبوط');
  String get save => _t('Save', 'حفظ');
  String get cancel => _t('Cancel', 'إلغاء');
  String get confirm => _t('Confirm', 'تأكيد');
  String get appVersion => _t('App version', 'إصدار التطبيق');
  String get account => _t('Account', 'الحساب');
  String get general => _t('General', 'عام');
  String get deleteAccount => _t('Delete account', 'امسح الحساب');
  String get deleteAccountConfirm => _t('This deletes your account and all its data for good. You cannot undo it.', 'حسابك وكل بياناته هيتمسحوا نهائي، ومش هينفع ترجّعهم.');
  String get deleteAccountSuccess => _t('Account deleted', 'الحساب اتمسح');
  String get enterPasswordToConfirm => _t('Type your password to confirm', 'اكتب كلمة السر للتأكيد');
  String get privacyPolicy => _t('Privacy policy', 'سياسة الخصوصية');
  String get about => _t('About', 'عن التطبيق');

  // ── Customer Home ──
  String get home => _t('Home', 'الرئيسية');
  String get pay => _t('Pay', 'الدفع');
  String get receipts => _t('Receipts', 'الإيصالات');
  String get alerts => _t('Alerts', 'التنبيهات');
  String get welcome => _t('Welcome', 'أهلًا بيك');
  String get myProfile => _t('My profile', 'حسابي');
  String get athleteNumber => _t('Swimmer number', 'رقم السبّاح');
  String get branch => _t('Branch', 'الفرع');
  String get practiceSchedule => _t('Training times', 'مواعيد التمرين');
  String get practiceTimes => _t('Training times', 'مواعيد التمرين');
  String get attendance => _t('Attendance', 'الحضور');
  String get present => _t('Attended', 'حضر');
  String get absent => _t('Missed', 'غاب');
  String get paymentStatus => _t('Payment', 'حالة الدفع');
  String get athleteDetails => _t('Swimmer details', 'بيانات السبّاح');
  String get enrollment => _t('Registration', 'الاشتراك');
  String get classInfo => _t('Class', 'التمرين');
  String get type => _t('Type', 'النوع');
  String get level => _t('Level', 'المستوى');
  String get days => _t('Days', 'الأيام');
  String get sessions => _t('Sessions', 'الحصص');
  String get coach => _t('Coach', 'الكابتن');
  String get age => _t('Age', 'السن');
  String get gender => _t('Gender', 'النوع');
  String get male => _t('Male', 'ذكر');
  String get female => _t('Female', 'أنثى');
  String get dateOfBirth => _t('Date of birth', 'تاريخ الميلاد');
  String get phone => _t('Phone', 'الموبايل');

  // ── Bill ──
  String get myBill => _t('My bill', 'فاتورتي');
  String get amountDue => _t('Amount to pay', 'المطلوب دفعه');
  String get paid => _t('Paid', 'مدفوع');
  String get unpaid => _t('Not paid', 'مش مدفوع');
  String get serviceDetails => _t('What you pay for', 'تفاصيل الاشتراك');
  String get swimmingLessonsAt => _t('Swimming lessons in person at', 'تمارين سباحة حضورية في فرع');
  String get billPending => _t('Bill not ready yet', 'الفاتورة لسه ما جهزتش');
  String get billPendingMsg => _t('Your branch has not set the amount yet.\nWe will tell you when it is ready.', 'الفرع لسه ما حدّدش المبلغ.\nهنبعتلك تنبيه أول ما تجهز.');
  String get enrollmentWindowClosed => _t('Payment time is over', 'ميعاد الدفع خلص');
  String get enrollmentWindowClosedMsg => _t('The time to pay for this month is over.\nGo to Home to ask if a spot\nis still free in your class.', 'ميعاد الدفع للشهر ده خلص.\nروح للرئيسية واسأل لو لسه في\nمكان فاضي في تمرينك.');
  String get noActiveEnrollment => _t('Not in a class this month', 'مفيش اشتراك الشهر ده');
  String get noActiveEnrollmentMsg => _t('You are not in a class this month.\nContact your branch to join one.', 'مش مشترك في تمرين الشهر ده.\nكلّم الفرع عشان تشترك.');
  String get processing => _t('Please wait...', 'لحظة واحدة...');
  String payAmount(String amount) => _t('Pay $amount', 'ادفع $amount');
  String receiptLabel(String number) => _t('Receipt $number', 'إيصال رقم $number');

  // ── Receipts ──
  String get noReceipts => _t('No receipts yet', 'مفيش إيصالات لسه');
  String get noReceiptsMsg => _t('Your receipts will show here after you pay.', 'إيصالاتك هتظهر هنا بعد ما تدفع.');
  String get downloadPdf => _t('Open PDF', 'افتح الـ PDF');
  String get resend => _t('Send again', 'ابعت تاني');

  // ── Notifications ──
  String get notifications => _t('Alerts', 'التنبيهات');
  String get noNotifications => _t('No alerts yet', 'مفيش تنبيهات لسه');
  String get noNotificationsMsg => _t('New alerts will show here.', 'أي جديد هيظهرلك هنا.');
  String get markAllRead => _t('Mark all as read', 'خلّي الكل مقروء');

  // ── Suspended / Reinstatement ──
  String get enrollmentPaused => _t('Your spot is on hold', 'مكانك متوقف مؤقتًا');
  String get checkSpotAvailability => _t('Ask for your spot back', 'اطلب مكانك تاني');
  String get requestAvailableSpot => _t('Ask for a spot', 'اطلب مكان');
  String get checkingAvailability => _t('We are checking', 'بنراجع طلبك');
  String get checkingAvailabilityMsg => _t('We got your request and are checking for a free spot in your class. We will tell you the answer.', 'طلبك وصل، وبنشوف لو في مكان فاضي في تمرينك. هنبلّغك بالرد.');
  String get noSpotsAvailable => _t('No free spots', 'مفيش أماكن فاضية');
  String get spotConfirmed => _t('Your spot is ready', 'مكانك جاهز');

  // ── Admin ──
  String get athletes => _t('Swimmers', 'السبّاحين');
  String get payments => _t('Payments', 'المدفوعات');
  String get analytics => _t('Statistics', 'الإحصائيات');
  String get health => _t('Sheet check', 'حالة الشيت');
  String get pricing => _t('Prices', 'الأسعار');
  String get branches => _t('Branches', 'الفروع');
  String get branchAdmins => _t('Admins', 'المسؤولين');
  String get search => _t('Search', 'بحث');
  String get searchAthletes => _t('Search swimmers...', 'دوّر على سبّاح...');
  String get refresh => _t('Refresh', 'تحديث');
  String get totalAthletes => _t('Total swimmers', 'إجمالي السبّاحين');
  String get markAsPaid => _t('Mark as paid', 'سجّل كمدفوع');
  String get alreadyPaid => _t('Already paid', 'مدفوع قبل كده');
  String get provisionAccount => _t('Create account', 'اعمل حساب');
  String get resetPassword => _t('Reset password', 'غيّر كلمة السر');
  String get cash => _t('Cash', 'كاش');
  String get card => _t('Card', 'كارت');
  String get online => _t('Online', 'أونلاين');
  String get paymentMethod => _t('Payment method', 'طريقة الدفع');
  String get selectPaymentMethod => _t('Choose how to pay', 'اختار طريقة الدفع');
  String get cashInBranch => _t('Cash at the branch', 'كاش في الفرع');
  String get cardInBranch => _t('Card at the branch', 'كارت في الفرع');
  String get reinstatementRequests => _t('Spot requests', 'طلبات الرجوع');
  String get approve => _t('Approve', 'موافقة');
  String get decline => _t('Decline', 'رفض');
  String get pending => _t('Waiting', 'في الانتظار');
  String get approved => _t('Approved', 'تمت الموافقة');
  String get declined => _t('Declined', 'مرفوض');
  String get comment => _t('Note', 'ملاحظة');
  String get noData => _t('Nothing to show yet', 'مفيش بيانات لسه');
  String get error => _t('Error', 'خطأ');
  String get retry => _t('Try again', 'جرّب تاني');
  String get loading => _t('Loading...', 'بنحمّل...');
  String get success => _t('Done', 'تمام');

  // ── Coach ──
  String get mySchedule => _t('My classes', 'جدولي');
  String get todaySchedule => _t('Today\'s classes', 'تمارين النهارده');
  String get noClassesToday => _t('No classes today', 'مفيش تمارين النهارده');

  // ── Monthly Reports ──
  String get monthlyReports => _t('Monthly reports', 'التقارير الشهرية');
  String get monthlyReport => _t('Monthly report', 'التقرير الشهري');
  String get reports => _t('Reports', 'التقارير');
  String get writeReport => _t('Write report', 'اكتب تقرير');
  String get editReport => _t('Edit report', 'عدّل التقرير');
  String get saveReport => _t('Save report', 'احفظ التقرير');
  String get reportSaved => _t('Report saved', 'التقرير اتحفظ');
  String get technique => _t('Technique', 'التكنيك');
  String get endurance => _t('Endurance', 'التحمّل');
  String get commitment => _t('Commitment', 'الالتزام');
  String get discipline => _t('Discipline', 'الانضباط');
  String get coachNotes => _t('Coach notes', 'ملاحظات الكابتن');
  String get nextMonthGoals => _t('Goals for next month', 'أهداف الشهر الجاي');
  String get overallRating => _t('Overall', 'التقييم العام');
  String get noReportsYet => _t('No reports yet', 'مفيش تقارير لسه');
  String get noReportsSubtitle => _t('Your coach will send the monthly report here.', 'الكابتن هيبعت التقرير الشهري هنا.');
  String get reportBy => _t('By', 'من');
  String get uploadPdf => _t('Upload PDF', 'ارفع PDF');
  String get writeNote => _t('Write a note', 'اكتب ملاحظة');
  String get choosePdf => _t('Choose a PDF', 'اختار ملف PDF');
  String get changePdf => _t('Change', 'غيّر');
  String get pdfTooLarge => _t('This PDF is bigger than 10 MB', 'الملف أكبر من 10 ميجا');
  String get noteHint => _t('Write the note for the parent', 'اكتب الملاحظة لولي الأمر');
  String get optionalNote => _t('Add a note (optional)', 'ضيف ملاحظة (اختياري)');
  String get sendReport => _t('Send report', 'ابعت التقرير');
  String get replaceReport => _t('Send and replace', 'ابعت وبدّل القديم');
  String get reportSent => _t('Report sent. The parent got an alert.', 'التقرير اتبعت، وولي الأمر وصله تنبيه.');
  String get parentNotified => _t('The parent gets an alert as soon as you send it.', 'ولي الأمر بيوصله تنبيه أول ما تبعت.');
  String get openPdf => _t('Open PDF', 'افتح الـ PDF');
  String get pdfReport => _t('PDF report', 'تقرير PDF');
  String get noteFromCoach => _t('Note from the coach', 'ملاحظة من الكابتن');
  String get alreadySent => _t('Already sent', 'اتبعت قبل كده');
  String get swimmers => _t('Swimmers', 'السبّاحين');
  String get reported => _t('Sent', 'اتبعت');
  String get notReported => _t('Waiting', 'لسه');

  // ── Common ──
  String get ok => _t('OK', 'تمام');
  String get close => _t('Close', 'إغلاق');
  String get yes => _t('Yes', 'أيوه');
  String get no => _t('No', 'لأ');
  String get done => _t('Done', 'تم');
  String get delete => _t('Delete', 'امسح');
  String get edit => _t('Edit', 'تعديل');
  String get add => _t('Add', 'ضيف');
  String get update => _t('Update', 'تحديث');
  String get noInternetConnection => _t('No internet. Check your connection.', 'مفيش إنترنت. راجع الاتصال.');
  String get serverError => _t('Our system is busy. Try again in a little while.', 'في ضغط على السيستم. جرّب تاني بعد شوية.');
  String get somethingWentWrong => _t('That did not work. Try again.', 'حصل مشكلة، جرّب تاني');

  // ── Parent screens: first login, bill, home ──
  // First login
  String get setUpEmailTitle => _t('Add your email', 'ضيف إيميلك');
  String get checkEmailTitle => _t('Check your email', 'تأكيد الإيميل');
  String get choosePasswordTitle => _t('Choose a password', 'اختار كلمة سر');
  String get onboardingEmailIntro => _t(
      'Type your email. We will send you a code to check it is yours.',
      'اكتب إيميلك، وهنبعتلك كود نتأكد بيه إنه بتاعك.');
  String get emailRequired => _t('Type your email', 'اكتب الإيميل');
  String get codeSentToLabel => _t('We sent a 6 digit code to', 'بعتنا كود من 6 أرقام على');
  String resendCodeIn(int seconds) => _t('You can ask for a new code in $seconds seconds', 'تقدر تطلب كود جديد بعد $seconds ثانية');
  String get resendCode => _t('Send a new code', 'ابعت كود جديد');
  String get enterSixDigitCode => _t('Type the 6 digit code', 'اكتب الكود اللي من 6 أرقام');
  String get onboardingPasswordIntro => _t('Choose a password for your account.', 'اختار كلمة سر لحسابك.');
  String get passwordTip => _t(
      'Tip: use 6 or more characters. Mix capital letters, numbers and symbols.',
      'نصيحة: 6 حروف أو أكتر، وخلّي فيها حروف كبيرة وأرقام ورموز.');
  String get checkCode => _t('Check code', 'تأكيد الكود');
  String get finishSetup => _t('Finish', 'خلّصنا');

  // Forgot password
  String get forgotEmailIntro => _t(
      'Type the email on your account. We will send you a code.',
      'اكتب الإيميل المسجّل على حسابك، وهنبعتلك كود.');
  String get enterCodeSentTo => _t('Type the 6 digit code we sent to', 'اكتب الكود اللي بعتناه على');
  String get chooseNewPasswordIntro => _t('Choose your new password.', 'اختار كلمة السر الجديدة.');
  String get passwordResetMsg => _t('You can now log in with your new password.', 'تقدر دلوقتي تدخل بكلمة السر الجديدة.');
  String get backToLogin => _t('Back to log in', 'ارجع لتسجيل الدخول');

  // Paying
  String get paymentUnavailable => _t(
      'Online payment is not working right now. Try again later.',
      'الدفع الأونلاين مش شغّال دلوقتي. جرّب تاني بعد شوية.');
  String get couldNotOpenPayment => _t('Could not open the payment page. Try again.', 'ماعرفناش نفتح صفحة الدفع. جرّب تاني.');
  String paymentError(String message) => _t('The payment did not work: $message', 'الدفع ما تمّش: $message');
  String get paymentDue => _t('Time to pay', 'مطلوب الدفع');
  String get billSoon => _t('Your branch will add the amount soon', 'الفرع هيضيف المبلغ قريب');
  String get payNow => _t('Pay now', 'ادفع دلوقتي');
  String coachNamed(String name) => _t('Coach $name', 'كابتن $name');

  // Receipts
  String get pdfFailed => _t('Could not open the PDF. Try again.', 'ماعرفناش نفتح الـ PDF. جرّب تاني.');
  String get share => _t('Share', 'شارك');
  String get emailMeCopy => _t('Email me a copy', 'ابعتهولي على الإيميل');
  String get sentToEmail => _t('Sent to your email', 'اتبعت على إيميلك');
  String receiptShareText(String number, String amount, String period) => _t(
      'Aquathletic Swimming Academy\nReceipt: $number\nAmount: $amount\nMonth: $period\nPaid',
      'Aquathletic أكاديمية سباحة\nإيصال رقم: $number\nالمبلغ: $amount\nالشهر: $period\nمدفوع');

  // Spot on hold
  String get spotLostExplain => _t(
      'The time to pay for this month is over. Spots are few, and they go to swimmers who paid on time.\n\nYou can ask below if a spot is still free.',
      'ميعاد الدفع للشهر ده خلص. الأماكن محدودة وبتروح للي دفعوا في الميعاد.\n\nتقدر تطلب من تحت نشوفلك لو لسه في مكان فاضي.');
  String get spotConfirmedMsg => _t(
      'Your spot is ready. Pay now to start training again.',
      'مكانك جاهز. ادفع دلوقتي عشان ترجع التمرين.');
  String get noSpotsMsg => _t(
      'Sorry, all spots in your class are taken for this month.',
      'للأسف كل الأماكن في تمرينك اتحجزت الشهر ده.');
  String get askSpotHelp => _t(
      'Send a request and we will check if a spot is still free in your class. We will tell you the answer.',
      'ابعت طلب وهنشوف لو لسه في مكان فاضي في تمرينك، وهنبلّغك بالرد.');

  // Home
  String get classNotSet => _t('No class yet', 'لسه مفيش تمرين');
  String get classNotSetMsg => _t(
      'Your class times will show here when the branch adds them.',
      'مواعيد تمرينك هتظهر هنا أول ما الفرع يضيفها.');
  String yearsOld(String age) => _t('$age years', '$age سنة');
  String bornOn(String date) => _t('Born $date', 'مواليد $date');
  String sessionsOf(int attended, int total) => _t('$attended of $total sessions', '$attended من $total حصة');
  String missedCount(int count) => _t('$count missed', 'غاب $count');
  String get noMisses => _t('None missed', 'ما غابش ولا مرة');
}
