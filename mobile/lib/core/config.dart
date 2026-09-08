class AppConfig {
  static const url = String.fromEnvironment('SUPABASE_URL');
  static const publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );
  static const turnFunction = String.fromEnvironment(
    'TURN_FUNCTION',
    defaultValue: 'call-ice',
  );
  static const androidBanner = String.fromEnvironment(
    'ADMOB_ANDROID_BANNER_ID',
    defaultValue: 'ca-app-pub-3940256099942544/6300978111',
  );
  static const iosBanner = String.fromEnvironment(
    'ADMOB_IOS_BANNER_ID',
    defaultValue: 'ca-app-pub-3940256099942544/2934735716',
  );
  static bool get configured =>
      Uri.tryParse(url)?.scheme == 'https' &&
      publishableKey.startsWith('sb_publishable_');
}
