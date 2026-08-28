import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api_service.dart';

/// Handles Firebase Cloud Messaging setup + device token registration.
///
/// Degrades gracefully: if Firebase isn't configured yet (no
/// google-services.json / GoogleService-Info.plist), push is disabled but the
/// in-app notification inbox keeps working.
class NotificationService {
  static bool _firebaseReady = false;
  static bool _initialized = false;
  static String? _currentToken;
  static String _language = 'en';

  static final _localNotifications = FlutterLocalNotificationsPlugin();

  static const _androidChannel = AndroidNotificationChannel(
    'aqua_athletic_default',
    'Aquathletic',
    description: 'Schedule, payment and attendance notifications',
    importance: Importance.high,
  );

  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      await Firebase.initializeApp();
      _firebaseReady = true;
    } catch (e) {
      debugPrint('Firebase not configured — push disabled: $e');
      return;
    }

    try {
      await FirebaseMessaging.instance.requestPermission();

      // Local notifications for foreground display (Android)
      const initSettings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      );
      await _localNotifications.initialize(settings: initSettings);
      await _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_androidChannel);

      // Show pushes that arrive while the app is in the foreground
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        final notification = message.notification;
        if (notification == null) return;
        _localNotifications.show(
          id: notification.hashCode,
          title: notification.title,
          body: notification.body,
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(
              _androidChannel.id,
              _androidChannel.name,
              channelDescription: _androidChannel.description,
              importance: Importance.high,
              priority: Priority.high,
            ),
            iOS: const DarwinNotificationDetails(),
          ),
        );
      });

      FirebaseMessaging.instance.onTokenRefresh.listen((token) {
        _currentToken = token;
        ApiService.registerDevice(token, _platform(), language: _language).catchError((_) {});
      });
    } catch (e) {
      debugPrint('Notification setup error: $e');
    }
  }

  static String _platform() {
    return defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
  }

  static Future<String> _getLanguage() async {
    const storage = FlutterSecureStorage();
    final saved = await storage.read(key: 'app_locale');
    return saved ?? 'en';
  }

  /// Register this device's FCM token with the backend (call after customer login).
  static Future<void> registerToken() async {
    if (!_firebaseReady) return;
    try {
      _language = await _getLanguage();
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        _currentToken = token;
        await ApiService.registerDevice(token, _platform(), language: _language);
      }
    } catch (e) {
      debugPrint('Token registration failed: $e');
    }
  }

  /// Deactivate this device's token on the backend (call before logout).
  static Future<void> unregisterToken() async {
    if (!_firebaseReady || _currentToken == null) return;
    try {
      await ApiService.unregisterDevice(_currentToken!);
    } catch (e) {
      debugPrint('Token unregistration failed: $e');
    }
  }
}
