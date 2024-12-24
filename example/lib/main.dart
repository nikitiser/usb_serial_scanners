import 'dart:async';

import 'package:flutter/material.dart';
import 'package:usb_serial_scanners/usb_serial_scanners.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'USB Serial Scanners',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  bool mainBusy = false;

  final List<String> scannedData = [];

  final _scrollController = ScrollController();

  late final StreamSubscription<String>? _subscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() {
        mainBusy = true;
      });
      UsbSerialScannersManager.init();
      UsbSerialScannersManager.addListener(() {
        setState(() {});
      });
      UsbSerialScannersManager.restoreScanners().then((_) {
        setState(() {
          mainBusy = false;
        });
      });
    });
    _subscription = UsbSerialScannersManager.scanDataStream.listen((event) {
      scannedData.add(event);
      setState(() {});
      _scrollController.animateTo(0, duration: Duration(milliseconds: 300), curve: Curves.easeInOut);
    });
  }

  @override
  Widget build(BuildContext context) {
    return mainBusy
        ? Center(
            child: CircularProgressIndicator(),
          )
        : Scaffold(
            appBar: AppBar(
              title: const Text('Serial POS Scanners Example'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () async {
                    await _onAddScanner();
                  },
                ),
                IconButton(
                    onPressed: () async {
                      await UsbSerialScannersManager.clear();
                      setState(() {});
                    },
                    icon: Icon(Icons.delete)),
              ],
            ),
            body: Row(
              children: [
                Flexible(
                  flex: 3,
                  fit: FlexFit.loose,
                  child: ListView.builder(
                    itemCount: UsbSerialScannersManager.scanners.length,
                    itemBuilder: (context, index) {
                      final scanner = UsbSerialScannersManager.scanners[index];
                      return ListTile(
                        title: Text(scanner.device.productName ?? ''),
                        subtitle: Text(scanner.device.manufacturerName ?? ''),
                        trailing: Icon(scanner.isConnected ? Icons.usb : Icons.usb_off),
                      );
                    },
                  ),
                ),
                Flexible(
                    flex: 10,
                    child: ListView.builder(
                      itemCount: scannedData.reversed.length,
                      controller: _scrollController,
                      itemBuilder: (context, index) {
                        return ListTile(
                          title: Text(scannedData.reversed.toList()[index]),
                        );
                      },
                    )),
                UsbScannerFinder(
                  suffix: Suffix.tab,
                  onFound: () {
                    setState(() {});
                  },
                  size: 200,
                  validationValue: 'Test',
                  filter: (v) {
                    return !(v.productName ?? '').toLowerCase().contains('printer') &&
                        !v.key.toLowerCase().contains('ilitek');
                  },
                ),
              ],
            ),
          );
  }

  Future<void> _onAddScanner() async {
    await showDialog(
        context: context,
        builder: (context) => Dialog(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Please connect the scanner and scan Qr code',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    UsbScannerFinder(
                      suffix: Suffix.tab,
                      onFound: () {
                        Navigator.pop(context);
                      },
                      size: 200,
                      validationValue: 'This scanner is connected',
                      filter: (v) {
                        return !(v.productName ?? '').toLowerCase().contains('printer') &&
                            !v.key.toLowerCase().contains('ilitek');
                      },
                    ),
                  ],
                ),
              ),
            ));

    setState(() {});
  }

  @override
  void dispose() {
    _subscription?.cancel();
    UsbSerialScannersManager.removeListener(() {
      setState(() {});
    });
    super.dispose();
  }
}
