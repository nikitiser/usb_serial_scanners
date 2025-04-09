import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:usb_serial/usb_serial.dart'; // Keep for UsbDevice

import '../usb_serial_scanners.dart'; // Imports UsbScannerService, UsbSerialScanner, etc.

/// Finds and validates new USB scanners by listening for a specific value.
class ScannersFinder {
  final UsbScannerService _scannerService; // Inject the service
  final String validationValue;
  final Suffix suffix;
  final BaudRate baudRate;
  final bool Function(UsbDevice)? filter;
  final VoidCallback onFound;
  final OnScannerError? _onError; // Optional error handler from service

  ScannersFinder({
    required UsbScannerService scannerService, // Require the service instance
    required this.validationValue,
    required this.suffix,
    required this.onFound,
    this.filter,
    this.baudRate = BaudRate.b115200,
  }) : _scannerService = scannerService,
       _onError = scannerService.onError; // Use service's error handler

  // List to hold temporary scanners used ONLY for validation
  final List<UsbSerialScanner> _validationScanners = [];

  bool _isRunning = false;
  bool get isRunning => _isRunning; // Corrected typo

  // USB event stream specifically for the finder while it's active
  StreamSubscription? _usbEventSubscription;

  /// Starts the finder process.
  /// Connects temporarily to available, unmanaged devices to listen for the validation value.
  Future<void> start() async {
    if (_isRunning) return;
    _isRunning = true;

    if (kDebugMode) print('ScannersFinder starting...');

    // Start listening for USB events *while* the finder is active
    _usbEventSubscription = UsbSerial.usbEventStream?.listen(
       _handleUsbEvent,
       onError: (e, s) => _handleError(e, s ?? StackTrace.current, 'Finder USB Event Stream Error')
    );

    // Get currently available devices *at start time*
    final availableDevices = await _scannerService.findAvailableDevices(filter: filter);

    // Filter out devices already managed by the service
    final managedDeviceKeys = _scannerService.currentScanners.map((s) => s.device.key).toSet();
    final devicesToValidate = availableDevices.where((d) => !managedDeviceKeys.contains(d.key)).toList();

    if (kDebugMode) {
      print('ScannersFinder: Found ${devicesToValidate.length} unmanaged devices to validate.');
      for (final device in devicesToValidate) {
        // Removed nested print
        print('  - ${device.productName} (${device.vid}:${device.pid})');
      }
    }

    // Try to connect to each validation candidate
    for (final device in devicesToValidate) {
      // Check again if it was added by the service in the meantime (unlikely but possible)
       if (_scannerService.currentScanners.any((s) => s.device.key == device.key)) {
         continue;
       }

      final validationScanner = UsbSerialScanner(
        device: device,
        suffix: suffix,
        // Pass validation handler and error handler
        onRead: (data) => _handleValidationData(data, device),
        onError: _handleValidationError,
      );

      try {
        final connected = await validationScanner.connect(boudRate: baudRate);
        if (connected) {
          validationScanner.resumeListening(); // Start listening for validation data
          _validationScanners.add(validationScanner);
           if (kDebugMode) print('ScannersFinder: Temporarily connected to ${device.productName} for validation.');
        } else {
           if (kDebugMode) print('ScannersFinder: Failed to temporarily connect to ${device.productName}.');
           await validationScanner.disconnect(); // Ensure cleanup
        }
      } catch (e) {
         // Don't propagate temporary connection errors, just log for debug
         if (kDebugMode) print('ScannersFinder DEBUG: Error connecting validation scanner ${device.productName}: $e');
         // _handleError(e, s, 'Error connecting validation scanner ${device.productName}'); // REMOVED
         await validationScanner.disconnect(); // Ensure cleanup
      }
    }
     if (kDebugMode) print('ScannersFinder: Started validation for ${_validationScanners.length} scanners.');
  }


  /// Handles USB attach/detach events while the finder is running.
  void _handleUsbEvent(UsbEvent event) async {
     if (!_isRunning) return; // Ignore events if finder stopped

     if (event.event == UsbEvent.ACTION_USB_ATTACHED && event.device is UsbDevice) {
        final device = event.device as UsbDevice;
        if (kDebugMode) print('ScannersFinder: Detected ATTACH event for ${device.productName}');

        // Check conditions: Not managed, not already validating, passes filter
        final isManaged = _scannerService.currentScanners.any((s) => s.device.key == device.key);
        final isValidating = _validationScanners.any((s) => s.device.key == device.key);
        final passesFilter = filter?.call(device) ?? true;

        if (!isManaged && !isValidating && passesFilter) {
           if (kDebugMode) print('ScannersFinder: New relevant device attached (${device.productName}). Attempting validation...');
           // Try to connect and add for validation (similar logic as in start())
           final validationScanner = UsbSerialScanner(
             device: device,
             suffix: suffix,
             onRead: (data) => _handleValidationData(data, device),
             onError: _handleValidationError,
           );
           try {
             final connected = await validationScanner.connect(boudRate: baudRate);
             if (connected) {
               validationScanner.resumeListening();
               _validationScanners.add(validationScanner);
               if (kDebugMode) print('ScannersFinder: Added ${device.productName} for validation due to attach event.');
             } else {
                await validationScanner.disconnect();
             }
           } catch (e) {
              // Don't propagate temporary connection errors, just log for debug
              if (kDebugMode) print('ScannersFinder DEBUG: Error connecting validation scanner ${device.productName} after attach: $e');
              // _handleError(e, s, 'Error connecting validation scanner ${device.productName} after attach'); // REMOVED
              await validationScanner.disconnect();
           }
        } else {
           if (kDebugMode) print('ScannersFinder: Ignoring attached device ${device.productName} (Managed: $isManaged, Validating: $isValidating, Filter: $passesFilter)');
        }

     } else if (event.event == UsbEvent.ACTION_USB_DETACHED && event.device is UsbDevice) {
        final device = event.device as UsbDevice;
         if (kDebugMode) print('ScannersFinder: Detected DETACH event for ${device.productName}');
        // Remove from validation list if it was being validated
        UsbSerialScanner? validationScanner;
        try {
           validationScanner = _validationScanners.firstWhere((s) => s.device.key == device.key);
        } on StateError {
           validationScanner = null; // Not found
        }

        if (validationScanner != null) {
           if (kDebugMode) print('ScannersFinder: Removing ${device.productName} from validation due to detach event.');
           await validationScanner.disconnect();
           _validationScanners.remove(validationScanner);
        }
     }
  }


  /// Handles data received from a temporary validation scanner.
  void _handleValidationData(String data, UsbDevice device) async {
    if (kDebugMode) print('ScannersFinder: Received validation data "$data" from ${device.productName}');

    if (data.trim() == validationValue.trim()) { // Trim both for safety
      if (kDebugMode) print('ScannersFinder: Validation SUCCESS for ${device.productName}');

      // Stop this validation scanner
      UsbSerialScanner? validationScanner;
       try {
          validationScanner = _validationScanners.firstWhere((s) => s.device.key == device.key);
       } on StateError {
          validationScanner = null; // Not found (might have been detached concurrently)
       }

      if (validationScanner != null) {
         await validationScanner.disconnect();
         _validationScanners.remove(validationScanner);
      }

      // Check if the service has already added it (e.g., via USB event)
      if (_scannerService.currentScanners.any((s) => s.device.key == device.key)) {
         if (kDebugMode) print('ScannersFinder: ${device.productName} was already added by the service.');
         // Optionally notify user?
      } else {
         // Add the scanner permanently via the service
         if (kDebugMode) print('ScannersFinder: Adding ${device.productName} to the service...');
         final added = await _scannerService.addScanner(device: device, suffix: suffix);
         if (added) {
           onFound(); // Call the user's callback
         } else {
            _handleError(Exception('Failed to add validated scanner via service'), StackTrace.current, device.productName);
         }
      }
       // Potentially stop the finder if only one scanner is expected? Or keep running?
       // stop(); // Example: stop after first successful validation
    }
  }

   /// Handles errors from a temporary validation scanner.
   // Corrected signature - scanner instance is not passed here anymore.
  void _handleValidationError(Object error, StackTrace stackTrace) {
     // Log validation errors only in debug mode, do not propagate to the main error handler.
     if (kDebugMode) {
        print('ScannersFinder DEBUG: Error during scanner validation: $error');
     }
     // _handleError(error, stackTrace, 'Error during scanner validation'); // REMOVED - Do not call main handler
     // We cannot easily identify *which* validation scanner failed here without more context.
     // Consider stopping the finder or logging more details if this happens frequently.
     // Cannot disconnect/remove the specific scanner without its instance.
  }


  /// Stops the finder process and disconnects all temporary validation scanners.
  Future<void> stop() async {
    if (!_isRunning) return;
    if (kDebugMode) print('ScannersFinder stopping...');

    // Create a copy to avoid modification issues
    final scannersToStop = List<UsbSerialScanner>.from(_validationScanners);
    for (final scanner in scannersToStop) {
      try {
        await scanner.disconnect();
      } catch (e, s) {
         _handleError(e, s, 'Error disconnecting validation scanner ${scanner.device.productName} during stop');
      }
    }
    _validationScanners.clear();
    _isRunning = false;
    // Cancel USB event subscription when stopping
    await _usbEventSubscription?.cancel();
    _usbEventSubscription = null;
     if (kDebugMode) print('ScannersFinder stopped.');
  }

   // Central internal error handling for the finder
  void _handleError(Object error, StackTrace stackTrace, [String? context]) {
    if (kDebugMode) {
      print('ScannersFinder ERROR: ${context ?? ''} | $error');
    }
    // Use the service's error handler if available
    _onError?.call(error, stackTrace);
  }

  // _handleUsbEvent added above to handle attach/detach while finder is active.
}
