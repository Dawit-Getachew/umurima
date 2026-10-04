import 'package:flutter_test/flutter_test.dart';

import 'package:umurima/services/gateway_settings.dart';

void main() {
  test('Rwandan numbers are grouped for reading aloud', () {
    expect(GatewaySettings.format('+250788123456'), '+250 788 123 456');
    expect(GatewaySettings.format('+250 788-123-456'), '+250 788 123 456');
  });

  test('other formats are shown as entered', () {
    expect(GatewaySettings.format('0788123456'), '0788123456');
  });
}
