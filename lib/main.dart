import 'package:flutter/widgets.dart';

import 'bio_medica_app.dart';
import 'data/supabase_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseConfig.initialize();
  runApp(const BioMedicaApp());
}
