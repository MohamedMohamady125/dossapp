import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/auth_provider.dart';
import 'services/notification_service.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/change_password_screen.dart';
import 'screens/customer/home_screen.dart';
import 'screens/admin/admin_home_screen.dart';
import 'screens/coach/coach_home_screen.dart';
import 'utils/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.init();
  runApp(
    ChangeNotifierProvider(
      create: (_) => AuthProvider()..init(),
      child: const AquaAthleticApp(),
    ),
  );
}

class AquaAthleticApp extends StatelessWidget {
  const AquaAthleticApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aqua Athletic',
      debugShowCheckedModeBanner: false,
      theme: appTheme(),
      home: Consumer<AuthProvider>(
        builder: (context, auth, _) {
          if (!auth.isLoggedIn) return const LoginScreen();
          if ((auth.isCustomer || auth.isCoach) && auth.mustChangePassword) {
            return const ChangePasswordScreen();
          }
          if (auth.isCoach) return const CoachHomeScreen();
          if (auth.isStaff) return const AdminHomeScreen();
          return const CustomerHomeScreen();
        },
      ),
    );
  }
}
