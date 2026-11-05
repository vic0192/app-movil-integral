import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfig {
  const SupabaseConfig._();

  static const _compiledUrl = String.fromEnvironment('SUPABASE_URL');
  static const _compiledPublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );
  static String _url = _compiledUrl;
  static String _publishableKey = _compiledPublishableKey;

  static String get url => _url;
  static String get publishableKey => _publishableKey;
  static const authRedirectUrl = 'com.example.biomedica_app://login-callback/';
  static const emailConfirmationRedirectUrl = String.fromEnvironment(
    'SUPABASE_EMAIL_CONFIRMATION_REDIRECT_URL',
    defaultValue: 'https://app-biomedica-web.onrender.com/auth/confirmed',
  );

  static bool get isConfigured => url.isNotEmpty && publishableKey.isNotEmpty;

  static Future<void> initialize() async {
    if (kIsWeb) await _loadWebConfig();
    if (!isConfigured) return;
    await Supabase.initialize(
      url: url,
      publishableKey: publishableKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    );
  }

  static Future<void> _loadWebConfig() async {
    final response = await http
        .get(Uri.base.resolve('/config.json'))
        .timeout(const Duration(seconds: 10));
    if (response.statusCode == 404 &&
        _compiledUrl.isNotEmpty &&
        _compiledPublishableKey.isNotEmpty) {
      return;
    }
    if (response.statusCode != 200) {
      throw StateError(
        'No se pudo cargar la configuración de BioMedica para web '
        '(HTTP ${response.statusCode}).',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map ||
        decoded['supabaseUrl'] is! String ||
        decoded['supabasePublishableKey'] is! String ||
        (decoded['supabaseUrl'] as String).isEmpty ||
        (decoded['supabasePublishableKey'] as String).isEmpty) {
      throw const FormatException(
        'El servidor devolvió una configuración web de BioMedica inválida.',
      );
    }
    _url = decoded['supabaseUrl'] as String;
    _publishableKey = decoded['supabasePublishableKey'] as String;
  }
}
