import '../models/app_user_profile.dart';
import '../models/health_report.dart';

abstract interface class ReportRepository {
  String? get ownerUid;

  AppRole? get role;

  Future<void> initialize();

  Stream<List<HealthReport>> watchReports();

  Future<String> createReport(HealthReportDraft draft, {String? documentId});

  Future<void> updateReport(String id, HealthReportDraft draft);

  Future<void> deleteReport(String id);
}

class ReportStoreException implements Exception {
  const ReportStoreException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}

class DuplicateReportIdException extends ReportStoreException {
  const DuplicateReportIdException(String id)
    : super('Ya existe un reporte con el identificador "$id".');
}

class ReportNotFoundException extends ReportStoreException {
  const ReportNotFoundException(String id)
    : super('No existe el reporte "$id". No se realizaron cambios.');
}
