import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:usb_serial/usb_serial.dart';

import '../usb_serial_scanners.dart';

class UsbSerialScanner {
  UsbSerialScanner({
    required this.device,
    required this.onRead,
    required this.suffix,
    this.timeoutForRead = const Duration(milliseconds: 100),
    this.timeoutForConnect = const Duration(seconds: 1),
  });

  final UsbDevice device;
  final Function(String) onRead;

  Suffix suffix;
  Duration timeoutForRead;
  Duration timeoutForConnect;

  UsbPort? _port;
  StreamSubscription<List<int>>? _subscription;
  String _buffer = '';
  Timer? _dataTimer;

  BaudRate _baudRate = BaudRate.b115200;
  BaudRate get baudRate => _baudRate;

  bool get isConnected => _port != null;

  UsbSerialScannerMeta get meta => UsbSerialScannerMeta(
        productName: device.productName,
        manufacturerName: device.manufacturerName,
        vid: device.vid,
        pid: device.pid,
        serial: device.serial,
        baudRate: _baudRate.value,
        suffix: suffix,
      );

  Future<bool> setBaudRate(BaudRate value) async {
    if (_baudRate != value) {
      _baudRate = value;
      await disconnect();
      return connect();
    } else {
      return true;
    }
  }

  Future<bool> connect({BaudRate? boudRate}) async {
    try {
      if (boudRate != null) {
        _baudRate = boudRate;
      }
      _port = await device.create().timeout(
            timeoutForConnect,
            onTimeout: () => null,
          );
      if (_port == null || !await _port!.open().timeout(timeoutForConnect, onTimeout: () => false)) {
        return false;
      }

      await _port!.setPortParameters(
        _baudRate.value,
        UsbPort.DATABITS_8,
        UsbPort.STOPBITS_1,
        UsbPort.PARITY_NONE,
      );
      await _port!.setDTR(true);
      await _port!.setRTS(true);

      _startListening();
      await save();
    } catch (e, s) {
      if (kDebugMode) {
        print('UsbSerialScanner: $e $s');
      }
      return false;
    }
    return true;
  }

  void _startListening() {
    _subscription?.cancel();
    _subscription = _port?.inputStream?.listen(
      (data) => _handleData(data),
      onError: (error) => disconnect(),
    );
  }

  void _handleData(List<int> data) {
    _buffer += String.fromCharCodes(data);
    if (kDebugMode) {
      print('UsbSerialScanner: $_buffer');
    }
    bool isComplete = false;
    switch (suffix) {
      case Suffix.cr: // Carriage return (CR)
        isComplete = _buffer.endsWith(suffix.value);
      case Suffix.crlf: // Carriage return + Line feed (CR&LF)
        isComplete = _buffer.endsWith(suffix.value);
      case Suffix.tab: // Tab (TAB)
        isComplete = _buffer.endsWith(suffix.value);
      case Suffix.none: // No suffix
        isComplete = _buffer.isNotEmpty;
    }

    if (isComplete) {
      _dataTimer?.cancel();
      onRead(_buffer);
      _buffer = '';
    } else {
      _dataTimer?.cancel();
      _dataTimer = Timer(timeoutForRead, () {
        onRead(_buffer);
        _buffer = '';
      });
    }
  }

  Future<void> disconnect() async {
    await _subscription?.cancel();
    await _port?.close();
    _subscription = null;
    _port = null;
    _dataTimer?.cancel();
  }

  Future<void> save() async {
    await ScannersMetaRepo.saveScanner(this);
  }
}
