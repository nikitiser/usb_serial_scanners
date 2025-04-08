import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:usb_serial/usb_serial.dart';

import '../usb_serial_scanners.dart';

/// Type definition for the error handler callback within a specific scanner.
/// The service's internal handler will know which scanner caused the error.
typedef OnScannerInternalError = void Function(Object error, StackTrace stackTrace);

class UsbSerialScanner {
  UsbSerialScanner({
    required this.device,
    required this.onRead, // This will be called by the service
    this.onError, // Add the onError callback
    required this.suffix,
    this.timeoutForRead = const Duration(milliseconds: 100),
    this.timeoutForConnect = const Duration(seconds: 1),
  });

  final UsbDevice device;
  final Function(String) onRead; // Callback provided by UsbScannerService
  final OnScannerInternalError? onError; // Callback provided by UsbScannerService

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

      // Do not start listening immediately, service will call resumeListening()
      // Do not save here, service will save after successful connection
    } catch (e, s) {
      // Report error if connect fails internally
      _handleError(e, s, 'Error during connect');
      // Ensure port is closed if something failed after creation/opening
      await _port?.close();
      _port = null;
      if (kDebugMode) {
        print('UsbSerialScanner: $e $s');
      }
      return false;
    }
    return true;
  }

  // Internal method to start or resume the stream subscription
  void _startOrResumeListening() {
    if (_subscription != null) {
      if (_subscription!.isPaused) {
        _subscription!.resume();
         if (kDebugMode) {
           print('Resumed listening for ${device.productName}');
         }
      }
      return; // Already listening or resumed
    }

    if (_port == null || _port?.inputStream == null) {
       _handleError(Exception('Port not open or input stream unavailable'), StackTrace.current, 'Cannot start listening');
       return;
    }

    _subscription = _port!.inputStream!.listen(
      (data) => _handleData(data),
      onError: (error, stackTrace) {
         _handleError(error, stackTrace ?? StackTrace.current, 'Error in input stream');
         // Consider attempting to disconnect/reconnect or just report
         disconnect(); // Disconnect on stream error for now
      },
      onDone: () {
         if (kDebugMode) {
           print('Input stream closed for ${device.productName}');
         }
         // Port or stream closed externally? Treat as disconnect.
         disconnect();
      }
    );
     if (kDebugMode) {
       print('Started listening for ${device.productName}');
     }
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
      final dataToSend = _buffer.trim(); // Get data before clearing
      _buffer = ''; // Clear buffer immediately
      try {
         onRead(dataToSend); // Call the service's callback
      } catch (e, s) {
         // Catch errors in the callback provided by the service
         _handleError(e, s, 'Error in onRead callback');
      }
    } else {
      _dataTimer?.cancel();
      _dataTimer = Timer(timeoutForRead, () {
        final dataToSend = _buffer.trim(); // Get data before clearing
        _buffer = ''; // Clear buffer immediately
        if (dataToSend.isNotEmpty) {
           try {
             onRead(dataToSend); // Call the service's callback
           } catch (e, s) {
             // Catch errors in the callback provided by the service
             _handleError(e, s, 'Error in onRead callback (timer)');
           }
        }
      });
    }
  }

  /// Pauses listening to the input stream.
  void pauseListening() {
    if (_subscription != null && !_subscription!.isPaused) {
      _subscription!.pause();
       if (kDebugMode) {
         print('Paused listening for ${device.productName}');
       }
    }
     _dataTimer?.cancel(); // Cancel timer when pausing
  }

  /// Resumes listening to the input stream.
  void resumeListening() {
     _startOrResumeListening(); // Handles both starting and resuming
  }


  Future<void> disconnect() async {
    _dataTimer?.cancel();
    _dataTimer = null;
    // Cancel subscription first
    await _subscription?.cancel();
    _subscription = null;
    // Then close the port
    await _port?.close();
    _port = null;
     if (kDebugMode) {
       print('Disconnected internal resources for ${device.productName}');
     }
  }

  // Central internal error handling
  void _handleError(Object error, StackTrace stackTrace, [String? context]) {
     if (kDebugMode) {
       print('UsbSerialScanner ERROR: ${device.productName} - ${context ?? ''} | $error');
     }
     // Call the service's error handler if provided (without passing 'this')
     onError?.call(error, stackTrace);
  }

  // Removed save() method - service handles saving.
}
