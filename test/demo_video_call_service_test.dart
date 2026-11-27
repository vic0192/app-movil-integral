import 'package:flutter_test/flutter_test.dart';

import 'package:biomedica_app/services/demo_video_call_service.dart';

void main() {
  test('creates unique Jitsi demo invitations without patient data', () {
    final first = DemoVideoCallService.createInvite();
    final second = DemoVideoCallService.createInvite();

    expect(first.scheme, 'https');
    expect(first.host, 'meet.jit.si');
    expect(first.pathSegments, hasLength(1));
    expect(first.pathSegments.single, startsWith('BioMedicaDemo-'));
    expect(DemoVideoCallService.isValidInvite(first.toString()), isTrue);
    expect(second, isNot(first));
  });

  test('rejects links outside the generated public demo room format', () {
    expect(
      DemoVideoCallService.isValidInvite(
        'https://meet.jit.si/medical-consult-patient-123',
      ),
      isFalse,
    );
    expect(
      DemoVideoCallService.isValidInvite(
        'https://example.com/BioMedicaDemo-abcdefghijklmnopqrstuvwx',
      ),
      isFalse,
    );
  });
}
