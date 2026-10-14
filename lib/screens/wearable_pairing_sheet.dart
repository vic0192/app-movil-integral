import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../bio_medica_colors.dart';
import '../ble/wearable_bluetooth_service.dart';

class WearablePairingSheet extends StatefulWidget {
  const WearablePairingSheet({
    super.key,
    required this.monitor,
    required this.onUseDemo,
  });

  final WearableBluetoothService monitor;
  final VoidCallback onUseDemo;

  @override
  State<WearablePairingSheet> createState() => _WearablePairingSheetState();
}

class _WearablePairingSheetState extends State<WearablePairingSheet> {
  String? _error;

  Future<void> _scan() async {
    setState(() => _error = null);
    try {
      await widget.monitor.startScan();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _connect(ScanResult result) async {
    setState(() => _error = null);
    try {
      await widget.monitor.connect(result);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.monitor,
    builder: (context, _) => ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.82,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Conectar wearable',
                    style: TextStyle(
                      color: BioMedicaColors.ink,
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Cerrar',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const Text(
              'Busca el STF Kronos y selecciónalo para conectarlo. Las mediciones '
              'BLE estándar compatibles se enviarán a BioMedica automáticamente.',
              style: TextStyle(
                color: BioMedicaColors.muted,
                fontSize: 12,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            _measurementSummary(widget.monitor),
            const SizedBox(height: 10),
            if (_error != null) _errorBanner(_error!),
            if (widget.monitor.statusMessage != null &&
                !widget.monitor.isConnectingToWearable &&
                !widget.monitor.isConnected)
              _errorBanner(widget.monitor.statusMessage!),
            if (widget.monitor.isConnectingToWearable) ...[
              _connectionStatus(widget.monitor),
              const SizedBox(height: 10),
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 14),
                      Text(
                        widget.monitor.statusMessage ??
                            'Conectando con el reloj…',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: BioMedicaColors.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: widget.monitor.disconnect,
                icon: const Icon(Icons.close_rounded, size: 18),
                label: const Text('Cancelar conexión'),
              ),
            ] else if (widget.monitor.isConnected) ...[
              _connectionStatus(widget.monitor),
              const SizedBox(height: 7),
              const Text(
                'Servicios y características recibidas',
                style: TextStyle(
                  color: BioMedicaColors.ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 4),
              Expanded(child: _gattList(widget.monitor.readings)),
              OutlinedButton.icon(
                onPressed: widget.monitor.disconnect,
                icon: const Icon(Icons.link_off_rounded, size: 18),
                label: const Text('Desconectar'),
              ),
            ] else ...[
              FilledButton.icon(
                onPressed: widget.monitor.isScanning ? null : _scan,
                icon: Icon(
                  widget.monitor.isScanning
                      ? Icons.bluetooth_searching_rounded
                      : Icons.search_rounded,
                ),
                label: Text(
                  widget.monitor.isScanning
                      ? 'Buscando dispositivos…'
                      : 'Buscar dispositivos',
                ),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(47),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11),
                  ),
                ),
              ),
              const SizedBox(height: 9),
              const Text(
                'Dispositivos detectados',
                style: TextStyle(
                  color: BioMedicaColors.ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 4),
              Expanded(child: _scanResults(widget.monitor)),
              TextButton.icon(
                onPressed: widget.onUseDemo,
                icon: const Icon(Icons.science_outlined, size: 17),
                label: const Text('Usar datos de muestra'),
              ),
            ],
          ],
        ),
      ),
    ),
  );

  Widget _scanResults(WearableBluetoothService monitor) =>
      StreamBuilder<List<ScanResult>>(
        stream: monitor.scanResults,
        initialData: FlutterBluePlus.lastScanResults,
        builder: (context, snapshot) {
          final results = snapshot.data ?? const <ScanResult>[];
          final unique = <String, ScanResult>{};
          for (final result in results) {
            unique[result.device.remoteId.toString()] = result;
          }
          final devices = unique.values.toList()
            ..sort((left, right) {
              final leftName = _name(left).toLowerCase();
              final rightName = _name(right).toLowerCase();
              final leftMatch =
                  leftName.contains('stf') || leftName.contains('kronos');
              final rightMatch =
                  rightName.contains('stf') || rightName.contains('kronos');
              if (leftMatch != rightMatch) return leftMatch ? -1 : 1;
              return right.rssi.compareTo(left.rssi);
            });

          if (devices.isEmpty) {
            return Center(
              child: Text(
                monitor.isScanning
                    ? 'Acerca el reloj y espera a que aparezca.'
                    : 'Pulsa “Buscar dispositivos” para comenzar.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: BioMedicaColors.muted,
                  fontSize: 12,
                ),
              ),
            );
          }

          return ListView.separated(
            itemCount: devices.length,
            separatorBuilder: (_, _) => const SizedBox(height: 6),
            itemBuilder: (context, index) {
              final result = devices[index];
              return Material(
                color: BioMedicaColors.surface,
                borderRadius: BorderRadius.circular(12),
                child: ListTile(
                  onTap: () => _connect(result),
                  leading: const Icon(
                    Icons.watch_rounded,
                    color: BioMedicaColors.primary,
                  ),
                  title: Text(
                    _name(result),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: BioMedicaColors.ink,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  subtitle: Text(
                    '${result.device.remoteId} · ${result.rssi} dBm',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: BioMedicaColors.muted,
                      fontSize: 10,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                ),
              );
            },
          );
        },
      );

  Widget _measurementSummary(WearableBluetoothService monitor) => Container(
    padding: const EdgeInsets.all(11),
    decoration: BoxDecoration(
      color: BioMedicaColors.primaryLight,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        _measurement('BPM', monitor.heartRate?.toString()),
        _measurement('SpO₂', monitor.oxygenSaturation?.toStringAsFixed(0)),
        _measurement('°C', monitor.temperature?.toStringAsFixed(1)),
      ],
    ),
  );

  Widget _measurement(String unit, String? value) => Expanded(
    child: Column(
      children: [
        Text(
          value ?? '—',
          style: const TextStyle(
            color: BioMedicaColors.ink,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          unit,
          style: const TextStyle(
            color: BioMedicaColors.muted,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );

  Widget _connectionStatus(WearableBluetoothService monitor) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
    decoration: BoxDecoration(
      color: monitor.isConnected
          ? BioMedicaColors.greenLight
          : BioMedicaColors.primaryLight,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      children: [
        Icon(
          monitor.isConnected
              ? Icons.bluetooth_connected_rounded
              : Icons.bluetooth_searching_rounded,
          color: monitor.isConnected
              ? BioMedicaColors.green
              : BioMedicaColors.primary,
          size: 17,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '${monitor.deviceName ?? 'Wearable'} · ${monitor.statusMessage ?? 'conectado'}',
            style: TextStyle(
              color: monitor.isConnected
                  ? BioMedicaColors.green
                  : BioMedicaColors.primary,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _gattList(List<GattCharacteristicReading> readings) {
    if (readings.isEmpty) {
      return const Center(
        child: Text(
          'No se encontraron características GATT.',
          style: TextStyle(color: BioMedicaColors.muted, fontSize: 12),
        ),
      );
    }
    return ListView.separated(
      itemCount: readings.length,
      separatorBuilder: (_, _) => const SizedBox(height: 5),
      itemBuilder: (context, index) {
        final reading = readings[index];
        final access = [
          if (reading.canRead) 'leer',
          if (reading.canNotify) 'notify',
          if (reading.canIndicate) 'indicate',
          if (reading.canWrite) 'write',
        ].join(' · ');
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
          decoration: BoxDecoration(
            color: BioMedicaColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: BioMedicaColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _labelFor(reading.characteristicUuid),
                style: const TextStyle(
                  color: BioMedicaColors.ink,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${reading.serviceUuid} / ${reading.characteristicUuid}',
                style: const TextStyle(
                  color: BioMedicaColors.muted,
                  fontSize: 9,
                ),
              ),
              Text(
                '${access.isEmpty ? 'sin acceso anunciado' : access} · ${reading.hexValue}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: BioMedicaColors.primary,
                  fontSize: 9,
                ),
              ),
              if (reading.error != null)
                Text(
                  reading.error!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: BioMedicaColors.red,
                    fontSize: 9,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _errorBanner(String error) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: BioMedicaColors.redLight,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      error,
      style: const TextStyle(color: BioMedicaColors.red, fontSize: 11),
    ),
  );

  String _name(ScanResult result) {
    final advertised = result.advertisementData.advName.trim();
    if (advertised.isNotEmpty) return advertised;
    final platformName = result.device.platformName.trim();
    return platformName.isNotEmpty ? platformName : 'Wearable sin nombre';
  }

  String _labelFor(String uuid) {
    if (uuid.endsWith('2a37')) return 'Frecuencia cardiaca estándar';
    if (uuid.endsWith('2a5e') || uuid.endsWith('2a5f')) {
      return 'Oximetría estándar';
    }
    if (uuid.endsWith('2a1c')) return 'Temperatura estándar';
    if (uuid.endsWith('2a19')) return 'Batería';
    return 'Característica BLE';
  }
}
