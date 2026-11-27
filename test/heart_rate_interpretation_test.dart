import 'package:biomedica_app/models/heart_rate_interpretation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('marks only 60 to 100 BPM as the adult resting reference', () {
    expect(
      HeartRateInterpretation.fromBpm(59).band,
      HeartRateBand.belowReference,
    );
    expect(HeartRateInterpretation.fromBpm(60).band, HeartRateBand.reference);
    expect(HeartRateInterpretation.fromBpm(100).band, HeartRateBand.reference);
    expect(
      HeartRateInterpretation.fromBpm(101).band,
      HeartRateBand.aboveReference,
    );
  });

  test('does not present a diagnosis when a reading is unavailable', () {
    final interpretation = HeartRateInterpretation.fromBpm(null);

    expect(interpretation.band, HeartRateBand.unavailable);
    expect(interpretation.label, 'Sin mediciones recientes');
  });
}
