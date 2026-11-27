enum HeartRateBand { unavailable, belowReference, reference, aboveReference }

class HeartRateInterpretation {
  const HeartRateInterpretation({
    required this.band,
    required this.label,
    required this.message,
  });

  final HeartRateBand band;
  final String label;
  final String message;

  factory HeartRateInterpretation.fromBpm(int? bpm) {
    if (bpm == null) {
      return const HeartRateInterpretation(
        band: HeartRateBand.unavailable,
        label: 'Sin mediciones recientes',
        message:
            'Toma una medición en el reloj. BioMedica la guardará e interpretará automáticamente.',
      );
    }
    if (bpm < 60) {
      return const HeartRateInterpretation(
        band: HeartRateBand.belowReference,
        label: 'Por debajo del rango orientativo',
        message:
            'En adultos en reposo suele usarse 60–100 BPM como referencia. El resultado puede variar según la persona y el contexto.',
      );
    }
    if (bpm > 100) {
      return const HeartRateInterpretation(
        band: HeartRateBand.aboveReference,
        label: 'Por encima del rango orientativo',
        message:
            'En adultos en reposo suele usarse 60–100 BPM como referencia. Si estabas en reposo, repite la medición y consulta a un profesional si persiste.',
      );
    }
    return const HeartRateInterpretation(
      band: HeartRateBand.reference,
      label: 'Dentro del rango orientativo',
      message:
          'El pulso está entre 60 y 100 BPM, referencia habitual para adultos en reposo.',
    );
  }
}
