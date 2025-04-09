import 'dart:convert';
import 'package:flutter/foundation.dart'; // For kDebugMode
import 'package:shared_preferences/shared_preferences.dart';

import '../usb_serial_scanners.dart'; // Assuming UsbSerialScannerMeta and usbSerialDevicePrefKey are here

class ScannersMetaRepo {
  static Future<List<UsbSerialScannerMeta>> getSavedScannersMeta() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> jsons = prefs.getStringList(usbSerialDevicePrefKey) ?? [];
    final List<UsbSerialScannerMeta> metas = [];
    for (final json in jsons) {
      try {
        final m = jsonDecode(json) as Map<String, dynamic>;
        metas.add(UsbSerialScannerMeta.fromJSON(m));
      } on FormatException catch (e) {
        // Log the error and skip the invalid entry
        if (kDebugMode) {
          print('ScannersMetaRepo ERROR: Failed to decode saved scanner meta: $e');
          print('Invalid JSON string: $json');
          // Consider reporting this via a more robust logging mechanism or the service's error handler if possible
        }
        // Optionally remove the invalid entry here?
        // await _removeInvalidJsonEntry(prefs, json);
      } catch (e) {
        // Catch other potential errors during fromJSON conversion
         if (kDebugMode) {
          print('ScannersMetaRepo ERROR: Failed to process saved scanner meta: $e');
          print('JSON string: $json');
        }
      }
    }
    return metas;
  }

  static Future<void> saveScanner(UsbSerialScanner scanner) async {
    final prefs = await SharedPreferences.getInstance();
    // final prefs = await SharedPreferences.getInstance(); // Remove duplicate line
    final List<String> jsons = prefs.getStringList(usbSerialDevicePrefKey) ?? [];
    final meta = scanner.meta;
    final List<String> updatedJsons = [];
    bool found = false;

    for (final json in jsons) {
       try {
         final m = jsonDecode(json) as Map<String, dynamic>;
         final savedMeta = UsbSerialScannerMeta.fromJSON(m);
         if (savedMeta.key == meta.key) {
           // Update existing entry
           updatedJsons.add(jsonEncode(meta.toJSON()));
           found = true;
         } else {
           updatedJsons.add(json); // Keep other entries
         }
       } on FormatException {
         // Skip invalid entries during save/update as well
         if (kDebugMode) {
           print('ScannersMetaRepo WARNING: Skipping invalid JSON during save: $json');
         }
       } catch (e) {
          // Skip other errors during processing
          if (kDebugMode) {
           print('ScannersMetaRepo WARNING: Skipping entry due to error during save: $e');
         }
       }
    }

    if (!found) {
       // Add new entry if it wasn't an update
       updatedJsons.add(jsonEncode(meta.toJSON()));
    }

    await prefs.setStringList(usbSerialDevicePrefKey, updatedJsons);
  }

  static Future<void> removeScanner(UsbSerialScanner scanner) async {
    final prefs = await SharedPreferences.getInstance();
    // final prefs = await SharedPreferences.getInstance(); // Remove duplicate line
    final List<String> jsons = prefs.getStringList(usbSerialDevicePrefKey) ?? [];
    final meta = scanner.meta;
    final List<String> updatedJsons = [];

    for (final json in jsons) {
       try {
         final m = jsonDecode(json) as Map<String, dynamic>;
         final savedMeta = UsbSerialScannerMeta.fromJSON(m);
         if (savedMeta.key != meta.key) {
            updatedJsons.add(json); // Keep only entries that don't match
         }
       } on FormatException {
          // Keep invalid entries when removing others? Or skip? Let's skip.
          if (kDebugMode) {
           print('ScannersMetaRepo WARNING: Skipping invalid JSON during remove: $json');
         }
       } catch (e) {
          // Skip other errors during processing
          if (kDebugMode) {
           print('ScannersMetaRepo WARNING: Skipping entry due to error during remove: $e');
         }
       }
    }

    // Only write if the list actually changed (though setStringList handles this)
    if (updatedJsons.length != jsons.length) {
       await prefs.setStringList(usbSerialDevicePrefKey, updatedJsons);
    }
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(usbSerialDevicePrefKey);
  }
}
