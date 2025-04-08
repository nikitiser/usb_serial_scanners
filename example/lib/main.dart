import 'dart:async';
import 'dart:math'; // For random string generation

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart'; // Import for QrImageView
import 'package:usb_serial_scanners/usb_serial_scanners.dart';

void main() {
  // It's better to initialize and provide the service higher up if possible,
  // e.g., using Provider or get_it in main(). For simplicity here,
  // we'll manage it within MyHomePageState.
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
  final List<String> scannedData = [];
  final _scrollController = ScrollController();

  // Instance of the service
  late final UsbScannerService _scannerService;
  // Subscription to scanner list updates
  StreamSubscription? _scannersUpdateSubscription;
  // Current list of scanners
  List<UsbSerialScanner> _currentScanners = [];
  // State for random QR code
  String _randomQrData = _generateRandomString();
  // State for pause/resume status
  bool _isPaused = false; // Track pause state for UI feedback

  // Helper to generate random string
  static String _generateRandomString({int length = 10}) {
    const chars = 'AaBbCcDdEeFfGgHhIiJjKkLlMmNnOoPpQqRrSsTtUuVvWwXxYyZz1234567890';
    final rnd = Random();
    return String.fromCharCodes(Iterable.generate(
        length, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))));
  }

  void _regenerateQrCode() {
     setState(() {
       _randomQrData = _generateRandomString();
     });
  }

   void _togglePauseResume() {
     if (_isPaused) {
       _scannerService.resumeScanners();
     } else {
       _scannerService.pauseScanners();
     }
     setState(() {
       _isPaused = !_isPaused; // Update UI state
     });
   }


  @override
  void initState() {
    super.initState();
    // Create and initialize the service
    _scannerService = UsbScannerService(onError: _handleServiceError);
    _initializeService();
  }

  Future<void> _initializeService() async {
    await _scannerService.initialize();
    // Subscribe to scanner list updates
    _scannersUpdateSubscription = _scannerService.scannersUpdateStream.listen(
      (scanners) {
        if (mounted) {
          setState(() {
            _currentScanners = scanners;
          });
        }
      },
      onError: (e, s) => _handleServiceError(e, s, "Scanner Update Stream Error"),
    );
    // Get initial list
    if (mounted) {
       setState(() {
         _currentScanners = _scannerService.currentScanners;
       });
     }
  }

  // Corrected signature: context string is just for logging here
  void _handleServiceError(Object error, StackTrace stackTrace, [String? logContext]) {
     print("EXAMPLE APP ERROR: ${logContext ?? 'Scanner Service Error'} | $error");
     // Show a snackbar or dialog to the user
     if (mounted) {
        // Use the widget's context
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text('Scanner Error: $error'), backgroundColor: Colors.red),
        );
     }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Serial POS Scanners Example'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add Scanner',
            onPressed: _onAddScanner, // No need for async here if dialog handles it
          ),
           // Add Pause/Resume Button
           IconButton(
             icon: Icon(_isPaused ? Icons.play_arrow : Icons.pause),
             tooltip: _isPaused ? 'Resume Listening' : 'Pause Listening',
             onPressed: _togglePauseResume,
           ),
          IconButton(
              tooltip: 'Clear All Scanners',
              onPressed: () async {
                // Use the service instance
                await _scannerService.clearAllScanners();
                // No need for setState, stream subscription handles updates
              },
              icon: const Icon(Icons.delete)),
        ],
      ),
      body: Row(
        children: [
          // Scanner List Panel
          Flexible(
            flex: 4,
            fit: FlexFit.loose,
            child: ListView.builder(
              // Use the state variable updated by the stream
              itemCount: _currentScanners.length,
              itemBuilder: (context, index) {
                final scanner = _currentScanners[index];
                return ListTile(
                  title: Text(scanner.device.productName ?? 'Unknown Device'),
                  subtitle: Text(scanner.device.manufacturerName ?? 'Unknown Manufacturer'),
                  leading: // Use leading for the status icon
                      Icon(scanner.isConnected ? Icons.usb : Icons.usb_off,
                           color: scanner.isConnected ? Colors.green : Colors.grey),
                  // Use trailing for the remove button
                  trailing: IconButton(
                     icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                     tooltip: 'Remove Scanner', // Add tooltip
                     onPressed: () async {
                        await _scannerService.removeScanner(scanner);
                     },
                  ),
                );
              },
            ),
          ),
          const VerticalDivider(),
          // Scanned Data Panel
          Flexible(
              flex: 10,
              child: UsbScannersListener(
                scannerService: _scannerService, // Pass the service instance
                onScan: (data) {
                  if (mounted) {
                     setState(() {
                       scannedData.add(data);
                     });
                     // Scroll to bottom (or top if reversed)
                     // Use jumpTo for immediate effect after setState
                     if (_scrollController.hasClients) {
                        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
                     }
                  }
                },
                child: ListView.builder(
                  // Display in insertion order (oldest at top)
                  itemCount: scannedData.length,
                  controller: _scrollController,
                  itemBuilder: (context, index) {
                    // Get item directly without reversing
                    return ListTile(
                      title: Text(scannedData[index]),
                      dense: true,
                    );
                  },
                ),
              )),
          const VerticalDivider(),
          // Random QR Code Panel
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text("Random QR", style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                QrImageView(
                  data: _randomQrData,
                  version: QrVersions.auto,
                  size: 150.0, // Adjust size
                  gapless: false,
                ),
                const SizedBox(height: 10),
                Text(_randomQrData, style: const TextStyle(fontSize: 10)), // Show the data
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text("Generate New"),
                  onPressed: _regenerateQrCode,
                ),
              ],
            ),
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
                    // Use a different validation value for the dialog finder
                    const Text(
                      'Scan QR code to add scanner',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    UsbScannerFinder(
                      scannerService: _scannerService, // Pass the service instance
                      suffix: Suffix.tab, // Or match your scanner's config
                      onFound: () {
                        if (mounted) {
                           Navigator.pop(context); // Close dialog on success
                           ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Scanner Added!'), backgroundColor: Colors.green),
                           );
                        }
                      },
                      size: 250, // Make QR larger for dialog
                      validationValue: 'ADD_THIS_SCANNER_PLEASE_123!', // Unique validation string
                      filter: (v) {
                        // Example filter: ignore devices with 'printer' in name
                        return !(v.productName ?? '').toLowerCase().contains('printer');
                      },
                    ),
                     const SizedBox(height: 16),
                     ElevatedButton(
                       onPressed: () => Navigator.pop(context),
                       child: const Text('Cancel'),
                     )
                  ],
                ),
              ),
            ));
    // No need for setState here, service stream handles updates
  }

  @override
  void dispose() {
    // Cancel subscription and dispose service
    _scannersUpdateSubscription?.cancel();
    _scannerService.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}
