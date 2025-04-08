// ignore_for_file: library_private_types_in_public_api

import 'package:flutter/material.dart';
// Removed provider import
import 'package:qr_flutter/qr_flutter.dart';
import 'package:usb_serial/usb_serial.dart';

// Import the main library file to get all necessary exports
import '../../usb_serial_scanners.dart';

/// A widget that displays a QR code for validation and uses [ScannersFinder]
/// to detect and validate new USB scanners.
///
/// Requires an instance of [UsbScannerService] to be passed via the constructor.
class UsbScannerFinder extends StatefulWidget {
  const UsbScannerFinder({
    required this.scannerService, // Require the service instance
    required this.onFound,
    this.baudRate = BaudRate.b115200,
    this.suffix = Suffix.cr,
    this.validationValue = 'Hello, World!',
    this.filter,
    this.size = 200,
    super.key,
  });

  final UsbScannerService scannerService; // Service instance passed in
  final BaudRate baudRate;
  final Suffix suffix;
  final String validationValue;
  final VoidCallback onFound;
  final double size;
  final bool Function(UsbDevice)? filter;

  @override
  State<UsbScannerFinder> createState() => _UsbScannerFinderState();
}

class _UsbScannerFinderState extends State<UsbScannerFinder> {
  ScannersFinder? _scannerFinder;
  // No need to store _scannerService separately, use widget.scannerService

  @override
  void initState() {
    super.initState();
    _initializeScannerFinder(); // Initialize with the initial service instance
  }

  @override
  void didUpdateWidget(UsbScannerFinder oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-initialize if the service instance or other parameters change
    if (widget.scannerService != oldWidget.scannerService ||
        widget.baudRate != oldWidget.baudRate ||
        widget.suffix != oldWidget.suffix ||
        widget.validationValue != oldWidget.validationValue ||
        widget.filter != oldWidget.filter) {
      _stopFinder();
      _initializeScannerFinder();
    }
  }

  void _initializeScannerFinder() {
    _scannerFinder = ScannersFinder(
      scannerService: widget.scannerService, // Pass the service instance from the widget
      validationValue: widget.validationValue,
      filter: widget.filter,
      suffix: widget.suffix,
      baudRate: widget.baudRate,
      onFound: () {
        // Ensure callback happens within the widget's context if needed
        if (mounted) {
          widget.onFound();
        }
      },
    );
    _scannerFinder?.start();
  } // <--- Correct placement for the method's closing brace

  void _stopFinder() {
    // Use ?. operator for safety
     _scannerFinder?.stop();
     _scannerFinder = null;
  }

  @override
  Widget build(BuildContext context) {
    // Display QR code for the validation value
    return QrImageView(
       data: widget.validationValue,
       version: QrVersions.auto, // Use auto version
       size: widget.size,
       gapless: false, // Recommended for better readability
    );
  }

  @override
  void dispose() {
    _stopFinder(); // Ensure finder is stopped when widget is disposed
    super.dispose();
  }
}
