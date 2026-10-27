import 'package:biomedica_app/data/account_repository.dart';
import 'package:biomedica_app/data/admin_user_repository.dart';
import 'package:biomedica_app/data/reminder_repository.dart';
import 'package:biomedica_app/data/supabase_measurement_repository.dart';
import 'package:biomedica_app/data/supabase_report_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test(
    'repositories accept an injected client without compile-time config',
    () {
      final client = SupabaseClient('http://localhost:54321', 'test-key');
      addTearDown(client.dispose);

      expect(
        SupabaseAccountRepository(client: client).supabaseClient,
        same(client),
      );
      expect(
        SupabaseReminderRepository(client: client).supabaseClient,
        same(client),
      );
      expect(AdminUserRepository(client: client).supabaseClient, same(client));
      expect(
        SupabaseMeasurementRepository(client: client).supabaseClient,
        same(client),
      );
      expect(
        SupabaseReportRepository(client: client).supabaseClient,
        same(client),
      );
    },
  );

  test('account repository can restore an empty injected session', () async {
    final client = SupabaseClient('http://localhost:54321', 'test-key');
    addTearDown(client.dispose);

    expect(
      await SupabaseAccountRepository(client: client).restoreSession(),
      isNull,
    );
  });
}
