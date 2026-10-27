import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_user_profile.dart';
import 'supabase_config.dart';

abstract interface class AccountRepository {
  Future<AppUserProfile> signIn(String email, String password);

  Future<AppUserProfile?> register({
    required String firstName,
    required String lastName,
    required String email,
    required String password,
    required DateTime dateOfBirth,
    required List<String> chronicConditions,
    String? otherChronicCondition,
  });

  Future<void> requestPasswordReset(String email);

  Future<void> updatePassword(String password);

  Future<AppUserProfile?> restoreSession();

  Future<void> signOut();
}

class AccountRepositoryException implements Exception {
  const AccountRepositoryException(this.message);

  final String message;

  @override
  String toString() => message;
}

class SupabaseAccountRepository implements AccountRepository {
  SupabaseAccountRepository({this.client});

  final SupabaseClient? client;

  SupabaseClient get supabaseClient {
    final injectedClient = client;
    if (injectedClient != null) return injectedClient;
    if (!SupabaseConfig.isConfigured) {
      throw const AccountRepositoryException(
        'Configura SUPABASE_URL y SUPABASE_PUBLISHABLE_KEY para usar BioMedica.',
      );
    }
    return Supabase.instance.client;
  }

  @override
  Future<AppUserProfile> signIn(String email, String password) async {
    try {
      final response = await supabaseClient.auth.signInWithPassword(
        email: email.trim().toLowerCase(),
        password: password,
      );
      final user = response.user;
      if (user == null || user.emailConfirmedAt == null) {
        throw const AccountRepositoryException(
          'Confirma tu correo desde el enlace que te enviamos antes de iniciar sesión.',
        );
      }
      return _loadProfile(user.id, user.email ?? email);
    } on AccountRepositoryException {
      rethrow;
    } on AuthException catch (error) {
      throw AccountRepositoryException(_authMessage(error));
    } on PostgrestException catch (error) {
      throw AccountRepositoryException(_dataMessage(error));
    }
  }

  @override
  Future<AppUserProfile?> register({
    required String firstName,
    required String lastName,
    required String email,
    required String password,
    required DateTime dateOfBirth,
    required List<String> chronicConditions,
    String? otherChronicCondition,
  }) async {
    try {
      final response = await supabaseClient.auth.signUp(
        email: email.trim().toLowerCase(),
        password: password,
        emailRedirectTo: SupabaseConfig.authRedirectUrl,
        data: {
          'first_name': firstName.trim(),
          'last_name': lastName.trim(),
          'date_of_birth': _dateOnly(dateOfBirth),
          'chronic_conditions': chronicConditions,
          'other_chronic_condition': otherChronicCondition?.trim(),
        },
      );
      final user = response.user;
      if (user == null) {
        throw const AccountRepositoryException(
          'No se pudo crear la cuenta. Inténtalo nuevamente.',
        );
      }
      if (response.session == null) return null;
      return _loadProfile(user.id, user.email ?? email);
    } on AccountRepositoryException {
      rethrow;
    } on AuthException catch (error) {
      throw AccountRepositoryException(_authMessage(error));
    } on PostgrestException catch (error) {
      throw AccountRepositoryException(_dataMessage(error));
    }
  }

  @override
  Future<void> requestPasswordReset(String email) async {
    try {
      await supabaseClient.auth.resetPasswordForEmail(
        email.trim().toLowerCase(),
        redirectTo: SupabaseConfig.authRedirectUrl,
      );
    } on AuthException catch (error) {
      throw AccountRepositoryException(_authMessage(error));
    }
  }

  @override
  Future<void> updatePassword(String password) async {
    try {
      await supabaseClient.auth.updateUser(UserAttributes(password: password));
    } on AuthException catch (error) {
      throw AccountRepositoryException(_authMessage(error));
    }
  }

  @override
  Future<AppUserProfile?> restoreSession() async {
    if (client == null && !SupabaseConfig.isConfigured) {
      throw const AccountRepositoryException(
        'Configura SUPABASE_URL y SUPABASE_PUBLISHABLE_KEY para usar BioMedica.',
      );
    }
    final user = supabaseClient.auth.currentUser;
    if (user == null || user.emailConfirmedAt == null) return null;
    return _loadProfile(user.id, user.email ?? '');
  }

  @override
  Future<void> signOut() async {
    try {
      await supabaseClient.auth.signOut();
    } on AuthException catch (error) {
      throw AccountRepositoryException(_authMessage(error));
    }
  }

  Future<AppUserProfile> _loadProfile(String uid, String email) async {
    final data = await supabaseClient
        .from('profiles')
        .select(
          'id, first_name, last_name, date_of_birth, chronic_conditions, '
          'other_chronic_condition, role',
        )
        .eq('id', uid)
        .maybeSingle();
    if (data == null) {
      throw const AccountRepositoryException(
        'El perfil todavía no está disponible. Confirma tu correo y vuelve a iniciar sesión.',
      );
    }
    return AppUserProfile.fromSupabase(uid, email, data);
  }

  String _dateOnly(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  String _authMessage(AuthException error) {
    final message = error.message.toLowerCase();
    if (message.contains('already registered') ||
        message.contains('already been registered') ||
        message.contains('user already exists')) {
      return 'Ya existe una cuenta con ese correo.';
    }
    if (message.contains('invalid login credentials')) {
      return 'Correo o contraseña incorrectos.';
    }
    if (message.contains('email not confirmed')) {
      return 'Confirma tu correo desde el enlace que te enviamos.';
    }
    return error.message;
  }

  String _dataMessage(PostgrestException error) =>
      'No se pudo cargar el perfil de Supabase: ${error.message}';
}
