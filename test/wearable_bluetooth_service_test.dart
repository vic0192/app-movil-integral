import 'package:biomedica_app/ble/wearable_bluetooth_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BLE standard measurement decoders', () {
    test('decodes 8-bit and 16-bit heart rate measurements', () {
      expect(WearableBluetoothService.parseHeartRate([0x00, 74]), 74);
      expect(WearableBluetoothService.parseHeartRate([0x01, 0x2c, 0x01]), 300);
      expect(WearableBluetoothService.parseHeartRate([0x01, 0x2c]), isNull);
    });

    test('decodes standard pulse oximeter SFLOAT values', () {
      expect(WearableBluetoothService.parsePulseOximeter([0x00, 97, 0]), 97);
    });

    test('decodes IEEE 11073 temperature measurements', () {
      expect(
        WearableBluetoothService.parseTemperature([0x00, 0x6d, 0x01, 0, 0xff]),
        36.5,
      );
    });
  });
}
