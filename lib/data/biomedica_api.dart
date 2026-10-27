import 'dart:convert';

import 'package:http/http.dart' as http;

class BioMedicaApi {
  const BioMedicaApi({
    this.baseUrl = const String.fromEnvironment(
      'BIOMEDICA_API_URL',
      defaultValue: 'https://biomedica-smarttv.onrender.com',
    ),
  });

  final String baseUrl;

  Future<Map<String, dynamic>> fetchStatus() async {
    final response = await http
        .get(_uri('/api/status'))
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) {
      throw http.ClientException('BioMedica respondió ${response.statusCode}.');
    }
    return _decodeMap(response.body);
  }

  Uri _uri(String path) =>
      Uri.parse('${baseUrl.replaceFirst(RegExp(r'/+$'), '')}$path');

  Map<String, dynamic> _decodeMap(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      throw const FormatException('La API devolvió una respuesta inválida.');
    }
    return Map<String, dynamic>.from(decoded);
  }
}
