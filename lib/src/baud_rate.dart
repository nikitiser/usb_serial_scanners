/// Enum representing common baud rates for serial communication.
///
/// Each enum value corresponds to a specific baud rate in bits per second (bps).
///
/// Example usage:
/// ```dart
/// BaudRate rate = BaudRate.b9600;
/// print(rate.value); // Outputs: 9600
/// ```
///
/// Enum values:
/// - `b9600`: 9600 bps
/// - `b14400`: 14400 bps
/// - `b19200`: 19200 bps
/// - `b38400`: 38400 bps
/// - `b57600`: 57600 bps
/// - `b115200`: 115200 bps
///
/// Each enum value has an associated integer value representing the baud rate.
enum BaudRate {
  b9600(9600),
  b14400(14400),
  b19200(19200),
  b38400(38400),
  b57600(57600),
  b115200(115200);

  final int value;
  const BaudRate(this.value);
}
