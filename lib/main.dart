import 'package:flutter/widgets.dart';
import 'package:firebase_core/firebase_core.dart';

import 'bio_medica_app.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const BioMedicaApp());
}
