import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../bio_medica_colors.dart';
import '../data/health_connect_repository.dart';
import '../models/health_connect_record.dart';
import '../services/health_connect_service.dart';
import '../screens/health_connect_screen.dart';

class HealthConnectMetricSummary {
  const HealthConnectMetricSummary({
    required this.latest,
    required this.history,
  });

  final HealthConnectRecord latest;
  final List<HealthConnectRecord> history;
}

List<HealthConnectMetricSummary> summarizeHealthConnectRecords(
  List<HealthConnectRecord> records, {
  int historyLimit = 12,
}) {
  final newestFirst = List<HealthConnectRecord>.of(records)
    ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
  final byType = <String, List<HealthConnectRecord>>{};
  for (final record in newestFirst) {
    byType.putIfAbsent(record.dataType, () => []).add(record);
  }

  final summaries =
      byType.values.map((typeRecords) {
          final recent = typeRecords.take(historyLimit).toList(growable: false);
          return HealthConnectMetricSummary(
            latest: typeRecords.first,
            history: recent.reversed.toList(growable: false),
          );
        }).toList()
        ..sort((a, b) => b.latest.recordedAt.compareTo(a.latest.recordedAt));
  return summaries;
}

class HealthConnectHomeSummary extends StatefulWidget {
  const HealthConnectHomeSummary({
    super.key,
    this.repository,
    this.healthService,
    this.enableAutomaticSync = true,
    this.onRecordsLoaded,
  });

  final HealthConnectRepository? repository;
  final HealthConnectService? healthService;
  final bool enableAutomaticSync;
  final ValueChanged<List<HealthConnectRecord>>? onRecordsLoaded;

  @override
  State<HealthConnectHomeSummary> createState() =>
      _HealthConnectHomeSummaryState();
}

class _HealthConnectHomeSummaryState extends State<HealthConnectHomeSummary>
    with WidgetsBindingObserver {
  late final HealthConnectRepository _repository =
      widget.repository ?? HealthConnectRepository();
  late final HealthConnectService _healthService =
      widget.healthService ?? HealthConnectService();
  List<HealthConnectMetricSummary> _summaries = const [];
  bool _loading = true;
  bool _loadingRecords = false;
  DateTime? _lastAutomaticSyncAt;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadRecords(syncAutomatically: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadRecords(syncAutomatically: true);
    }
  }

  Future<void> _loadRecords({bool syncAutomatically = false}) async {
    if (_loadingRecords) return;
    _loadingRecords = true;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _repository.initialize();
      String? syncError;
      if (syncAutomatically && _canAutomaticallySync) {
        try {
          final result = await _healthService.readRecentData(
            requestMissingPermissions: false,
          );
          if (result.records.isNotEmpty) {
            await _repository.saveRecords(result.records);
          }
          _lastAutomaticSyncAt = DateTime.now();
        } catch (error) {
          syncError = 'No se pudieron sincronizar datos nuevos: $error';
        }
      }
      final records = await _repository.loadRecentRecords();
      if (!mounted) return;
      setState(() {
        _summaries = summarizeHealthConnectRecords(records);
        _error = syncError;
        _loading = false;
      });
      widget.onRecordsLoaded?.call(records);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudieron cargar las lecturas sincronizadas: $error';
        _loading = false;
      });
    } finally {
      _loadingRecords = false;
    }
  }

  bool get _canAutomaticallySync {
    if (!widget.enableAutomaticSync ||
        kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    final lastSync = _lastAutomaticSyncAt;
    return lastSync == null ||
        DateTime.now().difference(lastSync) >= const Duration(minutes: 15);
  }

  Future<void> _openHealthConnect() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const HealthConnectScreen()),
    );
    if (mounted) await _loadRecords();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Datos recientes de Health Connect',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 3),
                Text(
                  'Métricas disponibles con fuente y hora',
                  style: TextStyle(color: BioMedicaColors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: _openHealthConnect,
            icon: const Icon(Icons.sync_rounded, size: 18),
            label: const Text('Ver y sincronizar'),
          ),
        ],
      ),
      const SizedBox(height: 10),
      if (_loading)
        const Center(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: CircularProgressIndicator(),
          ),
        )
      else if (_summaries.isEmpty && _error == null)
        const Card(
          color: BioMedicaColors.surface,
          child: Padding(
            padding: EdgeInsets.all(14),
            child: Text(
              'Todavía no hay lecturas sincronizadas. Abre Health Connect y '
              'pulsa “Sincronizar ahora” para importar los datos compartidos.',
              style: TextStyle(color: BioMedicaColors.muted, fontSize: 13),
            ),
          ),
        )
      else if (_summaries.isEmpty)
        Card(
          color: BioMedicaColors.surface,
          child: ListTile(
            title: Text(
              _error!,
              style: const TextStyle(color: BioMedicaColors.red, fontSize: 13),
            ),
            trailing: IconButton(
              tooltip: 'Reintentar',
              onPressed: _loadRecords,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ),
        )
      else
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error case final error?)
              Card(
                color: BioMedicaColors.surface,
                child: ListTile(
                  title: Text(
                    error,
                    style: const TextStyle(
                      color: BioMedicaColors.red,
                      fontSize: 13,
                    ),
                  ),
                  trailing: IconButton(
                    tooltip: 'Reintentar sincronización',
                    onPressed: _loadRecords,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ),
              ),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 440 ? 2 : 1;
                const spacing = 10.0;
                final cardWidth =
                    (constraints.maxWidth - spacing * (columns - 1)) / columns;
                return Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: [
                    for (final summary in _summaries)
                      SizedBox(width: cardWidth, child: _metricCard(summary)),
                  ],
                );
              },
            ),
          ],
        ),
    ],
  );

  Widget _metricCard(HealthConnectMetricSummary summary) {
    final latest = summary.latest;
    final source = latest.sourceName.isEmpty
        ? 'Fuente no identificada'
        : latest.sourceName;
    final accent = _metricColor(latest.dataType);
    final tint = Color.lerp(accent, Colors.white, 0.9)!;
    return Card(
      color: BioMedicaColors.surface,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Color.lerp(accent, Colors.white, 0.68)!),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.78, end: 1),
                  duration: const Duration(milliseconds: 450),
                  curve: Curves.easeOutBack,
                  builder: (context, scale, child) =>
                      Transform.scale(scale: scale, child: child),
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: tint,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      _metricIcon(latest.dataType),
                      color: accent,
                      size: 22,
                    ),
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    latest.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: BioMedicaColors.ink,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Icon(Icons.verified_rounded, color: accent, size: 17),
              ],
            ),
            const SizedBox(height: 12),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.12),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: Text(
                key: ValueKey(
                  '${latest.dataType}:${latest.value}:${latest.recordedAt}',
                ),
                latest.displayValue,
                style: TextStyle(
                  color: accent,
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${_formatDate(latest.recordedAt)} · $source',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: BioMedicaColors.muted,
                fontSize: 10,
              ),
            ),
            const SizedBox(height: 8),
            Semantics(
              label:
                  'Tendencia de ${latest.label}, '
                  '${summary.history.length} lecturas',
              child: ExcludeSemantics(
                child: SizedBox(
                  height: 42,
                  child: CustomPaint(
                    painter: _SparklinePainter(
                      summary.history.map((record) => record.value).toList(),
                      accent,
                    ),
                  ),
                ),
              ),
            ),
            Text(
              summary.history.length < 2
                  ? 'Se requieren más lecturas para mostrar la tendencia'
                  : 'Últimas ${summary.history.length} lecturas',
              style: const TextStyle(
                color: BioMedicaColors.muted,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static IconData _metricIcon(String dataType) => switch (dataType) {
    'HEART_RATE' => Icons.favorite_rounded,
    'RESTING_HEART_RATE' => Icons.monitor_heart_rounded,
    'BLOOD_OXYGEN' => Icons.air_rounded,
    'BODY_TEMPERATURE' => Icons.thermostat_rounded,
    'BLOOD_PRESSURE_SYSTOLIC' ||
    'BLOOD_PRESSURE_DIASTOLIC' => Icons.bloodtype_rounded,
    'BODY_FAT_PERCENTAGE' ||
    'LEAN_BODY_MASS' ||
    'BODY_MASS_INDEX' => Icons.fitness_center_rounded,
    'BODY_WATER_MASS' => Icons.water_drop_rounded,
    'WEIGHT' => Icons.monitor_weight_outlined,
    'HEIGHT' => Icons.straighten_rounded,
    'SLEEP_SESSION' ||
    'SLEEP_ASLEEP' ||
    'SLEEP_DEEP' ||
    'SLEEP_REM' => Icons.bedtime_rounded,
    _ => Icons.health_and_safety_rounded,
  };

  static Color _metricColor(String dataType) => switch (dataType) {
    'HEART_RATE' || 'RESTING_HEART_RATE' => const Color(0xFFD64550),
    'BLOOD_OXYGEN' => const Color(0xFF1976D2),
    'BODY_TEMPERATURE' => const Color(0xFFE07A32),
    'BLOOD_PRESSURE_SYSTOLIC' ||
    'BLOOD_PRESSURE_DIASTOLIC' => const Color(0xFF9C4141),
    'BODY_FAT_PERCENTAGE' ||
    'LEAN_BODY_MASS' ||
    'BODY_MASS_INDEX' ||
    'BODY_WATER_MASS' => const Color(0xFF168A83),
    'SLEEP_SESSION' ||
    'SLEEP_ASLEEP' ||
    'SLEEP_DEEP' ||
    'SLEEP_REM' => const Color(0xFF7755A5),
    _ => BioMedicaColors.primary,
  };

  static String _formatDate(DateTime value) {
    final date = value.toLocal();
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }
}

class _SparklinePainter extends CustomPainter {
  const _SparklinePainter(this.values, this.color);

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty || size.width <= 0 || size.height <= 0) return;

    final minimum = values.reduce((a, b) => a < b ? a : b);
    final maximum = values.reduce((a, b) => a > b ? a : b);
    final range = maximum - minimum;
    const horizontalInset = 5.0;
    const verticalInset = 5.0;
    final usableWidth = size.width - horizontalInset * 2;
    final usableHeight = size.height - verticalInset * 2;
    final points = <Offset>[
      for (var index = 0; index < values.length; index++)
        Offset(
          values.length == 1
              ? size.width / 2
              : horizontalInset + usableWidth * index / (values.length - 1),
          verticalInset +
              usableHeight *
                  (range == 0 ? 0.5 : (maximum - values[index]) / range),
        ),
    ];

    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    if (points.length > 1) {
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, linePaint);
    }

    canvas.drawCircle(points.last, 3, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) =>
      !listEquals(values, oldDelegate.values) || color != oldDelegate.color;
}
