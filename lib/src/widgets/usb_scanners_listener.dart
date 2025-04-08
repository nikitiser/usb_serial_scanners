// ignore_for_file: library_private_types_in_public_api

import 'dart:async';

import 'package:flutter/material.dart';
// Removed provider import

import '../../usb_serial_scanners.dart'; // Imports UsbScannerService

/// Listens to the scan data stream from the provided [UsbScannerService]
/// instance and calls [onScan].
class UsbScannersListener extends StatefulWidget {
  const UsbScannersListener({
    super.key,
    required this.scannerService, // Require the service instance
    required this.child,
    required this.onScan,
  });

  final UsbScannerService scannerService; // Service instance passed in
  final Widget child;
  final Function(String) onScan;

  @override
  State<UsbScannersListener> createState() => _UsbScannersListenerState();
}

class _UsbScannersListenerState extends State<UsbScannersListener> {
  StreamSubscription<String>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscribe(); // Subscribe with the initial service instance
  }

  @override
  void didUpdateWidget(UsbScannersListener oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the provided service instance changes, re-subscribe
    if (widget.scannerService != oldWidget.scannerService) {
      _unsubscribe();
      _subscribe();
    }
  }

  void _subscribe() {
    try {
      _subscription = widget.scannerService.scanDataStream.listen(
        (data) {
          // Use mounted check for safety in async callbacks
          if (mounted) {
            widget.onScan(data);
          }
        },
        onError: (error, stackTrace) {
          // Optionally handle stream errors, e.g., log them
          print('UsbScannersListener ERROR: Error in scanDataStream: $error');
          // Use the service's error handler if available
          widget.scannerService.onError?.call(error, stackTrace);
        }
      );
    } catch (e, s) {
      // Catch potential errors during subscription itself
      print('UsbScannersListener ERROR: Failed to subscribe to scanDataStream: $e');
      widget.scannerService.onError?.call(e, s);
    }
  }

  void _unsubscribe() {
    _subscription?.cancel();
    _subscription = null;
  }


  @override
  void dispose() {
    _unsubscribe(); // Ensure cancellation on dispose
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
