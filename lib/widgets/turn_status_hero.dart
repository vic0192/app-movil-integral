import 'package:flutter/material.dart';

import '../bio_medica_colors.dart';

class TurnStatusHero extends StatelessWidget {
  const TurnStatusHero({
    super.key,
    required this.ticketNumber,
    required this.status,
    required this.service,
    required this.room,
    required this.estimatedWait,
    required this.peopleAhead,
    this.progress = 0.72,
  });

  final String ticketNumber;
  final String status;
  final String service;
  final String room;
  final String estimatedWait;
  final int peopleAhead;
  final double progress;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
    decoration: BoxDecoration(
      color: BioMedicaColors.ink,
      borderRadius: BorderRadius.circular(20),
      boxShadow: const [
        BoxShadow(
          color: Color(0x2210264D),
          blurRadius: 20,
          offset: Offset(0, 8),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.confirmation_number_outlined,
              color: Colors.white,
              size: 22,
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'TU TURNO',
                style: TextStyle(
                  color: Color(0xFFD7E2F5),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFFE3A7),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                status.toUpperCase(),
                style: const TextStyle(
                  color: BioMedicaColors.ink,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Text(
          ticketNumber,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 56,
            height: 1,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '$service · $room',
          style: const TextStyle(color: Color(0xFFD7E2F5), fontSize: 13),
        ),
        const SizedBox(height: 20),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: progress.clamp(0, 1),
            minHeight: 6,
            backgroundColor: Color(0x334D6792),
            valueColor: const AlwaysStoppedAnimation<Color>(
              Color(0xFF77A7FF),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _TurnStat(value: estimatedWait, label: 'Espera estimada'),
            ),
            Expanded(
              child: _TurnStat(value: '$peopleAhead', label: 'Personas antes'),
            ),
          ],
        ),
      ],
    ),
  );
}

class _TurnStat extends StatelessWidget {
  const _TurnStat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        value,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 3),
      Text(
        label,
        style: const TextStyle(color: Color(0xFFD7E2F5), fontSize: 10),
      ),
    ],
  );
}
