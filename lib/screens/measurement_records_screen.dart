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
  Widget build(BuildContext context) => _content();

  Widget _content() {
    final error = _error;
    if (error != null) {
      return _scrollState(
        Text(
          'No se pudieron consultar las mediciones: $error',
          textAlign: TextAlign.center,
          style: const TextStyle(color: BioMedicaColors.red),
        ),
      );
    }
    final stream = _measurements;
    if (stream == null) {
      return _scrollState(const CircularProgressIndicator());
    }
    return StreamBuilder<List<WearableMeasurement>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _scrollState(
            Text(
              'No se pudieron leer las mediciones: ${snapshot.error}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: BioMedicaColors.red),
            ),
          );
        }
        if (!snapshot.hasData) {
          return _scrollState(const CircularProgressIndicator());
        }
        final measurements = snapshot.data!;
        if (measurements.isEmpty) {
          return _scrollState(
            const Text(
              'No hay mediciones registradas para este acceso.',
              style: TextStyle(color: BioMedicaColors.muted),
            ),
          );
        }
        return ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          itemCount: measurements.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) =>
              _measurementTile(measurements[index]),
        );
      },
    );
  }

  Widget _scrollState(Widget child) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: constraints.maxHeight),
        child: Center(
          child: Padding(padding: const EdgeInsets.all(24), child: child),
        ),
      ),
    ),
  );

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
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Paciente: ${measurement.ownerUid}\n'
              'Dispositivo: ${measurement.deviceName} · Fuente: ${measurement.source}'
              '${measurement.oxygenSaturationPercent == null ? '' : '\nSpO₂: ${measurement.oxygenSaturationPercent}%'}'
              '${measurement.bodyTemperatureCelsius == null ? '' : '\nTemperatura: ${measurement.bodyTemperatureCelsius!.toStringAsFixed(1)} °C'}',
            ),
            for (final entry in measurement.sensorReadings.entries)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  '${entry.value.label}: '
                  '${_formatSensorValues(entry.value.values)} ${entry.value.unit}'
                  '${entry.value.observedAt == null ? '' : ' · ${_formatReadingTime(entry.value.observedAt!)}'}',
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatSensorValues(List<double> values) => values
      .map(
        (value) => value == value.roundToDouble()
            ? value.round().toString()
            : value.toStringAsFixed(2),
      )
      .join(' · ');

  String _formatReadingTime(DateTime time) {
    final local = time.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}
