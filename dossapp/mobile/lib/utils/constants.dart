class AppConstants {
  // Override for local previews: --dart-define=API_BASE_URL=http://localhost:8765
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://dossapp-production.up.railway.app',
  );

  static const String appName = 'Aquathletic';
  static const String currency = 'EGP';
}
