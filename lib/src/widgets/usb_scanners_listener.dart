import 'dart:async';

import 'package:flutter/material.dart';

import '../../usb_serial_scanners.dart';

class UsbScannersListener extends StatefulWidget {
  const UsbScannersListener({
    super.key,
    required this.child,
    required this.onScan,
  });

  final Widget child;
  final Function(String) onScan;

  @override
  State<UsbScannersListener> createState() => _UsbScannersListenerState();
}

class _UsbScannersListenerState extends State<UsbScannersListener> {
  late StreamSubscription<String> _subscription;

  @override
  void initState() {
    super.initState();
    _startListening();
  }

  void _startListening() {
    _subscription = UsbSerialScannersManager.scanDataStream.listen((data) {
      widget.onScan(data);
    });
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
