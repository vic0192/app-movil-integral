import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../models/health_report.dart';

abstract interface class ReportRepository {
  String? get ownerUid;

  Future<void> initialize();

  Stream<List<HealthReport>> watchReports();

  Future<String> createReport(HealthReportDraft draft, {String? documentId});

  Future<void> updateReport(String id, HealthReportDraft draft);

  Future<void> deleteReport(String id);
}

class FirestoreReportRepository implements ReportRepository {
  FirestoreReportRepository({this.auth, this.firestore});

  final FirebaseAuth? auth;
  final FirebaseFirestore? firestore;
  String? _ownerUid;

  @override
  String? get ownerUid => _ownerUid;

  FirebaseAuth get _firebaseAuth => auth ?? FirebaseAuth.instance;
  FirebaseFirestore get _database => firestore ?? FirebaseFirestore.instance;

  @override
  Future<void> initialize() async {
    try {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp();
      final user =
          _firebaseAuth.currentUser ??
          (await _firebaseAuth.signInAnonymously()).user;
      if (user == null) {
        throw const ReportStoreException(
          'No se pudo crear una sesión segura para los reportes.',
        );
      }
      _ownerUid = user.uid;
    } on FirebaseException catch (error, stackTrace) {
      Error.throwWithStackTrace(_mapFirebaseError(error), stackTrace);
    }
  }

  @override
  Stream<List<HealthReport>> watchReports() {
    final ownerUid = _requireOwner();
    try {
      return _database
          .collection('reportes')
          .where('ownerUid', isEqualTo: ownerUid)
          .snapshots(includeMetadataChanges: true)
          .map((snapshot) {
            final reports = <HealthReport>[];
            for (final document in snapshot.docs) {
              final data = document.data();
              if (!data.containsKey('equipment') ||
                  !data.containsKey('description') ||
                  !data.containsKey('priority')) {
                debugPrint(
                  'Se omitió el reporte ${document.id}: usa el esquema '
                  'anterior y no corresponde al formato equipo/descripción/'
                  'prioridad.',
                );
                continue;
              }
              reports.add(
                HealthReport.fromFirestore(
                  document.id,
                  data,
                  pendingSync: document.metadata.hasPendingWrites,
                ),
              );
            }
            reports.sort(
              (left, right) => right.createdAt.compareTo(left.createdAt),
            );
            return reports;
          })
          .handleError((Object error, StackTrace stackTrace) {
            if (error is FirebaseException) {
              Error.throwWithStackTrace(_mapFirebaseError(error), stackTrace);
            }
            Error.throwWithStackTrace(error, stackTrace);
          });
    } on FirebaseException catch (error, stackTrace) {
      Error.throwWithStackTrace(_mapFirebaseError(error), stackTrace);
    }
  }

  @override
  Future<String> createReport(
    HealthReportDraft draft, {
    String? documentId,
  }) async {
    final ownerUid = _requireOwner();
    try {
      final collection = _database.collection('reportes');
      final requestedId = documentId ?? draft.id;
      final document = requestedId.trim().isEmpty
          ? collection.doc()
          : collection.doc(_validateDocumentId(requestedId));
      final now = FieldValue.serverTimestamp();
      final data = {
        ..._reportData(draft),
        'ownerUid': ownerUid,
        'createdAt': now,
        'updatedAt': now,
      };
      if (requestedId.trim().isEmpty) {
        await document.set(data);
      } else {
        await _database.runTransaction((transaction) async {
          if ((await transaction.get(document)).exists) {
            throw DuplicateReportIdException(document.id);
          }
          transaction.set(document, data);
        });
      }
      return document.id;
    } on FirebaseException catch (error, stackTrace) {
      Error.throwWithStackTrace(_mapFirebaseError(error), stackTrace);
    }
  }

  @override
  Future<void> updateReport(String id, HealthReportDraft draft) async {
    final ownerUid = _requireOwner();
    try {
      final document = _database.collection('reportes').doc(id);
      final snapshot = await document.get();
      if (!snapshot.exists) throw ReportNotFoundException(id);
      if (snapshot.data()?['ownerUid'] != ownerUid) {
        throw const ReportStoreException(
          'No tienes permiso para modificar este reporte.',
        );
      }
      await document.update({
        ..._reportData(draft),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (error, stackTrace) {
      Error.throwWithStackTrace(_mapFirebaseError(error), stackTrace);
    }
  }

  @override
  Future<void> deleteReport(String id) async {
    final ownerUid = _requireOwner();
    try {
      final document = _database.collection('reportes').doc(id);
      final snapshot = await document.get();
      if (!snapshot.exists) throw ReportNotFoundException(id);
      if (snapshot.data()?['ownerUid'] != ownerUid) {
        throw const ReportStoreException(
          'No tienes permiso para eliminar este reporte.',
        );
      }
      await document.delete();
    } on FirebaseException catch (error, stackTrace) {
      Error.throwWithStackTrace(_mapFirebaseError(error), stackTrace);
    }
  }

  String _requireOwner() {
    final ownerUid = _ownerUid;
    if (ownerUid == null) {
      throw const ReportStoreException(
        'La sesión de Firebase no está lista. Vuelve a intentarlo.',
      );
    }
    return ownerUid;
  }

  String _validateDocumentId(String id) {
    final normalized = id.trim();
    if (normalized.isEmpty || normalized.contains('/')) {
      throw const ReportStoreException(
        'El identificador debe ser válido y no puede estar vacío.',
      );
    }
    return normalized;
  }

  Map<String, Object> _reportData(HealthReportDraft draft) => {
    'equipment': draft.equipment.trim(),
    'description': draft.description.trim(),
    'priority': draft.priority,
  };

  ReportStoreException _mapFirebaseError(FirebaseException error) {
    if (error.message?.contains('CONFIGURATION_NOT_FOUND') ?? false) {
      return const ReportStoreException(
        'Firebase Authentication no está configurado para esta app. Activa '
        'el inicio de sesión anónimo en Firebase Console y registra la app '
        'Android con FlutterFire CLI.',
        code: 'CONFIGURATION_NOT_FOUND',
      );
    }
    return switch (error.code) {
      'permission-denied' => const ReportStoreException(
        'Firebase rechazó la operación. Revisa las reglas y la sesión.',
        code: 'permission-denied',
      ),
      'unavailable' || 'network-request-failed' => const ReportStoreException(
        'Sin conexión con Firebase. Los cambios no se guardaron; revisa '
        'tu conexión e inténtalo de nuevo.',
        code: 'unavailable',
      ),
      'failed-precondition' => const ReportStoreException(
        'Firestore necesita una configuración adicional. Revisa el índice '
        'indicado en Firebase Console.',
        code: 'failed-precondition',
      ),
      _ => ReportStoreException(
        'Firebase no pudo completar la operación (${error.code}). '
                '${error.message ?? ''}'
            .trim(),
        code: error.code,
      ),
    };
  }
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
