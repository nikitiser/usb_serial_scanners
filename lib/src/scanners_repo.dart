import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../usb_serial_scanners.dart';

class ScannersMetaRepo {
  static Future<List<UsbSerialScannerMeta>> getSavedScannersMeta() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> jsons = prefs.getStringList(usbSerialDevicePrefKey) ?? [];
    return jsons.map((json) {
      final m = jsonDecode(json) as Map<String, dynamic>;
      return UsbSerialScannerMeta.fromJSON(m);
    }).toList();
  }

  static Future<void> saveScanner(UsbSerialScanner scanner) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> jsons = prefs.getStringList(usbSerialDevicePrefKey) ?? [];
    final meta = scanner.meta;
    final updatedJsons = jsons.where((json) {
      final m = jsonDecode(json) as Map<String, dynamic>;
      final savedMeta = UsbSerialScannerMeta.fromJSON(m);
      return savedMeta.key != meta.key;
    }).toList();
    updatedJsons.add(jsonEncode(meta.toJSON()));
    await prefs.setStringList(usbSerialDevicePrefKey, updatedJsons);
  }

  static Future<void> removeScanner(UsbSerialScanner scanner) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> jsons = prefs.getStringList(usbSerialDevicePrefKey) ?? [];
    final meta = scanner.meta;
    final updatedJsons = jsons.where((json) {
      final m = jsonDecode(json) as Map<String, dynamic>;
      final savedMeta = UsbSerialScannerMeta.fromJSON(m);
      return savedMeta.key != meta.key;
    }).toList();
    await prefs.setStringList(usbSerialDevicePrefKey, updatedJsons);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(usbSerialDevicePrefKey);
  }
}
