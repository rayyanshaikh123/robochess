# iPhone build setup

The BLE Dart client is iOS-safe and `Runner/Info.plist` includes the Bluetooth
usage description. This checkout was added without Flutter's generated Xcode
project, so generate it on a macOS machine with Flutter and Xcode installed:

```bash
cd frontend
flutter create --platforms=ios .
pod install --project-directory=ios
flutter run -d <physical-iphone-id>
```

Use a physical iPhone near the Pi. iOS prompts for pairing automatically when
the app performs its first authenticated GATT write; the app must not force an
Android-style programmatic bond.
