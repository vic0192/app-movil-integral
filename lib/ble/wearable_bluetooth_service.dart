import 'dart:async';
import 'dart:math' as math;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class GattCharacteristicReading {
  const GattCharacteristicReading({
    required this.serviceUuid,
    required this.characteristicUuid,
    required this.canRead,
    required this.canNotify,
    required this.canIndicate,
    required this.canWrite,
    this.value = const [],
    this.error,
  });

  final String serviceUuid;
  final String characteristicUuid;
  final bool canRead;
  final bool canNotify;
  final bool canIndicate;
  final bool canWrite;
  final List<int> value;
  final String? error;

  String get key => '$serviceUuid/$characteristicUuid';

  String get hexValue => value.isEmpty
      ? 'Sin lectura'
      : value.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join(' ');

  GattCharacteristicReading copyWith({List<int>? value, String? error}) =>
      GattCharacteristicReading(
        serviceUuid: serviceUuid,
        characteristicUuid: characteristicUuid,
        canRead: canRead,
        canNotify: canNotify,
        canIndicate: canIndicate,
        canWrite: canWrite,
        value: value ?? this.value,
        error: error,
      );
}

class WearableBluetoothService extends ChangeNotifier {
  WearableBluetoothService() {
    _scanSubscription = FlutterBluePlus.isScanning.listen((scanning) {
      _isScanning = scanning;
      _notifyListeners();
    });
  }

  final Map<String, GattCharacteristicReading> _readings = {};
  final List<StreamSubscription<List<int>>> _valueSubscriptions = [];
  late final StreamSubscription<bool> _scanSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  BluetoothDevice? _device;
  String? _deviceName;
  bool _isScanning = false;
  bool _disposed = false;
  bool isConnecting = false;
  void _notifyListeners() {
    if (!_disposed) notifyListeners();
  }

  int? heartRate;
  double? oxygenSaturation;
  double? temperature;
  String? statusMessage;

  Stream<List<ScanResult>> get scanResults => FlutterBluePlus.onScanResults;
  bool get isScanning => _isScanning;
  bool get isConnectingToWearable => isConnecting;
  BluetoothDevice? get device => _device;
  String? get deviceName => _deviceName;
  bool get isConnected => _device?.isConnected ?? false;
  List<GattCharacteristicReading> get readings => _readings.values.toList();

  Future<void> startScan() async {
    statusMessage = null;
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      throw StateError(
        'La búsqueda BLE requiere un teléfono Android o iPhone.',
      );
    }
    if (!await FlutterBluePlus.isSupported) {
      throw StateError('Este dispositivo no es compatible con Bluetooth LE.');
    }

    await _requestPermissions();
    if (defaultTargetPlatform == TargetPlatform.android) {
      await FlutterBluePlus.turnOn();
    }
    await FlutterBluePlus.adapterState
        .where((state) => state == BluetoothAdapterState.on)
        .first
        .timeout(const Duration(seconds: 12));
    await FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 15),
      androidScanMode: AndroidScanMode.lowLatency,
    );
  }

  Future<void> _requestPermissions() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = await DeviceInfoPlugin().androidInfo;
      final permissions = android.version.sdkInt >= 31
          ? [Permission.bluetoothScan, Permission.bluetoothConnect]
          : [Permission.locationWhenInUse];
      final results = await permissions.request();
      if (results.values.any((status) => !status.isGranted)) {
        throw StateError(
          'BioMedica necesita permiso de dispositivos cercanos para buscar el reloj.',
        );
      }
    } else {
      final result = await Permission.bluetooth.request();
      if (!result.isGranted) {
        throw StateError('Permite el uso de Bluetooth para buscar el reloj.');
      }
    }
  }

  Future<void> stopScan() => FlutterBluePlus.stopScan();

  Future<void> connect(ScanResult result) async {
    await stopScan();
    await disconnect();
    final device = result.device;
    _device = device;
    _deviceName = _displayName(result);
    _readings.clear();
    heartRate = null;
    oxygenSaturation = null;
    temperature = null;
    isConnecting = true;
    statusMessage = 'Conectando con $_deviceName…';
    _notifyListeners();

    try {
      await device.connect(
        license: License.nonprofit,
        timeout: const Duration(seconds: 15),
      );
      _connectionSubscription = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _clearConnection('Se perdió la conexión Bluetooth.');
        }
      });
      statusMessage = 'Bluetooth conectado; explorando servicios GATT…';
      _notifyListeners();
      final services = await device.discoverServices().timeout(
        const Duration(seconds: 12),
      );
      final totalCharacteristics = services.fold<int>(
        0,
        (total, service) => total + service.characteristics.length,
      );
      var inspectedCharacteristics = 0;
      var supportedMeasurementCharacteristics = 0;
      for (final service in services) {
        for (final characteristic in service.characteristics) {
          inspectedCharacteristics++;
          statusMessage =
              'Revisando característica $inspectedCharacteristics/$totalCharacteristics…';
          _notifyListeners();
          final serviceUuid = service.uuid.toString().toLowerCase();
          final characteristicUuid = characteristic.uuid
              .toString()
              .toLowerCase();
          final properties = characteristic.properties;
          final initialReading = GattCharacteristicReading(
            serviceUuid: serviceUuid,
            characteristicUuid: characteristicUuid,
            canRead: properties.read,
            canNotify: properties.notify,
            canIndicate: properties.indicate,
            canWrite: properties.write || properties.writeWithoutResponse,
          );
          _readings[initialReading.key] = initialReading;
          _notifyListeners();

          final isStandardMeasurement = _isStandardMeasurement(
            serviceUuid,
            characteristicUuid,
          );
          final isKronosDataChannel = _isKronosDataChannel(
            serviceUuid,
            characteristicUuid,
            properties.notify,
            properties.indicate,
          );
          if (!isStandardMeasurement && !isKronosDataChannel) {
            continue;
          }
          if (properties.read || properties.notify || properties.indicate) {
            supportedMeasurementCharacteristics++;
          }

          if (properties.notify || properties.indicate) {
            try {
              await characteristic
                  .setNotifyValue(true)
                  .timeout(const Duration(seconds: 5));
              final subscription = characteristic.onValueReceived.listen(
                (value) =>
                    _updateReading(serviceUuid, characteristicUuid, value),
              );
              _valueSubscriptions.add(subscription);
              device.cancelWhenDisconnected(subscription);
            } catch (error) {
              _setReadingError(initialReading.key, error);
            }
          }

          if (properties.read && !properties.notify && !properties.indicate) {
            try {
              final value = await characteristic.read().timeout(
                const Duration(seconds: 5),
              );
              _updateReading(serviceUuid, characteristicUuid, value);
            } catch (error) {
              _setReadingError(initialReading.key, error);
            }
          }
        }
      }
      isConnecting = false;
      statusMessage = services.isEmpty
          ? 'Conectado, pero el reloj no anunció servicios GATT.'
          : supportedMeasurementCharacteristics == 0
          ? 'Bluetooth conectado, pero no hay mediciones BLE estándar '
                'compatibles. No se detectaron canales de datos compatibles.'
          : _readings.values.any(
              (reading) => reading.serviceUuid.endsWith('56ff'),
            )
          ? 'Bluetooth conectado; canal de datos Kronos detectado. '
                'Esperando lecturas del reloj.'
          : 'Conectado · ${services.length} servicios GATT; '
                'escuchando canales de medición compatibles.';
      _notifyListeners();
    } catch (error) {
      isConnecting = false;
      statusMessage = 'No se pudo conectar: $error';
      _notifyListeners();
      rethrow;
    }
  }

  Future<void> disconnect() async {
    isConnecting = false;
    final device = _device;
    await _cancelSubscriptions();
    await _connectionSubscription?.cancel();
    _connectionSubscription = null;
    if (device != null && device.isConnected) {
      await device.disconnect();
    }
    _clearConnection('Desconectado.');
  }

  void _updateReading(
    String serviceUuid,
    String characteristicUuid,
    List<int> value,
  ) {
    final key = '$serviceUuid/$characteristicUuid';
    final reading = _readings[key];
    if (reading == null) return;
    _readings[key] = reading.copyWith(value: List.unmodifiable(value));

    if (characteristicUuid.endsWith('2a37')) {
      heartRate = parseHeartRate(value);
    } else if (serviceUuid.endsWith('1822') &&
        (characteristicUuid.endsWith('2a5e') ||
            characteristicUuid.endsWith('2a5f'))) {
      oxygenSaturation = parsePulseOximeter(value);
    } else if (characteristicUuid.endsWith('2a1c')) {
      temperature = parseTemperature(value);
    }
    _notifyListeners();
  }

  void _setReadingError(String key, Object error) {
    final reading = _readings[key];
    if (reading == null) return;
    _readings[key] = reading.copyWith(error: '$error');
    _notifyListeners();
  }

  Future<void> _cancelSubscriptions() async {
    for (final subscription in _valueSubscriptions) {
      await subscription.cancel();
    }
    _valueSubscriptions.clear();
  }

  void _clearConnection(String message) {
    _device = null;
    _deviceName = null;
    isConnecting = false;
    _readings.clear();
    heartRate = null;
    oxygenSaturation = null;
    temperature = null;
    statusMessage = message;
    _notifyListeners();
  }

  static bool _isStandardMeasurement(
    String serviceUuid,
    String characteristicUuid,
  ) =>
      (serviceUuid.endsWith('180d') && characteristicUuid.endsWith('2a37')) ||
      (serviceUuid.endsWith('1822') &&
          (characteristicUuid.endsWith('2a5e') ||
              characteristicUuid.endsWith('2a5f'))) ||
      (serviceUuid.endsWith('1809') && characteristicUuid.endsWith('2a1c'));

  static bool _isKronosDataChannel(
    String serviceUuid,
    String characteristicUuid,
    bool canNotify,
    bool canIndicate,
  ) =>
      (serviceUuid.endsWith('56ff') &&
          characteristicUuid.endsWith('33f4') &&
          (canNotify || canIndicate)) ||
      (serviceUuid.startsWith('fef5') && (canNotify || canIndicate));

  static String _displayName(ScanResult result) {
    final advertised = result.advertisementData.advName.trim();
    if (advertised.isNotEmpty) return advertised;
    final platformName = result.device.platformName.trim();
    return platformName.isNotEmpty ? platformName : 'Wearable sin nombre';
  }

  static int? parseHeartRate(List<int> value) {
    if (value.length < 2) return null;
    final usesUInt16 = value[0] & 0x01 != 0;
    if (!usesUInt16) return value[1];
    if (value.length < 3) return null;
    return value[1] | (value[2] << 8);
  }

  static double? parsePulseOximeter(List<int> value) {
    if (value.length < 3) return null;
    return _decodeSfloat(value, 1);
  }

  static double? parseTemperature(List<int> value) {
    if (value.length < 5) return null;
    final raw =
        value[1] | (value[2] << 8) | (value[3] << 16) | (value[4] << 24);
    var mantissa = raw & 0x00ffffff;
    if (mantissa & 0x00800000 != 0) mantissa -= 0x01000000;
    var exponent = (raw >> 24) & 0xff;
    if (exponent >= 0x80) exponent -= 0x100;
    return (mantissa * math.pow(10, exponent)).toDouble();
  }

  static double? _decodeSfloat(List<int> value, int offset) {
    if (value.length < offset + 2) return null;
    final raw = value[offset] | (value[offset + 1] << 8);
    if (raw == 0x07ff || raw == 0x0800 || raw == 0x0802 || raw == 0x07fe) {
      return null;
    }
    var mantissa = raw & 0x0fff;
    if (mantissa & 0x0800 != 0) mantissa -= 0x1000;
    var exponent = (raw >> 12) & 0x0f;
    if (exponent >= 0x08) exponent -= 0x10;
    return (mantissa * math.pow(10, exponent)).toDouble();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_scanSubscription.cancel());
    unawaited(disconnect());
    super.dispose();
  }
}
