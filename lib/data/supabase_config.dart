import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfig {
  const SupabaseConfig._();

  static const url = String.fromEnvironment('SUPABASE_URL');
  static const publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );
  static const authRedirectUrl =
      'com.example.biomedica_app://login-callback/';
  static const emailConfirmationRedirectUrl = String.fromEnvironment(
    'SUPABASE_EMAIL_CONFIRMATION_REDIRECT_URL',
    defaultValue: 'https://app-biomedica-web.onrender.com/auth/confirmed',
  );

  static bool get isConfigured => url.isNotEmpty && publishableKey.isNotEmpty;

  static Future<void> initialize() async {
    if (!isConfigured) return;
    await Supabase.initialize(
      url: url,
      publishableKey: publishableKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    );
  }
}
