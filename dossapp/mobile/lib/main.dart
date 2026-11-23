import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'utils/app_error.dart';
import 'widgets/error_views.dart';
import 'services/auth_provider.dart';
import 'services/locale_provider.dart';
import 'services/notification_service.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/change_password_screen.dart';
import 'screens/auth/onboarding_screen.dart';
import 'screens/auth/profile_picker_screen.dart';
import 'screens/customer/home_screen.dart';
import 'screens/admin/admin_home_screen.dart';
import 'screens/coach/coach_home_screen.dart';
import 'utils/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait only
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Set status bar style
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
  ));

  // Arabic month and day names for dates shown in the app
  await initializeDateFormatting('ar');

  await NotificationService.init();

  // Firebase Crashlytics — catch Flutter errors + async errors
  // (Crashlytics has no web implementation; web is only used for local previews.)
  if (!kIsWeb) {
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  }

  // One broken card shows a small note instead of a grey or red screen
  installFriendlyErrorWidget();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()..init()),
        ChangeNotifierProvider(create: (_) => LocaleProvider()..init()),
      ],
      child: const AquathleticApp(),
    ),
  );
}

class AquathleticApp extends StatelessWidget {
  const AquathleticApp({super.key});

  @override
  Widget build(BuildContext context) {
    final locale = context.watch<LocaleProvider>().locale;
    // Dates and money are formatted outside the widget tree (utils/formatters),
    // so they follow this instead of a BuildContext. 'ar' keeps Western digits.
    Intl.defaultLocale = locale.languageCode;

    // Errors raised outside widgets (the network layer) use this language
    AppLang.isArabic = locale.languageCode == 'ar';
    return MaterialApp(
      // A strip across the top of every screen while the phone is offline
      builder: (context, child) => OfflineBanner(child: child ?? const SizedBox.shrink()),
      title: 'Aquathletic',
      debugShowCheckedModeBanner: false,
      theme: appTheme(),
      locale: locale,
      supportedLocales: const [
        Locale('en'),
        Locale('ar'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Consumer<AuthProvider>(
        builder: (context, auth, _) {
          final Widget screen;
          if (!auth.isLoggedIn) {
            screen = const LoginScreen();
          } else if (auth.isCustomer && auth.mustChangePassword) {
            screen = const OnboardingScreen();
          } else if (auth.isCoach && auth.mustChangePassword) {
            screen = const ChangePasswordScreen();
          } else if (auth.isCoach) {
            screen = const CoachHomeScreen();
          } else if (auth.isStaff) {
            screen = const AdminHomeScreen();
          } else if (auth.needsProfileChoice) {
            screen = const ProfilePickerScreen();
          } else {
            // Keyed by swimmer: switching rebuilds home from scratch, so no
            // data of the previous child is ever left on screen.
            screen = CustomerHomeScreen(key: ValueKey('home-${auth.sessionKey}'));
          }

          return AnimatedSwitcher(
            duration: AppAnimation.slowDuration,
            switchInCurve: AppAnimation.enterCurve,
            switchOutCurve: AppAnimation.exitCurve,
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.03),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              );
            },
            child: KeyedSubtree(
              key: ValueKey(screen.runtimeType.toString() + auth.role),
              child: screen,
            ),
          );
        },
      ),
    );
  }
}
