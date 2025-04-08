import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:usb_serial/usb_serial.dart';

import '../usb_serial_scanners.dart'; // Assuming UsbSerialScanner, ScannersMetaRepo etc. are exported from here
// Or import specific files like:
// import 'scanners_repo.dart';
// import 'usb_serial_scanner.dart';
// import 'usb_serial_scanner_meta.dart';
// import 'suffix.dart';
// import 'const.dart'; // Assuming usbSerialDevicePrefKey is here

/// Type definition for the error handler callback.
typedef OnScannerError = void Function(Object error, StackTrace stackTrace);

/// Service for managing USB serial scanners.
///
/// This service handles device discovery, connection, data reading,
/// and lifecycle management for USB scanners.
class UsbScannerService {
  /// Creates an instance of the scanner service.
  ///
  /// [onError]: An optional callback function to handle errors that occur
  /// within the service or during scanner operations.
  UsbScannerService({this.onError});

  /// Optional error handler provided by the user.
  final OnScannerError? onError;

  final List<UsbSerialScanner> _scanners = [];
  StreamSubscription? _usbEventSubscription;

  // Controller for broadcasting scanned data from all active scanners.
  final _scanDataController = StreamController<String>.broadcast();
  // Controller for notifying changes in the list of connected scanners.
  final _scannersUpdateController = StreamController<List<UsbSerialScanner>>.broadcast();

  bool _isInitialized = false;
  bool _isPaused = false;

  /// Stream of scanned data from all connected and active scanners.
  Stream<String> get scanDataStream => _scanDataController.stream;

  /// Stream that emits the updated list of connected scanners whenever
  /// a scanner is added or removed.
  Stream<List<UsbSerialScanner>> get scannersUpdateStream => _scannersUpdateController.stream;

  /// Gets the current list of connected scanners.
  List<UsbSerialScanner> get currentScanners => List.unmodifiable(_scanners);

  /// Initializes the service.
  ///
  /// Discovers previously saved scanners, connects to them, and starts
  /// listening for USB attach/detach events.
  /// Must be called before using other methods.
  Future<void> initialize() async {
    if (_isInitialized) {
      _handleError(Exception("UsbScannerService is already initialized."), StackTrace.current);
      return;
    }
    _isInitialized = true;
    _isPaused = false; // Start in resumed state

    await _restoreScanners();
    _startListeningUsbEvents();

    _notifyScannersUpdate(); // Notify initial list
  }

  /// Disposes the service.
  ///
  /// Disconnects all scanners, cancels subscriptions, and closes streams.
  /// Should be called when the service is no longer needed to prevent leaks.
  Future<void> dispose() async {
    if (!_isInitialized) return;

    await _usbEventSubscription?.cancel();
    _usbEventSubscription = null;

    // Create a copy of the list to avoid modification issues during iteration
    final scannersToDisconnect = List<UsbSerialScanner>.from(_scanners);
    for (final scanner in scannersToDisconnect) {
      await _disconnectScanner(scanner, removeFromList: false); // Disconnect without modifying list yet
    }
    _scanners.clear(); // Clear the list after all are disconnected

    await _scanDataController.close();
    await _scannersUpdateController.close();

    _isInitialized = false;
    if (kDebugMode) {
      print('UsbScannerService disposed.');
    }
  }

  /// Pauses listening for data from all connected scanners.
  /// Ports remain open, allowing for quick resume.
  void pauseScanners() {
    if (_isPaused) return;
    _isPaused = true;
    for (final scanner in _scanners) {
      scanner.pauseListening(); // Method to be added in UsbSerialScanner
    }
    if (kDebugMode) {
      print('Scanners paused.');
    }
  }

  /// Resumes listening for data from all connected scanners.
  void resumeScanners() {
    if (!_isPaused) return;
    _isPaused = false;
    for (final scanner in _scanners) {
      scanner.resumeListening(); // Method to be added in UsbSerialScanner
    }
    if (kDebugMode) {
      print('Scanners resumed.');
    }
  }

  /// Adds and connects a new scanner.
  ///
  /// [device]: The USB device to connect to.
  /// [suffix]: The suffix used to determine the end of a scan.
  /// Returns `true` if the scanner was added and connected successfully, `false` otherwise.
  Future<bool> addScanner({required UsbDevice device, required Suffix suffix}) async {
    if (_scanners.any((s) => s.device.key == device.key)) {
      if (kDebugMode) {
        print('Scanner ${device.productName} already added.');
      }
      return true; // Already exists, consider it success
    }

    final scanner = UsbSerialScanner(
      device: device,
      onRead: _onDataReceived, // Scanner will call this
      suffix: suffix,
      onError: _handleScannerError, // Pass error handler
    );

    try {
      final bool connected = await scanner.connect(); // connect will only open port now
      if (connected) {
        _scanners.add(scanner);
        await ScannersMetaRepo.saveScanner(scanner); // Save after successful connect
        if (!_isPaused) {
           scanner.resumeListening(); // Start listening if not paused
        }
        _notifyScannersUpdate();
        if (kDebugMode) {
          print('Scanner ${device.productName} added successfully.');
        }
        return true;
      } else {
        // Connection failed, ensure cleanup (disconnect might not be needed if connect handles it)
        await scanner.disconnect(); // Ensure port is closed if connect partially succeeded
         if (kDebugMode) {
          print('Failed to connect scanner ${device.productName}.');
        }
        return false;
      }
    } catch (e, s) {
      _handleError(e, s, 'Failed to add scanner ${device.productName}');
      // Ensure cleanup after error
      await scanner.disconnect();
      return false;
    }
  }

  /// Removes and disconnects a specific scanner.
  Future<void> removeScanner(UsbSerialScanner scanner) async {
    await _disconnectScanner(scanner, removeFromList: true);
    try {
      await ScannersMetaRepo.removeScanner(scanner);
    } catch (e, s) {
      _handleError(e, s, 'Failed to remove scanner metadata for ${scanner.device.productName}');
    }
  }

  /// Removes all scanners and clears saved metadata.
  Future<void> clearAllScanners() async {
     // Create a copy of the list to avoid modification issues during iteration
    final scannersToDisconnect = List<UsbSerialScanner>.from(_scanners);
    for (final scanner in scannersToDisconnect) {
       await _disconnectScanner(scanner, removeFromList: false); // Disconnect first
    }
     _scanners.clear(); // Clear the list

    try {
      await ScannersMetaRepo.clear();
    } catch (e, s) {
      _handleError(e, s, 'Failed to clear scanner metadata');
    }
    _notifyScannersUpdate();
     if (kDebugMode) {
      print('All scanners cleared.');
    }
  }

  /// Finds available USB serial devices, optionally filtering them.
  Future<List<UsbDevice>> findAvailableDevices({bool Function(UsbDevice)? filter}) async {
    try {
      final List<UsbDevice> devices = await UsbSerial.listDevices();
      if (kDebugMode) {
        for (var d in devices) {
          print('Found device: ${d.productName} (${d.vid}:${d.pid})');
        }
      }
      if (filter != null) {
        return devices.where(filter).toList();
      }
      return devices;
    } catch (e, s) {
      _handleError(e, s, 'Failed to list USB devices');
      return [];
    }
  }

  // --- Internal Methods ---

  void _startListeningUsbEvents() {
    try {
      _usbEventSubscription = UsbSerial.usbEventStream?.listen(
        _handleUsbEvent,
        onError: (e) {
          // It's unusual for the event stream itself to error, but handle it.
           _handleError(e, StackTrace.current, 'Error in USB event stream');
           // Consider attempting to restart listening?
           _usbEventSubscription?.cancel();
           _usbEventSubscription = null;
           // Maybe schedule a retry? For now, just log.
        },
        onDone: () {
           if (kDebugMode) {
             print('USB event stream closed.');
           }
           _usbEventSubscription = null; // Ensure it's null if stream closes
        }
      );
       if (kDebugMode) {
        print('Started listening for USB events.');
      }
    } catch (e, s) {
       _handleError(e, s, 'Failed to start listening for USB events');
    }
  }

  Future<void> _restoreScanners() async {
    if (kDebugMode) {
      print('Restoring saved scanners...');
    }
    List<UsbSerialScannerMeta> metas = [];
    try {
      metas = await ScannersMetaRepo.getSavedScannersMeta();
    } catch (e, s) {
      _handleError(e, s, 'Failed to get saved scanner metadata');
      return; // Cannot restore without metadata
    }

    if (metas.isEmpty) {
       if (kDebugMode) {
        print('No saved scanners found.');
      }
      return;
    }

    List<UsbDevice> devices = [];
    try {
      devices = await UsbSerial.listDevices();
    } catch (e, s) {
       _handleError(e, s, 'Failed to list USB devices during restore');
       return; // Cannot restore without current devices
    }

    final Map<String, UsbDevice> deviceMap = { for (var d in devices) d.key: d };

    for (final meta in metas) {
      if (deviceMap.containsKey(meta.key)) {
        final device = deviceMap[meta.key]!;
        if (kDebugMode) {
          print('Attempting to restore scanner: ${device.productName}');
        }
        // Use addScanner which handles connection, saving (redundant here but ok), and notification
        await addScanner(device: device, suffix: meta.suffix);
      } else {
         if (kDebugMode) {
          print('Saved scanner ${meta.productName} (${meta.key}) not found attached.');
        }
        // Optionally remove stale metadata here? Or leave it for manual cleanup.
        // await ScannersMetaRepo.removeScannerMetaByKey(meta.key); // Requires new method in repo
      }
    }
     if (kDebugMode) {
      print('Scanner restore process finished.');
    }
  }

  void _handleUsbEvent(UsbEvent event) async {
    if (kDebugMode) {
      print('USB Event: ${event.event}, Device: ${event.device?.productName}');
    }
    try {
      if (event.event == UsbEvent.ACTION_USB_ATTACHED) {
        if (event.device is UsbDevice) {
          final device = event.device as UsbDevice;
          // Check if it's a known/saved scanner and try to add it
          final metas = await ScannersMetaRepo.getSavedScannersMeta();
          UsbSerialScannerMeta? matchingMeta; // Make it nullable
          try {
            matchingMeta = metas.firstWhere((meta) => meta.key == device.key);
          } on StateError {
            // firstWhere throws StateError if no element is found
            matchingMeta = null;
          }

          if (matchingMeta != null) {
             if (kDebugMode) {
              print('Known scanner attached: ${device.productName}. Attempting to add...');
            }
            await addScanner(device: device, suffix: matchingMeta.suffix);
          } else {
             if (kDebugMode) {
              print('Unknown scanner attached: ${device.productName}. Ignoring.');
            }
          }
        }
      } else if (event.event == UsbEvent.ACTION_USB_DETACHED) {
        if (event.device is UsbDevice) {
          final device = event.device as UsbDevice;
          UsbSerialScanner? scanner; // Make it nullable
          try {
             scanner = _scanners.firstWhere((s) => s.device.key == device.key);
          } on StateError {
             // firstWhere throws StateError if no element is found
             scanner = null;
          }

          if (scanner != null) {
             if (kDebugMode) {
              print('Connected scanner detached: ${device.productName}. Removing...');
            }
            // Disconnect and remove from list, but keep metadata
            await _disconnectScanner(scanner, removeFromList: true);
          }
        }
      }
    } catch (e, s) {
      _handleError(e, s, 'Error handling USB event');
    }
  }

  // Called by individual UsbSerialScanner instances
  void _onDataReceived(String data) {
    if (!_scanDataController.isClosed) {
      _scanDataController.add(data);
    }
  }

   // Called by individual UsbSerialScanner instances on error
   // The scanner instance is implicitly known by the service context where this is called.
  void _handleScannerError(Object error, StackTrace stackTrace) {
     // We might not know exactly *which* scanner errored immediately here
     // unless we wrap the call site or pass more context.
     // For now, log a generic internal error. The main handler will report it.
     _handleError(error, stackTrace, 'Internal error from a scanner');
     // Decide on action: maybe try to disconnect/reconnect? Or just report?
     // For now, just report via the main handler. Consider adding auto-reconnect logic later.
     // Maybe disconnect the faulty scanner?
     // _disconnectScanner(scanner, removeFromList: true);
  }


  Future<void> _disconnectScanner(UsbSerialScanner scanner, {required bool removeFromList}) async {
    try {
      await scanner.disconnect();
       if (kDebugMode) {
        print('Disconnected scanner: ${scanner.device.productName}');
      }
    } catch (e, s) {
      _handleError(e, s, 'Error disconnecting scanner ${scanner.device.productName}');
    } finally {
       if (removeFromList) {
         final removed = _scanners.remove(scanner);
         if (removed) {
           _notifyScannersUpdate();
         }
       }
    }
  }

  void _notifyScannersUpdate() {
    if (!_scannersUpdateController.isClosed) {
      _scannersUpdateController.add(List.unmodifiable(_scanners));
    }
  }

  // Central error handling
  void _handleError(Object error, StackTrace stackTrace, [String? context]) {
    if (kDebugMode) {
      print('UsbScannerService ERROR: ${context ?? ''} | $error');
      // print(stackTrace); // Can be very verbose
    }
    if (onError != null && !_scanDataController.isClosed) { // Check stream closed status? Maybe not needed.
      try {
         onError!(error, stackTrace);
      } catch (e, s) {
         // Prevent crash if user-provided error handler fails
         if (kDebugMode) {
           print('UsbScannerService CRITICAL: User-provided onError callback failed! $e\n$s');
         }
      }
    }
  }
}
