# usb_serial_scanners

[![pub package](https://img.shields.io/pub/v/usb_serial_scanners.svg)](https://pub.dev/packages/usb_serial_scanners)

Пакет Flutter для работы с USB сканерами штрих-кодов (и другими устройствами), работающими через эмуляцию COM-порта (USB CDC ACM). Основан на пакете [usb_serial](https://pub.dev/packages/usb_serial).

Этот пакет предоставляет высокоуровневый сервис для управления жизненным циклом сканеров, автоматического восстановления подключения, получения данных сканирования и добавления новых устройств.

## Возможности

*   **Управление сканерами:** Централизованный сервис (`UsbScannerService`) для управления подключенными сканерами.
*   **Автоматическое восстановление:** Автоматически подключается к ранее добавленным сканерам при запуске или при подключении устройства к USB.
*   **Потоки данных:** Предоставляет `Stream` для получения данных со всех активных сканеров и `Stream` для отслеживания изменений в списке подключенных сканеров.
*   **Добавление новых сканеров:** Включает класс `ScannersFinder` и виджет `UsbScannerFinder` для обнаружения и добавления новых сканеров путем сканирования QR-кода с валидационной строкой.
*   **Управление состоянием:** Позволяет приостанавливать (`pauseScanners`) и возобновлять (`resumeScanners`) прослушивание сканеров для оптимизации ресурсов.
*   **Обработка ошибок:** Позволяет передать колбэк для централизованной обработки ошибок.
*   **Сохранение настроек:** Сохраняет метаданные добавленных сканеров (VID, PID, суффикс и т.д.) в `SharedPreferences`.

## Установка

Добавьте зависимости в ваш `pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  usb_serial_scanners: # Укажите актуальную версию
  usb_serial: # Требуется как зависимость usb_serial_scanners
  # Добавьте qr_flutter, если планируете использовать виджет UsbScannerFinder
  qr_flutter: ^4.0.0 
  # Добавьте DI-решение (например, provider или get_it), если необходимо
  # provider: ^6.0.0 
```

Затем выполните `flutter pub get`.

**Настройка для Android:**

Следуйте инструкциям по настройке для Android из пакета `usb_serial` ([usb_serial setup](https://pub.dev/packages/usb_serial#android)). Обычно это включает добавление `intent-filter` в `AndroidManifest.xml`.

## Использование

### 1. Инициализация `UsbScannerService`

Создайте экземпляр `UsbScannerService`. Рекомендуется делать это один раз для всего приложения и управлять его жизненным циклом. Используйте DI-контейнер (например, `provider`, `get_it`) или управляйте им в корневом виджете вашего приложения.

```dart
import 'package:usb_serial_scanners/usb_serial_scanners.dart';

// Создаем сервис (например, в initState корневого виджета или через DI)
late UsbScannerService _scannerService;

void _initializeScannerService() {
  _scannerService = UsbScannerService(
    onError: (error, stackTrace) {
      print("Scanner Service Error: $error");
      // Обработайте ошибку (например, покажите сообщение пользователю)
    },
  );
  // Инициализируем сервис (восстановление сохраненных сканеров, запуск прослушивания USB)
  _scannerService.initialize(); 
}

@override
void initState() {
  super.initState();
  _initializeScannerService();
}

@override
void dispose() {
  // Обязательно освобождаем ресурсы при уничтожении виджета/приложения
  _scannerService.dispose(); 
  super.dispose();
}
```

### 2. Получение списка сканеров

Вы можете получить текущий список сканеров или подписаться на обновления.

```dart
// Получить текущий список (не реактивно)
List<UsbSerialScanner> scanners = _scannerService.currentScanners;

// Подписаться на обновления списка (реактивно)
StreamSubscription? scannersUpdateSubscription;

void _subscribeToScannerUpdates() {
  scannersUpdateSubscription = _scannerService.scannersUpdateStream.listen((updatedScanners) {
    setState(() {
      // Обновите ваш UI списком updatedScanners
      print("Scanner list updated: ${updatedScanners.length} scanners");
    });
  });
}

// Не забудьте отменить подписку в dispose()
// scannersUpdateSubscription?.cancel();
```

### 3. Получение данных сканирования

Подпишитесь на `scanDataStream` для получения данных со всех активных сканеров.

```dart
StreamSubscription? scanDataSubscription;

void _subscribeToScanData() {
  scanDataSubscription = _scannerService.scanDataStream.listen((data) {
    print("Scanned data: $data");
    // Обработайте полученные данные
  });
}

// Не забудьте отменить подписку в dispose()
// scanDataSubscription?.cancel();
```

Или используйте виджет `UsbScannersListener`:

```dart
UsbScannersListener(
  scannerService: _scannerService, // Передайте экземпляр сервиса
  onScan: (data) {
    print("Scanned data via Listener: $data");
    // Обработайте данные
  },
  child: YourWidgetTree(), // Ваш остальной UI
)
```

### 4. Добавление нового сканера

Используйте виджет `UsbScannerFinder` (обычно в диалоговом окне), чтобы пользователь мог отсканировать QR-код для добавления нового устройства.

```dart
Future<void> _showAddScannerDialog(BuildContext context) async {
  await showDialog(
    context: context,
    builder: (context) => Dialog(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("Подключите сканер и отсканируйте QR-код"),
            SizedBox(height: 16),
            UsbScannerFinder(
              scannerService: _scannerService, // Передайте сервис
              suffix: Suffix.cr, // Укажите суффикс вашего сканера
              baudRate: BaudRate.b9600, // Укажите скорость вашего сканера
              validationValue: 'YOUR_UNIQUE_VALIDATION_STRING', // Уникальная строка для QR
              onFound: () {
                print("Scanner found and added!");
                Navigator.pop(context); // Закрыть диалог
              },
              size: 250,
              // Опциональный фильтр для устройств-кандидатов
              filter: (device) => !(device.productName ?? '').toLowerCase().contains('printer'),
            ),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Отмена'),
            )
          ],
        ),
      ),
    ),
  );
}
```

### 5. Удаление сканера

```dart
// Получите экземпляр сканера (например, из списка _currentScanners)
UsbSerialScanner scannerToRemove = _currentScanners[index]; 

// Удалите его через сервис
await _scannerService.removeScanner(scannerToRemove); 
```

### 6. Пауза и возобновление

Если сканирование не требуется на некоторых экранах, вы можете приостановить прослушивание для экономии ресурсов.

```dart
// При переходе на экран, где сканирование не нужно
_scannerService.pauseScanners();

// При возвращении на экран, где сканирование нужно
_scannerService.resumeScanners();
```

## Пример

Полный пример использования смотрите в директории `example`.

## Зависимости

Этот пакет использует:
*   [usb_serial](https://pub.dev/packages/usb_serial) для низкоуровневого взаимодействия с USB CDC устройствами.
*   [shared_preferences](https://pub.dev/packages/shared_preferences) для хранения метаданных сканеров.
*   [qr_flutter](https://pub.dev/packages/qr_flutter) (опционально, для виджета `UsbScannerFinder`).

Убедитесь, что вы выполнили все необходимые нативные настройки для `usb_serial`.
