import 'dart:convert';
import 'dart:math';

import 'package:url_launcher/url_launcher.dart';

class DemoVideoCallService {
  static const _roomPrefix = 'BioMedicaDemo-';
  static final _roomPattern = RegExp(r'^BioMedicaDemo-[A-Za-z0-9_-]{24}$');

  static Uri createInvite() {
    final randomBytes = List<int>.generate(
      18,
      (_) => Random.secure().nextInt(256),
    );
    final room =
        '$_roomPrefix${base64Url.encode(randomBytes).replaceAll('=', '')}';
    return Uri.https('meet.jit.si', '/$room');
  }

  static bool isValidInvite(String value) {
    final uri = Uri.tryParse(value.trim());
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host == 'meet.jit.si' &&
        uri.userInfo.isEmpty &&
        uri.port == 443 &&
        uri.query.isEmpty &&
        uri.fragment.isEmpty &&
        uri.pathSegments.length == 1 &&
        _roomPattern.hasMatch(uri.pathSegments.single);
  }

  static Future<bool> openInvite(String value) {
    if (!isValidInvite(value)) {
      throw const FormatException('El enlace de videollamada no es válido.');
    }
    return launchUrl(
      Uri.parse(value.trim()),
      mode: LaunchMode.externalApplication,
    );
  }
}
