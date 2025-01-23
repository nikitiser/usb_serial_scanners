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
  StreamSubscription<String>? _subscription;
  static StreamController<String>? _controller;
  static int _listenerCount = 0;

  @override
  void initState() {
    super.initState();
    _startListening();
  }

  void _startListening() {
    if (_controller == null || _controller!.isClosed) {
      _controller = StreamController<String>.broadcast(
        onListen: () {
          _listenerCount++;
          debugPrint("UsbScannersListener count: $_listenerCount");
        },
        onCancel: () {
          _listenerCount--;
          debugPrint("UsbScannersListener count: $_listenerCount");
          if (_listenerCount == 0) {
            _controller!.close();
            _controller = null;
          }
        },
      );

      // Перенаправляем данные из оригинального потока в наш контроллер
      UsbSerialScannersManager.scanDataStream.listen((data) {
        if (_controller != null && !_controller!.isClosed) {
          _controller!.add(data);
        }
      });
    }

    _subscription = _controller!.stream.listen((data) {
      widget.onScan(data);
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
