import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// The number farmers text. Android can rarely read a SIM's own number, because
/// carriers often do not store it on the SIM, so the operator confirms it once.
/// It is kept on this phone only.
class GatewaySettings {
  GatewaySettings._();

  /// Optional default for a demo build: `--dart-define=GATEWAY_NUMBER=+2507...`.
  static const String buildDefault = String.fromEnvironment('GATEWAY_NUMBER');

  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, 'gateway_number.txt'));
  }

  static Future<String?> savedNumber() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final number = (await file.readAsString()).trim();
      return number.isEmpty ? null : number;
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveNumber(String number) async {
    final file = await _file();
    await file.writeAsString(number.trim());
  }

  /// "+250788123456" -> "+250 788 123 456"; other formats are returned as given.
  static String format(String raw) {
    final compact = raw.replaceAll(RegExp(r'[\s-]'), '');
    final match = RegExp(r'^\+250(\d{3})(\d{3})(\d{3})$').firstMatch(compact);
    return match == null ? raw : '+250 ${match[1]} ${match[2]} ${match[3]}';
  }
}
