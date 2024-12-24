import 'package:usb_serial/usb_serial.dart';

extension UsbDeviceExt on UsbDevice {
  String get key => '$vid:$pid:$manufacturerName:$productName:$serial';
}
