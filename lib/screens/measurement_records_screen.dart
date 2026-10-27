import 'package:flutter/material.dart';

import '../bio_medica_colors.dart';
import '../data/supabase_measurement_repository.dart';
import '../models/wearable_measurement.dart';

class MeasurementRecordsScreen extends StatefulWidget {
  const MeasurementRecordsScreen({super.key});

  @override
  State<MeasurementRecordsScreen> createState() =>
      _MeasurementRecordsScreenState();
}

class _MeasurementRecordsScreenState extends State<MeasurementRecordsScreen> {
  final _repository = SupabaseMeasurementRepository();
  Stream<List<WearableMeasurement>>? _measurements;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await _repository.initialize();
      if (mounted) {
        setState(() => _measurements = _repository.watchMeasurements());
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No se pudieron consultar las mediciones: $error',
            textAlign: TextAlign.center,
            style: const TextStyle(color: BioMedicaColors.red),
          ),
        ),
      );
    }
    final stream = _measurements;
    if (stream == null) return const Center(child: CircularProgressIndicator());
    return StreamBuilder<List<WearableMeasurement>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'No se pudieron leer las mediciones: ${snapshot.error}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: BioMedicaColors.red),
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final measurements = snapshot.data!;
        if (measurements.isEmpty) {
          return const Center(
            child: Text(
              'No hay mediciones registradas para este acceso.',
              style: TextStyle(color: BioMedicaColors.muted),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: measurements.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) =>
              _measurementTile(measurements[index]),
        );
      },
    );
  }

  Widget _measurementTile(WearableMeasurement measurement) {
    final date = measurement.readingAt.toLocal();
    final timestamp =
        '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/${date.year} '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
    return Card(
      child: ListTile(
        leading: const Icon(
          Icons.favorite_outline_rounded,
          color: BioMedicaColors.primary,
        ),
        title: Text('${measurement.heartRateBpm} BPM · $timestamp'),
        subtitle: Text(
          'Paciente: ${measurement.ownerUid}\n'
          'Dispositivo: ${measurement.deviceName} · Fuente: ${measurement.source}'
          '${measurement.oxygenSaturationPercent == null ? '' : '\nSpO₂: ${measurement.oxygenSaturationPercent}%'}'
          '${measurement.bodyTemperatureCelsius == null ? '' : '\nTemperatura: ${measurement.bodyTemperatureCelsius!.toStringAsFixed(1)} °C'}',
        ),
        isThreeLine: true,
      ),
    );
  }
}
