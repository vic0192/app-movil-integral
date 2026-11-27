import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/clinical_video_call_repository.dart';
import '../services/demo_video_call_service.dart';

Future<void> showClinicalCallInviteDialog(
  BuildContext context,
  ClinicalVideoCall call,
) async {
  final action = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Invitación de videollamada enviada'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'El paciente recibirá esta invitación en BioMedica. Jitsi es una '
            'sala pública de demostración: no compartas nombres, diagnósticos '
            'ni información clínica durante la llamada.',
          ),
          const SizedBox(height: 12),
          SelectableText(call.inviteUrl),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
        TextButton.icon(
          onPressed: () => Navigator.pop(context, 'copy'),
          icon: const Icon(Icons.copy_rounded),
          label: const Text('Copiar enlace'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, 'join'),
          icon: const Icon(Icons.video_call_rounded),
          label: const Text('Abrir sala'),
        ),
      ],
    ),
  );
  if (!context.mounted || action == null) return;
  final messenger = ScaffoldMessenger.of(context);
  if (action == 'copy') {
    await Clipboard.setData(ClipboardData(text: call.inviteUrl));
    if (context.mounted) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Enlace de la sala copiado.')),
      );
    }
    return;
  }
  final opened = await DemoVideoCallService.openInvite(call.inviteUrl);
  if (!opened && context.mounted) {
    messenger.showSnackBar(
      const SnackBar(content: Text('No se pudo abrir la sala de video.')),
    );
  }
}
