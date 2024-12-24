import '../usb_serial_scanners.dart';

class UsbSerialScannerMeta {
  final String? productName;
  final String? manufacturerName;
  final int? vid;
  final int? pid;
  final String? serial;
  final int baudRate;
  final Suffix suffix;

  UsbSerialScannerMeta({
    required this.productName,
    required this.manufacturerName,
    required this.vid,
    required this.pid,
    required this.serial,
    required this.baudRate,
    required this.suffix,
  });

  String get key => '$vid:$pid:$manufacturerName:$productName:$serial';

  Map<String, dynamic> toJSON() {
    return {
      'productName': productName,
      'manufacturerName': manufacturerName,
      'vid': vid,
      'pid': pid,
      'serial': serial,
      'baudRate': baudRate,
      'suffix': suffix.value,
    };
  }

  factory UsbSerialScannerMeta.fromJSON(Map<String, dynamic> json) {
    return UsbSerialScannerMeta(
      productName: json['productName'],
      manufacturerName: json['manufacturerName'],
      vid: json['vid'],
      pid: json['pid'],
      serial: json['serial'],
      baudRate: json['baudRate'],
      suffix: Suffix.values.firstWhere((element) => element.value == json['suffix']),
    );
  }
}
