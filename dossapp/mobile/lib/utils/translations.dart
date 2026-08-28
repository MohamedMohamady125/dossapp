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

  /// Use this when you don't have a context (e.g., in initState)
  static S fromLocale(Locale locale) => S._(locale.languageCode);

  String _t(String en, String ar) => _lang == 'ar' ? ar : en;

  // ── App ──
  String get appName => 'Aquathletic';
  String get swimmingAcademy => _t('Swimming Academy', 'أكاديمية السباحة');

  // ── Auth ──
  String get login => _t('Log In', 'تسجيل الدخول');
  String get logout => _t('Log Out', 'تسجيل الخروج');
  String get logoutConfirm => _t('Are you sure you want to log out?', 'هل أنت متأكد من تسجيل الخروج؟');
  String get parentAthlete => _t('Parent / Athlete', 'ولي أمر / سباح');
  String get staff => _t('Staff', 'الموظفين');
  String get loginCode => _t('Login Code', 'رمز الدخول');
  String get username => _t('Username', 'اسم المستخدم');
  String get password => _t('Password', 'كلمة المرور');
  String get forgotPassword => _t('Forgot Password?', 'نسيت كلمة المرور؟');
  String get forgotPasswordTitle => _t('Forgot Password', 'نسيت كلمة المرور');
  String get forgotPasswordBody => _t(
    'Please contact your branch administrator to reset your password.',
    'يرجى التواصل مع إدارة الفرع لإعادة تعيين كلمة المرور.',
  );
  String get contactBranch => _t('Contact Branch', 'تواصل مع الفرع');
  String get required => _t('Required', 'مطلوب');
  String get invalidCredentials => _t('Invalid credentials', 'بيانات غير صحيحة');
  String get tooManyAttempts => _t('Too many attempts. Try again later.', 'محاولات كثيرة. حاول مرة أخرى لاحقاً.');

  // ── Change Password ──
  String get changePassword => _t('Change Password', 'تغيير كلمة المرور');
  String get currentPassword => _t('Current Password', 'كلمة المرور الحالية');
  String get newPassword => _t('New Password', 'كلمة المرور الجديدة');
  String get confirmPassword => _t('Confirm Password', 'تأكيد كلمة المرور');
  String get passwordChanged => _t('Password changed successfully', 'تم تغيير كلمة المرور بنجاح');
  String get passwordTooShort => _t('Password must be at least 6 characters', 'كلمة المرور يجب أن تكون 6 أحرف على الأقل');
  String get passwordsMustMatch => _t('Passwords must match', 'كلمات المرور يجب أن تتطابق');
  String get createNewPassword => _t('Create a new password for your account', 'أنشئ كلمة مرور جديدة لحسابك');
  String get passwordStrength => _t('Password Strength', 'قوة كلمة المرور');
  String get weak => _t('Weak', 'ضعيفة');
  String get fair => _t('Fair', 'مقبولة');
  String get good => _t('Good', 'جيدة');
  String get strong => _t('Strong', 'قوية');
  String get veryStrong => _t('Very Strong', 'قوية جداً');
  String get setPassword => _t('Set Password', 'تعيين كلمة المرور');

  // ── Settings ──
  String get settings => _t('Settings', 'الإعدادات');
  String get profile => _t('Profile', 'الملف الشخصي');
  String get language => _t('Language', 'اللغة');
  String get english => _t('English', 'الإنجليزية');
  String get arabic => _t('Arabic', 'العربية');
  String get changeEmail => _t('Change Email', 'تغيير البريد الإلكتروني');
  String get email => _t('Email', 'البريد الإلكتروني');
  String get newEmail => _t('New Email', 'البريد الإلكتروني الجديد');
  String get emailUpdated => _t('Email updated successfully', 'تم تحديث البريد الإلكتروني بنجاح');
  String get invalidEmail => _t('Please enter a valid email', 'يرجى إدخال بريد إلكتروني صحيح');
  String get save => _t('Save', 'حفظ');
  String get cancel => _t('Cancel', 'إلغاء');
  String get confirm => _t('Confirm', 'تأكيد');
  String get appVersion => _t('App Version', 'إصدار التطبيق');
  String get account => _t('Account', 'الحساب');
  String get general => _t('General', 'عام');
  String get deleteAccount => _t('Delete Account', 'حذف الحساب');
  String get deleteAccountConfirm => _t(
    'This will permanently delete your account and all associated data. This action cannot be undone.',
    'سيتم حذف حسابك وجميع البيانات المرتبطة بشكل نهائي. لا يمكن التراجع عن هذا الإجراء.',
  );
  String get deleteAccountSuccess => _t('Account deleted successfully', 'تم حذف الحساب بنجاح');
  String get enterPasswordToConfirm => _t('Enter your password to confirm', 'أدخل كلمة المرور للتأكيد');
  String get privacyPolicy => _t('Privacy Policy', 'سياسة الخصوصية');
  String get about => _t('About', 'حول');

  // ── Customer Home ──
  String get home => _t('Home', 'الرئيسية');
  String get pay => _t('Pay', 'الدفع');
  String get receipts => _t('Receipts', 'الإيصالات');
  String get alerts => _t('Alerts', 'التنبيهات');
  String get welcome => _t('Welcome', 'مرحباً');
  String get myProfile => _t('My Profile', 'ملفي الشخصي');
  String get athleteNumber => _t('Athlete Number', 'رقم السباح');
  String get branch => _t('Branch', 'الفرع');
  String get practiceSchedule => _t('Practice Schedule', 'جدول التدريب');
  String get practiceTimes => _t('Practice Times', 'أوقات التدريب');
  String get attendance => _t('Attendance', 'الحضور');
  String get present => _t('Present', 'حاضر');
  String get absent => _t('Absent', 'غائب');
  String get paymentStatus => _t('Payment Status', 'حالة الدفع');
  String get athleteDetails => _t('Athlete Details', 'بيانات السباح');
  String get enrollment => _t('Enrollment', 'التسجيل');
  String get classInfo => _t('Class Info', 'معلومات الفصل');
  String get type => _t('Type', 'النوع');
  String get level => _t('Level', 'المستوى');
  String get days => _t('Days', 'الأيام');
  String get sessions => _t('Sessions', 'الحصص');
  String get coach => _t('Coach', 'المدرب');
  String get age => _t('Age', 'العمر');
  String get gender => _t('Gender', 'الجنس');
  String get male => _t('Male', 'ذكر');
  String get female => _t('Female', 'أنثى');
  String get dateOfBirth => _t('Date of Birth', 'تاريخ الميلاد');
  String get phone => _t('Phone', 'الهاتف');

  // ── Bill ──
  String get myBill => _t('My Bill', 'فاتورتي');
  String get amountDue => _t('Amount Due', 'المبلغ المستحق');
  String get paid => _t('PAID', 'مدفوعة');
  String get unpaid => _t('Unpaid', 'غير مدفوعة');
  String get serviceDetails => _t('Service Details', 'تفاصيل الخدمة');
  String get swimmingLessonsAt => _t('In-person swimming lessons at', 'دروس سباحة حضورية في');
  String get billPending => _t('Bill Pending', 'الفاتورة قيد المعالجة');
  String get billPendingMsg => _t(
    'Your bill amount has not been set yet.\nYou will be notified when it is ready.',
    'لم يتم تحديد مبلغ الفاتورة بعد.\nسيتم إخطارك عندما تكون جاهزة.',
  );
  String get enrollmentWindowClosed => _t('Enrollment Window Closed', 'نافذة التسجيل مغلقة');
  String get enrollmentWindowClosedMsg => _t(
    'The payment window for this period has closed.\nGo to the Home tab to check if a spot is\nstill available in your class.',
    'نافذة الدفع لهذه الفترة قد أُغلقت.\nانتقل إلى الرئيسية للتحقق من\nتوفر مكان في فصلك.',
  );
  String get noActiveEnrollment => _t('No Active Enrollment', 'لا يوجد تسجيل نشط');
  String get noActiveEnrollmentMsg => _t(
    'You are not enrolled for the current period.\nContact your branch for more information.',
    'أنت غير مسجل للفترة الحالية.\nتواصل مع فرعك لمزيد من المعلومات.',
  );
  String get processing => _t('Processing...', 'جاري المعالجة...');
  String payAmount(String amount) => _t('Pay $amount', 'ادفع $amount');
  String receiptLabel(String number) => _t('Receipt: $number', 'إيصال: $number');

  // ── Receipts ──
  String get noReceipts => _t('No Receipts', 'لا توجد إيصالات');
  String get noReceiptsMsg => _t('Your payment receipts will appear here.', 'ستظهر إيصالات الدفع الخاصة بك هنا.');
  String get downloadPdf => _t('Download PDF', 'تحميل PDF');
  String get resend => _t('Resend', 'إعادة إرسال');

  // ── Notifications ──
  String get notifications => _t('Notifications', 'الإشعارات');
  String get noNotifications => _t('No Notifications', 'لا توجد إشعارات');
  String get noNotificationsMsg => _t('You\'re all caught up!', 'أنت على اطلاع بكل شيء!');
  String get markAllRead => _t('Mark all as read', 'تحديد الكل كمقروء');

  // ── Suspended / Reinstatement ──
  String get enrollmentPaused => _t('Enrollment Paused', 'التسجيل متوقف');
  String get checkSpotAvailability => _t('Check Spot Availability', 'التحقق من توفر مكان');
  String get requestAvailableSpot => _t('Request Available Spot', 'طلب مكان متاح');
  String get checkingAvailability => _t('Checking Availability', 'جاري التحقق من التوفر');
  String get checkingAvailabilityMsg => _t(
    'The system is checking for available spots in your class. You will be notified once a decision is made.',
    'النظام يتحقق من الأماكن المتاحة في فصلك. سيتم إخطارك عند اتخاذ قرار.',
  );
  String get noSpotsAvailable => _t('No Spots Available', 'لا توجد أماكن متاحة');
  String get spotConfirmed => _t('Spot Confirmed', 'تم تأكيد المكان');

  // ── Admin ──
  String get athletes => _t('Athletes', 'السباحين');
  String get payments => _t('Payments', 'المدفوعات');
  String get analytics => _t('Analytics', 'التحليلات');
  String get health => _t('Health', 'الصحة');
  String get pricing => _t('Pricing', 'الأسعار');
  String get branches => _t('Branches', 'الفروع');
  String get branchAdmins => _t('Admins', 'المسؤولون');
  String get search => _t('Search', 'بحث');
  String get searchAthletes => _t('Search athletes...', 'البحث عن سباح...');
  String get refresh => _t('Refresh', 'تحديث');
  String get totalAthletes => _t('Total Athletes', 'إجمالي السباحين');
  String get markAsPaid => _t('Mark as Paid', 'تحديد كمدفوع');
  String get alreadyPaid => _t('Already Paid', 'تم الدفع');
  String get provisionAccount => _t('Create Account', 'إنشاء حساب');
  String get resetPassword => _t('Reset Password', 'إعادة تعيين كلمة المرور');
  String get cash => _t('Cash', 'نقدي');
  String get card => _t('Card', 'بطاقة');
  String get online => _t('Online', 'أونلاين');
  String get paymentMethod => _t('Payment Method', 'طريقة الدفع');
  String get selectPaymentMethod => _t('Select Payment Method', 'اختر طريقة الدفع');
  String get cashInBranch => _t('Cash in Branch', 'نقدي في الفرع');
  String get cardInBranch => _t('Card in Branch', 'بطاقة في الفرع');
  String get reinstatementRequests => _t('Reinstatement Requests', 'طلبات إعادة التسجيل');
  String get approve => _t('Approve', 'قبول');
  String get decline => _t('Decline', 'رفض');
  String get pending => _t('Pending', 'قيد الانتظار');
  String get approved => _t('Approved', 'مقبول');
  String get declined => _t('Declined', 'مرفوض');
  String get comment => _t('Comment', 'ملاحظة');
  String get noData => _t('No data available', 'لا توجد بيانات');
  String get error => _t('Error', 'خطأ');
  String get retry => _t('Retry', 'إعادة المحاولة');
  String get loading => _t('Loading...', 'جاري التحميل...');
  String get success => _t('Success', 'نجاح');

  // ── Coach ──
  String get mySchedule => _t('My Schedule', 'جدولي');
  String get todaySchedule => _t("Today's Schedule", 'جدول اليوم');
  String get noClassesToday => _t('No classes today', 'لا توجد حصص اليوم');

  // ── Common ──
  String get ok => _t('OK', 'حسناً');
  String get close => _t('Close', 'إغلاق');
  String get yes => _t('Yes', 'نعم');
  String get no => _t('No', 'لا');
  String get done => _t('Done', 'تم');
  String get delete => _t('Delete', 'حذف');
  String get edit => _t('Edit', 'تعديل');
  String get add => _t('Add', 'إضافة');
  String get update => _t('Update', 'تحديث');
  String get noInternetConnection => _t('No internet connection', 'لا يوجد اتصال بالإنترنت');
  String get serverError => _t('Server error. Please try again later.', 'خطأ في الخادم. يرجى المحاولة لاحقاً.');
  String get somethingWentWrong => _t('Something went wrong', 'حدث خطأ ما');
}
