import 'package:flutter/material.dart';

import '../bio_medica_colors.dart';

class HistoryReadingTile extends StatelessWidget {
  const HistoryReadingTile({
    super.key,
    required this.heartRate,
    required this.oxygenSaturation,
    required this.temperature,
    required this.time,
    required this.isDemo,
  });

  final int heartRate;
  final int oxygenSaturation;
  final String temperature;
  final String time;
  final bool isDemo;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
    decoration: BoxDecoration(
      color: BioMedicaColors.surface,
      border: Border.all(color: BioMedicaColors.line),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        const Icon(
          Icons.favorite_rounded,
          color: BioMedicaColors.red,
          size: 19,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$heartRate BPM  ·  $oxygenSaturation% SpO₂',
                style: const TextStyle(
                  color: BioMedicaColors.ink,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
              Text(
                '$temperature °C${isDemo ? ' · demostración' : ''}',
                style: const TextStyle(
                  color: BioMedicaColors.muted,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
        Text(
          time,
          style: const TextStyle(color: BioMedicaColors.muted, fontSize: 10),
        ),
      ],
    ),
  );
}
