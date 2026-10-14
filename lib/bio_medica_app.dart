import 'package:flutter/material.dart';

import 'bio_medica_colors.dart';
import 'screens/patient_shell.dart';
import 'screens/sign_in_screen.dart';

class BioMedicaApp extends StatefulWidget {
  const BioMedicaApp({super.key});

  @override
  State<BioMedicaApp> createState() => _BioMedicaAppState();
}

class _BioMedicaAppState extends State<BioMedicaApp> {
  String? _patientName;
  String? _patientEmail;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'BioMedica | Paciente',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: BioMedicaColors.primary,
        primary: BioMedicaColors.primary,
        surface: BioMedicaColors.surface,
      ),
      scaffoldBackgroundColor: BioMedicaColors.canvas,
    ),
    home: _patientName == null
        ? SignInScreen(
            onContinue: (name, email) => setState(() {
              _patientName = name;
              _patientEmail = email;
            }),
          )
        : PatientShell(
            patientName: _patientName!,
            patientEmail: _patientEmail!,
            onSignOut: () => setState(() {
              _patientName = null;
              _patientEmail = null;
            }),
          ),
  );
}
