import 'package:flutter/material.dart';

import '../bio_medica_colors.dart';

class VitalIndicatorCard extends StatelessWidget {
  const VitalIndicatorCard({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
    required this.progress,
    required this.color,
    required this.diameter,
  });

  final String label;
  final String value;
  final String unit;
  final double progress;
  final Color color;
  final double diameter;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 120),
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
    decoration: BoxDecoration(
      color: BioMedicaColors.surface,
      borderRadius: BorderRadius.circular(15),
      border: Border.all(color: BioMedicaColors.line),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0A10264D),
          blurRadius: 14,
          offset: Offset(0, 5),
        ),
      ],
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox.square(
          dimension: diameter,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox.square(
                dimension: diameter,
                child: CircularProgressIndicator(
                  value: progress.clamp(0, 1),
                  strokeWidth: 5,
                  backgroundColor: BioMedicaColors.line,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  value,
                  style: TextStyle(
                    color: BioMedicaColors.ink,
                    fontSize: diameter < 52 ? 15 : 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 7),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            unit,
            style: const TextStyle(
              color: BioMedicaColors.muted,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: BioMedicaColors.ink,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}
