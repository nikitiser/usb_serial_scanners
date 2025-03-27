import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:usb_serial/usb_serial.dart';

import '../usb_serial_scanners.dart';

class UsbSerialScannersManager {
  static final List<UsbSerialScanner> _scanners = [];

  static List<UsbSerialScanner> get scanners => _scanners;

  static final StreamController<String> _streamController = StreamController<String>.broadcast();

  static Stream<String> get scanDataStream => _streamController.stream;

  static StreamSubscription? usbEventStream;

  static final List<VoidCallback> listeners = [];

  static void _eventHandler(UsbEvent event) async {
    if (event.event == UsbEvent.ACTION_USB_ATTACHED) {
      if (event.device is UsbDevice) {
        final device = event.device as UsbDevice;
        if (_scanners.any((s) => s.device.key == device.key)) {
          _scanners.removeWhere((s) => s.device.key == device.key);
        }
        final metas = await ScannersMetaRepo.getSavedScannersMeta();
        if (metas.any((meta) => meta.key == device.key)) {
          final suffix = metas.firstWhere((meta) => meta.key == device.key).suffix;
          await addScanner(device: device, suffix: suffix);
        }
      }
    } else if (event.event == UsbEvent.ACTION_USB_DETACHED) {
      if (event.device is UsbDevice) {
        final device = event.device as UsbDevice;
        if (_scanners.any((s) => s.device.key == device.key)) {
          final scanner = _scanners.firstWhere((s) => s.device.key == device.key);
          await scanner.disconnect();
          _scanners.remove(scanner);
        }
      }
    }
    notifylisteners();
  }

  static Future<void> init() async {
    usbEventStream = UsbSerial.usbEventStream?.listen(_eventHandler);
  }

  static void _onDataReceived(String data) {
    _streamController.add(data);
  }

  static Future<void> restoreScanners() async {
    if (_scanners.isNotEmpty) {
      for (final scanner in _scanners) {
        await scanner.disconnect();
      }
      _scanners.clear();
    }
    final List<UsbSerialScannerMeta> metas = await ScannersMetaRepo.getSavedScannersMeta();
    final List<UsbDevice> devices = await getUsbSerialDevicesWithFilter(filter: (device) {
      return metas.any((meta) => meta.key == device.key);
    });
    for (final device in devices) {
      await addScanner(device: device, suffix: metas.firstWhere((meta) => meta.key == device.key).suffix);
    }
    notifylisteners();
  }

  static Future<bool> addScanner({required UsbDevice device, required Suffix suffix}) async {
    final scanner = UsbSerialScanner(device: device, onRead: _onDataReceived, suffix: suffix);
    final res = await scanner.connect();
    if (res) {
      _scanners.add(scanner);
    } else {
      await scanner.disconnect();
    }
    notifylisteners();
    return res;
  }

  static Future<List<UsbDevice>> getUsbSerialDevicesWithFilter({required bool Function(UsbDevice)? filter}) async {
    final List<UsbDevice> devices = await UsbSerial.listDevices();
    if (kDebugMode) {
      for (final device in devices) {
        print('getUsbSerialDevicesWithFilter: ${device.toString()}');
      }
    }
    if (filter != null) {
      return devices.where(filter).toList();
    }
    return devices;
  }

  static Future<void> clear() async {
    for (final scanner in _scanners) {
      await scanner.disconnect();
    }
    _scanners.clear();
    await ScannersMetaRepo.clear();
    notifylisteners();
  }

  static Future<void> removeScanner(UsbSerialScanner scanner) async {
    await scanner.disconnect();
    _scanners.removeWhere((s) => s.device.key == scanner.device.key);
    await ScannersMetaRepo.removeScanner(scanner);
    notifylisteners();
  }

  static void notifylisteners() {
    for (var element in listeners) {
      element();
    }
  }

  static void addListener(VoidCallback listener) {
    listeners.add(listener);
  }

  static void removeListener(VoidCallback listener) {
    listeners.remove(listener);
  }
}
