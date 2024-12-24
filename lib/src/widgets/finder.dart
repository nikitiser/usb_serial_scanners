import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:usb_serial/usb_serial.dart';
import 'package:usb_serial_scanners/src/baud_rate.dart';
import 'package:usb_serial_scanners/src/scanners_finder.dart';
import 'package:usb_serial_scanners/src/suffix.dart';

class UsbScannerFinder extends StatefulWidget {
  const UsbScannerFinder({
    required this.onFound,
    this.baudRate = BaudRate.b115200,
    this.suffix = Suffix.cr,
    this.validationValue = 'Hello, World!',
    this.filter,
    this.size = 200,
    super.key,
  });

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
  late ScannersFinder _scannerFinder;

  @override
  void initState() {
    super.initState();
    _initializeScannerFinder();
  }

  @override
  void didUpdateWidget(UsbScannerFinder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.baudRate != widget.baudRate || oldWidget.suffix != widget.suffix) {
      _scannerFinder.stop();
      _initializeScannerFinder();
    }
  }

  void _initializeScannerFinder() {
    _scannerFinder = ScannersFinder(
      validationValue: widget.validationValue,
      filter: widget.filter,
      suffix: widget.suffix,
      baudRate: widget.baudRate,
      onFound: widget.onFound,
    );
    _scannerFinder.start();
  }

  @override
  Widget build(BuildContext context) {
    return QrImageView(data: widget.validationValue, size: widget.size);
  }

  @override
  void dispose() {
    _scannerFinder.stop();
    super.dispose();
  }
}
