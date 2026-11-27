import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'bio_medica_app.dart';
import 'data/supabase_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  await SupabaseConfig.initialize();
  runApp(const BioMedicaApp());
}
