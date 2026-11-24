import 'dart:async';
import 'dart:io';

/// The app's language for text produced outside a widget (errors raised in
/// the network layer). Kept in step with the language switch by main.dart.
class AppLang {
  static bool isArabic = false;
}

/// Every way a request can fail, as the user would describe it.
enum ErrorKind {
  offline, // no internet, connection dropped
  timeout, // the server did not answer in time
  server, // the server broke (5xx) or sent something unreadable
  tooMany, // too many tries, wait a little
  signedOut, // the session ended
  notAllowed, // this account may not do that
  notFound,
  rejected, // the server said no and explained why (wrong code, already paid...)
  unknown,
}

/// One place that turns any thrown thing into words a parent can act on.
/// Raw text such as "SocketException: Failed host lookup" or
/// "type 'Null' is not a subtype of type 'String'" never reaches the screen.
class AppError {
  final ErrorKind kind;

  /// What the server said, when it said something meant for the user.
  final String? detail;

  const AppError(this.kind, [this.detail]);

  static String _t(String en, String ar) => AppLang.isArabic ? ar : en;

  static ErrorKind kindForStatus(int status) {
    if (status == 0) return ErrorKind.offline;
    if (status == 401) return ErrorKind.signedOut;
    if (status == 403 || status == 423) return ErrorKind.notAllowed;
    if (status == 404) return ErrorKind.notFound;
    if (status == 408 || status == 504) return ErrorKind.timeout;
    if (status == 429) return ErrorKind.tooMany;
    if (status >= 500) return ErrorKind.server;
    if (status >= 400) return ErrorKind.rejected;
    return ErrorKind.unknown;
  }

  /// Short heading for a full-screen error.
  String get title => switch (kind) {
        ErrorKind.offline => _t('No internet', 'مفيش إنترنت'),
        ErrorKind.timeout => _t('This is taking too long', 'الموضوع واخد وقت'),
        ErrorKind.server => _t('We have a problem on our side', 'في مشكلة عندنا'),
        ErrorKind.tooMany => _t('Too many tries', 'محاولات كتير'),
        ErrorKind.signedOut => _t('Please log in again', 'سجّل دخولك تاني'),
        ErrorKind.notAllowed => _t('Not allowed', 'مش مسموح'),
        ErrorKind.notFound => _t('Not found', 'مش موجود'),
        ErrorKind.rejected => _t('That did not work', 'الطلب متمّش'),
        ErrorKind.unknown => _t('That did not work', 'حصلت مشكلة'),
      };

  /// What happened and what to do next, in one or two short sentences.
  String get message {
    final said = detail == null ? null : sayServerText(detail!);
    switch (kind) {
      case ErrorKind.offline:
        return _t('Check your internet and try again.', 'اتأكد من النت وجرّب تاني.');
      case ErrorKind.timeout:
        return _t('The connection is slow. Try again in a moment.', 'النت بطيء. جرّب تاني بعد شوية.');
      case ErrorKind.server:
        return _t('It is not your phone. Try again in a few minutes.', 'المشكلة مش من موبايلك. جرّب تاني بعد كام دقيقة.');
      case ErrorKind.tooMany:
        return _t('Wait a few minutes, then try again.', 'استنى كام دقيقة وجرّب تاني.');
      case ErrorKind.signedOut:
        return (said != null && said.isNotEmpty) ? said : _t('Your login ended. Log in again to continue.', 'تسجيل دخولك انتهى. سجّل تاني عشان تكمّل.');
      case ErrorKind.notAllowed:
        return (said != null && said.isNotEmpty) ? said : _t('This account cannot do that.', 'الحساب ده مينفعش يعمل كده.');
      case ErrorKind.notFound:
        return (said != null && said.isNotEmpty) ? said : _t('We could not find that.', 'مش لاقيين ده.');
      case ErrorKind.rejected:
        return (said != null && said.isNotEmpty) ? said : _t('Check what you entered and try again.', 'راجع اللي كتبته وجرّب تاني.');
      case ErrorKind.unknown:
        return _t('Try again. If it keeps happening, close the app and open it again.', 'جرّب تاني. لو فضلت المشكلة، اقفل التطبيق وافتحه تاني.');
    }
  }

  /// Can trying again possibly help?
  bool get canRetry => kind != ErrorKind.notAllowed && kind != ErrorKind.signedOut;

  /// Turn anything thrown into an [AppError]. [ApiException] carries its own
  /// kind; everything else is classified here.
  static AppError from(Object error) {
    if (error is AppError) return error;
    if (error is HasAppError) return error.appError;
    if (error is SocketException || error is HandshakeException || error is HttpException) {
      return const AppError(ErrorKind.offline);
    }
    if (error is TimeoutException) return const AppError(ErrorKind.timeout);
    // Programming and parsing errors: never show their text
    return const AppError(ErrorKind.unknown);
  }

  /// The one sentence to show for [error], wherever it came from.
  static String messageFor(Object error) => from(error).message;
}

/// Implemented by exceptions that already know what kind of failure they are.
abstract class HasAppError {
  AppError get appError;
}

/// Sentences the server sends, in plain English and Egyptian Arabic. The
/// server writes for developers; parents and front desk staff read these.
/// A sentence that is not listed is shown as the server sent it.
const Map<String, (String, String)> _serverSays = {
    'Invalid credentials': ('The login code or password is not correct.', 'الكود أو كلمة السر غلط.'),
    'Incorrect password': ('That password is not correct.', 'كلمة السر غلط.'),
    'Current password is incorrect': ('Your current password is not correct.', 'كلمة السر الحالية غلط.'),
    'That login code or password is not correct': ('The login code or password is not correct.', 'الكود أو كلمة السر غلط.'),
    'Password must be at least 6 characters': ('The password needs at least 6 characters.', 'كلمة السر لازم تكون 6 حروف على الأقل.'),
    'New password must be at least 6 characters': ('The new password needs at least 6 characters.', 'كلمة السر الجديدة لازم تكون 6 حروف على الأقل.'),
    'Invalid verification code': ('That code is not correct. Check it and try again.', 'الكود غلط. راجعه وجرّب تاني.'),
    'Verification code expired': ('That code is too old. Ask for a new one.', 'الكود انتهى. اطلب كود جديد.'),
    'Verification expired. Request a new code.': ('That code is too old. Ask for a new one.', 'الكود انتهى. اطلب كود جديد.'),
    'No pending verification found': ('Ask for a new code first.', 'اطلب كود جديد الأول.'),
    'Too many failed attempts. Request a new code.': ('Too many wrong tries. Ask for a new code.', 'جرّبت كتير غلط. اطلب كود جديد.'),
    'Too many codes requested. Try again in a few minutes.': ('You asked for too many codes. Wait a few minutes.', 'طلبت أكواد كتير. استنى كام دقيقة.'),
    'Too many login attempts. Try again in a few minutes.': ('Too many tries. Wait a few minutes, then try again.', 'محاولات كتير. استنى كام دقيقة وجرّب تاني.'),
    'Too many attempts. Try again later.': ('Too many tries. Wait a few minutes, then try again.', 'محاولات كتير. استنى كام دقيقة وجرّب تاني.'),
    'Email not verified. Complete verification first.': ('Confirm your email with the code first.', 'أكّد الإيميل بالكود الأول.'),
    'Verify this email with the code we send before saving it': ('Confirm the new email with the code we send you.', 'أكّد الإيميل الجديد بالكود اللي هنبعتهولك.'),
    'Invalid email format': ('That email does not look right.', 'الإيميل مكتوب غلط.'),
    'Invalid email address': ('That email does not look right.', 'الإيميل مكتوب غلط.'),
    'Already paid for this period': ('This month is already paid.', 'الشهر ده مدفوع خلاص.'),
    'Payment service unavailable': ('Online payment is not working right now. Try again later.', 'الدفع أونلاين واقف دلوقتي. جرّب بعد شوية.'),
    'Online payment not configured': ('Online payment is not ready yet. Please pay at the front desk.', 'الدفع أونلاين لسه مش جاهز. ادفع في الاستقبال.'),
    'No price set in the pricing list for your program': ('Your class has no price yet. Please ask the front desk.', 'الحصة بتاعتك لسه ملهاش سعر. اسأل الاستقبال.'),
    'No active enrollment': ('This swimmer is not in a class this month.', 'السبّاح ده مش في حصة الشهر ده.'),
    'Account suspended': ('This account is on hold. Check for a free spot from the home screen.', 'الحساب متوقف. شوف لو في مكان فاضي من الصفحة الرئيسية.'),
    'Account disabled': ('This account is closed. Please contact the academy.', 'الحساب مقفول. كلّم الأكاديمية.'),
    'Account inactive': ('This account is not active. Please contact the academy.', 'الحساب مش شغّال. كلّم الأكاديمية.'),
    'Account not found': ('We could not find this account.', 'مش لاقيين الحساب ده.'),
    'Account not found or disabled': ('This account is closed. Please contact the academy.', 'الحساب مقفول. كلّم الأكاديمية.'),
    'Identity mismatch — contact admin': ('The swimmer on this number changed. Please contact the front desk.', 'السبّاح اللي على الرقم ده اتغيّر. كلّم الاستقبال.'),
    'Identity mismatch — the athlete at this number has changed. Contact admin.': ('The swimmer on this number changed. Please contact the front desk.', 'السبّاح اللي على الرقم ده اتغيّر. كلّم الاستقبال.'),
    'This swimmer is already on your account': ('This swimmer is already on your account.', 'السبّاح ده موجود عندك خلاص.'),
    'This swimmer is already set up. Ask the front desk for new login details.': ('This swimmer already has an account. Ask the front desk for new login details.', 'السبّاح ده عنده حساب خلاص. اطلب بيانات دخول جديدة من الاستقبال.'),
    'Finish setting up your own account first': ('Finish setting up your own account first.', 'كمّل إعداد حسابك الأول.'),
    'Swimmer not found on this account': ('This swimmer is not on your account.', 'السبّاح ده مش على حسابك.'),
    'A reinstatement request is already pending': ('The system is already checking. You will get the result soon.', 'السيستم بيشوف دلوقتي. النتيجة هتوصلك قريب.'),
    'This swimmer has no email on their account yet': ('This swimmer has no email yet. The parent adds it the first time they log in.', 'السبّاح ده لسه مالوش إيميل. ولي الأمر بيضيفه أول مرة يدخل.'),
    'Account is not suspended': ('This account is not paused.', 'الحساب مش متوقف.'),
    'Receipt not found': ('We could not find this receipt.', 'مش لاقيين الإيصال ده.'),
    'Report not found': ('We could not find this report.', 'مش لاقيين التقرير ده.'),
    'This report has no PDF': ('This report has no PDF.', 'التقرير ده مفيهوش ملف.'),
    'That file is not a PDF': ('Choose a PDF file.', 'اختار ملف PDF.'),
    'PDF is larger than 10 MB': ('This PDF is too big. The limit is 10 MB.', 'الملف كبير. الحد الأقصى 10 ميجا.'),
    'Note is too long': ('The note is too long.', 'الملاحظة طويلة.'),
    'Write a note or upload a PDF': ('Write a note or add a PDF.', 'اكتب ملاحظة أو ضيف ملف PDF.'),
    'This athlete is not in your sessions': ('This swimmer is not in your classes.', 'السبّاح ده مش في حصصك.'),
    'Access denied to this branch': ('You cannot open this branch.', 'مينفعش تفتح الفرع ده.'),
    'Use profile settings to change your password': ('Change your password from Settings.', 'غيّر كلمة السر من الإعدادات.'),
    'Branch data not available': ('The class list is loading. Try again in a minute.', 'بيانات الحصص بتتحمّل. جرّب بعد دقيقة.'),
};

/// What to show for a sentence from the server, in the app's language.
String sayServerText(String text) {
  final known = _serverSays[text.trim()];
  if (known == null) return text;
  return AppLang.isArabic ? known.$2 : known.$1;
}
