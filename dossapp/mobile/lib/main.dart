import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'services/auth_provider.dart';
import 'services/locale_provider.dart';
import 'services/notification_service.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/change_password_screen.dart';
import 'screens/customer/home_screen.dart';
import 'screens/admin/admin_home_screen.dart';
import 'screens/coach/coach_home_screen.dart';
import 'utils/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set status bar style
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
  ));

  await NotificationService.init();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()..init()),
        ChangeNotifierProvider(create: (_) => LocaleProvider()..init()),
      ],
      child: const AquaAthleticApp(),
    ),
  );
}

class AquaAthleticApp extends StatelessWidget {
  const AquaAthleticApp({super.key});

  @override
  Widget build(BuildContext context) {
    final locale = context.watch<LocaleProvider>().locale;

    return MaterialApp(
      title: 'Aqua Athletic',
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
          } else if ((auth.isCustomer || auth.isCoach) && auth.mustChangePassword) {
            screen = const ChangePasswordScreen();
          } else if (auth.isCoach) {
            screen = const CoachHomeScreen();
          } else if (auth.isStaff) {
            screen = const AdminHomeScreen();
          } else {
            screen = const CustomerHomeScreen();
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
