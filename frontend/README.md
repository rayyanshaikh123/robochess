RoboChess Mobile
RoboChess Mobile is the companion Flutter application for the RoboChess Smart Board, enabling players to control, play, and analyze chess games using voice commands.

Features
Players can speak their moves using speech-to-text, and the app parses and validates them in real time against the current board state. The interactive chess board provides full game state management with legal move validation, powered by the chess and flutter_chess_board packages. Through the cross-connect interface, the app pairs with the RoboChess Smart Board to sync moves between the physical and digital boards.

The analysis dashboard lets users review games with move history, positional charts built with fl_chart, and checkmate visualizations. A learn section offers curated tutorials and chess learning resources, and users get a profile screen with an animated avatar and configurable app preferences.

Design and Tech Stack
The app features a dark theme with neon green accents, Google Fonts typography, and Material 3 design. It is built with Flutter using Riverpod for state management, Go Router for navigation, and Clean Architecture organized into data, domain, and presentation layers.

## iOS Setup & Troubleshooting

### Initial Setup
1. Install Flutter dependencies: `flutter pub get`
2. Update iOS pods: `cd ios && pod update && cd ..`
3. Build and run: `flutter run -d <device_id>`

### Fixing iOS Build Errors

If you encounter the following errors on iOS device:
- `UIScene lifecycle will soon be required`
- `fopen failed for data file: errno = 2`

**Solution:**
1. Clean the build cache:
   ```bash
   flutter clean
   cd ios
   rm -rf Pods Podfile.lock .symlinks Flutter/Flutter.podspec
   cd ..
   ```

2. Rebuild:
   ```bash
   flutter pub get
   cd ios && pod install --repo-update && cd ..
   flutter run
   ```

3. The following files have been configured to support the modern UIScene lifecycle:
   - `ios/Runner/Info.plist` - Added UIApplicationSceneManifest configuration
   - `ios/Runner/SceneDelegate.swift` - Handles UIScene lifecycle callbacks

### Bluetooth & Permissions
Ensure your iOS device grants Bluetooth permissions when prompted. Update permissions in `Info.plist` if needed:
- `NSBluetoothAlwaysUsageDescription` - Required for BLE connection to physical chess board
