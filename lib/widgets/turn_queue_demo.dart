import 'package:flutter/material.dart';

import '../bio_medica_colors.dart';
import 'turn_status_hero.dart';

class TurnQueueDemo extends StatefulWidget {
  const TurnQueueDemo({super.key});

  @override
  State<TurnQueueDemo> createState() => _TurnQueueDemoState();
}

class _TurnQueueDemoState extends State<TurnQueueDemo> {
  static const _initialPeopleAhead = 3;
  static const _lastStep = _initialPeopleAhead + 1;

  int _step = 0;

  int get _peopleAhead => (_initialPeopleAhead - _step).clamp(0, _initialPeopleAhead);

  bool get _inConsultation => _step == _initialPeopleAhead;

  bool get _attended => _step == _lastStep;

  String get _status {
    if (_attended) return 'Atendido';
    if (_inConsultation) return 'En consulta';
    return 'En espera';
  }

  String get _estimatedWait {
    if (_attended) return 'Finalizado';
    if (_inConsultation) return 'Ahora';
    return '${_peopleAhead * 6} min';
  }

  void _advanceQueue() {
    setState(() {
      _step = _attended ? 0 : _step + 1;
    });
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TurnStatusHero(
        ticketNumber: 'B-024',
        status: _status,
        service: 'Consulta general',
        room: 'Sala 2',
        estimatedWait: _estimatedWait,
        peopleAhead: _peopleAhead,
        progress: 0.35 + (_step / _lastStep) * 0.65,
      ),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: BioMedicaColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: BioMedicaColors.line),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0D10264D),
              blurRadius: 16,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  color: BioMedicaColors.primary,
                  size: 19,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Demostración interactiva',
                    style: TextStyle(
                      color: BioMedicaColors.ink,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            const Text(
              'Este turno es de ejemplo; todavía no se sincroniza con un paciente del servidor.',
              style: TextStyle(
                color: BioMedicaColors.muted,
                fontSize: 12,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 13),
            FilledButton.icon(
              key: const ValueKey('advance-turn-demo'),
              onPressed: _advanceQueue,
              icon: Icon(
                _attended ? Icons.restart_alt_rounded : Icons.skip_next_rounded,
              ),
              label: Text(
                _attended
                    ? 'Reiniciar demostración'
                    : 'Simular avance de fila',
              ),
            ),
          ],
        ),
      ),
    ],
  );
}
