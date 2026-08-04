import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class LocaleProvider extends ChangeNotifier {
  static const _storage = FlutterSecureStorage();
  Locale _locale = const Locale('en');

  Locale get locale => _locale;
  bool get isArabic => _locale.languageCode == 'ar';

  Future<void> init() async {
    final saved = await _storage.read(key: 'app_locale');
    if (saved != null) {
      _locale = Locale(saved);
      notifyListeners();
    }
  }

  Future<void> setLocale(Locale locale) async {
    _locale = locale;
    await _storage.write(key: 'app_locale', value: locale.languageCode);
    notifyListeners();
  }

  Future<void> toggleLanguage() async {
    final next = isArabic ? const Locale('en') : const Locale('ar');
    await setLocale(next);
  }
}
