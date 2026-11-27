import 'package:flutter/material.dart';

import '../bio_medica_colors.dart';
import '../data/clinic_turn_repository.dart';
import 'turn_status_hero.dart';

class TurnQueuePanel extends StatelessWidget {
  const TurnQueuePanel({
    super.key,
    required this.patientTurn,
    required this.activeQueue,
    required this.loading,
    required this.onRefresh,
    this.error,
  });

  final ClinicTurn? patientTurn;
  final List<ClinicTurn> activeQueue;
  final bool loading;
  final String? error;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final turn = patientTurn;
    final turnIndex = turn == null
        ? -1
        : activeQueue.indexWhere((item) => item.ticketCode == turn.ticketCode);
    final peopleAhead = turnIndex < 0 ? 0 : turnIndex;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (error != null)
          _stateCard(
            icon: Icons.cloud_off_outlined,
            message: 'No se pudieron cargar los turnos. Inténtalo de nuevo.',
          ),
        if (turn != null)
          TurnStatusHero(
            ticketNumber: turn.ticketCode,
            status: turn.status == 'en_atencion' ? 'En consulta' : 'En espera',
            service: turn.service,
            room: turn.room,
            estimatedWait: turn.status == 'en_atencion'
                ? 'Ahora'
                : '${turn.etaMinutes} min',
            peopleAhead: peopleAhead,
            progress: turn.status == 'en_atencion' ? 1 : 1 / (peopleAhead + 1),
          )
        else
          _stateCard(
            icon: Icons.confirmation_number_outlined,
            message: 'No tienes un turno activo asignado.',
          ),
        const SizedBox(height: 18),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Turnos en atención y en espera',
                style: TextStyle(
                  color: BioMedicaColors.ink,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Actualizar turnos',
              onPressed: loading ? null : onRefresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        if (loading && activeQueue.isEmpty)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (activeQueue.isEmpty)
          _stateCard(
            icon: Icons.event_busy_outlined,
            message: 'No hay turnos pasando en este momento.',
          )
        else
          ...activeQueue.map(_queueTile),
      ],
    );
  }

  Widget _queueTile(ClinicTurn turn) {
    final isCurrent = turn.status == 'en_atencion';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: BioMedicaColors.surface,
        border: Border.all(color: BioMedicaColors.line),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: isCurrent
                ? BioMedicaColors.greenLight
                : BioMedicaColors.primaryLight,
            child: Icon(
              isCurrent
                  ? Icons.record_voice_over_outlined
                  : Icons.hourglass_bottom_rounded,
              color: isCurrent
                  ? BioMedicaColors.green
                  : BioMedicaColors.primary,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  turn.ticketCode,
                  style: const TextStyle(
                    color: BioMedicaColors.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  '${turn.service} · ${turn.room}',
                  style: const TextStyle(
                    color: BioMedicaColors.muted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Text(
            isCurrent ? 'En atención' : '${turn.etaMinutes} min',
            style: TextStyle(
              color: isCurrent ? BioMedicaColors.green : BioMedicaColors.muted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _stateCard({required IconData icon, required String message}) =>
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: BioMedicaColors.surface,
          border: Border.all(color: BioMedicaColors.line),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(icon, color: BioMedicaColors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: BioMedicaColors.muted,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      );
}
