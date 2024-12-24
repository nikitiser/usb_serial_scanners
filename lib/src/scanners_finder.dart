import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:usb_serial/usb_serial.dart';

import '../usb_serial_scanners.dart';

class ScannersFinder {
  final String validationValue;
  final Suffix suffix;
  final BaudRate baudRate;
  final bool Function(UsbDevice)? filter;
  final VoidCallback onFound;

  ScannersFinder({
    required this.validationValue,
    required this.suffix,
    required this.onFound,
    this.filter,
    this.baudRate = BaudRate.b115200,
  });

  final List<UsbSerialScanner> _scanners = [];

  bool _isRunning = false;

  bool get isRanning => _isRunning;

  StreamSubscription? _usbEventStream;

  Future<void> start() async {
    if (_isRunning) {
      return;
    } else {
      _isRunning = true;
    }
    _usbEventStream = UsbSerial.usbEventStream?.listen(_eventHandler);
    final devices = await UsbSerialScannersManager.getUsbSerialDevicesWithFilter(filter: (v) {
      return (filter != null ? filter!(v) : true) &&
          !UsbSerialScannersManager.scanners.any((s) => s.device.key == v.key);
    });
    if (kDebugMode) {
      for (final device in devices) {
        print(
            'ScannersFinder: ${device.deviceName} ${device.manufacturerName} ${device.vid} ${device.pid} ${device.serial}');
      }
    }
    for (final device in devices) {
      final scanner = UsbSerialScanner(
          device: device,
          onRead: (v) {
            _onDataReceived(v, device);
          },
          suffix: suffix);
      final res = await scanner.connect(boudRate: baudRate);
      if (res) {
        _scanners.add(scanner);
      } else {
        await scanner.disconnect();
      }
    }
    if (kDebugMode) {
      print('Connected scanners: ${UsbSerialScannersManager.scanners.length} scanners');
      print('ScannersFinder: ${_scanners.length} scanners found');
    }
  }

  Future<void> _onDataReceived(String data, UsbDevice device) async {
    if (data.contains(validationValue)) {
      if (UsbSerialScannersManager.scanners.any((s) => s.device.key == device.key)) {
        final scanner = UsbSerialScannersManager.scanners.firstWhere((s) => s.device.key == device.key);
        scanner.onRead('This scanner is already added');
      } else {
        await UsbSerialScannersManager.addScanner(device: device, suffix: suffix);
        onFound();
      }
    }
  }

  Future<void> stop() async {
    for (final scanner in _scanners) {
      await scanner.disconnect();
    }
    _scanners.clear();
    _isRunning = false;
    await _usbEventStream?.cancel();
  }

  Future<void> _eventHandler(UsbEvent event) async {
    if (event.event == UsbEvent.ACTION_USB_ATTACHED) {
      if (event.device is UsbDevice) {
        final device = event.device as UsbDevice;
        if (_scanners.any((s) => s.device.key == device.key)) {
          _scanners.removeWhere((s) => s.device.key == device.key);
        }
        final metas = await ScannersMetaRepo.getSavedScannersMeta();
        if (metas.any((meta) => meta.key == device.key)) {
          final suffix = metas.firstWhere((meta) => meta.key == device.key).suffix;
          _scanners.add(UsbSerialScanner(
            device: device,
            onRead: (v) async => await _onDataReceived(v, device),
            suffix: suffix,
          ));
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
  }
}
