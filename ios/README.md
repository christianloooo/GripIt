# GripIt for iOS

A SwiftUI application for iPhone and iPad, targeting iOS 17+. It embeds the existing React/Three.js studio in WKWebView. The renderer, grip solver, scan quality checks, and MediaPipe worker remain TypeScript; this is a SwiftUI/WebKit hybrid, not a complete rewrite of those systems in Swift.

All website assets, hand/baseball models, textures, MediaPipe WASM, and the detection model are copied into the app bundle. No development server or internet connection is needed when running the installed app. A Swift `Network` server bound to `127.0.0.1:49173` serves only the bundled files; it is not accessible over Wi-Fi. Its stable origin preserves WebKit's local failure log between launches.

## Run on your iPhone

From the repository root:

```sh
npm ci
npm run ios:prepare
npm run ios:open
```

In Xcode:

1. Select the **GripIt** target, then **Signing & Capabilities**.
2. Select your Apple development team. Change `com.christianloooo.gripit` if your team needs a different bundle identifier.
3. Select a connected iPhone or an iOS simulator and press **Run**.
4. On a real iPhone, allow the camera when starting a scan. Place an open hand and regulation baseball beside each other at the same depth.

Re-run `npm run ios:prepare` after changing the website. `ios/GripIt/Web` is generated and ignored by Git; the Xcode project, Swift sources, icon, and licenses in the web bundle are retained. Missing generated assets produce a build/resource error; prepare them before opening/building from a fresh checkout.

## Native integration

- SwiftUI hosts the app, loading state, recovery screen, and native share sheet.
- `WKUIDelegate` grants camera capture only to the app's own loopback origin and only after iOS camera authorization. Microphone capture requests are denied.
- **Export grip**, **Export session JSON**, and **Download log** open the iOS share sheet; choose **Save to Files**, AirDrop, or another destination. JSON exports are also written to the app's private Documents directory.
- External links open in the system browser. The privileged export bridge accepts only messages from the bundled main frame.
- Video remains on-device. Existing scan/model rejection checks and failure logging are shared with the website. Phone scan estimates retain the website's measurement limits.

Camera capture on a physical iPhone still needs a real-device test; the simulator test exercises a generated blank frame, not a camera or real hand scan. Native sharing is implemented but requires interactive device validation. No signing team, App Store upload, or TestFlight release is configured.

Apple API references: [WebKit camera permissions](<https://developer.apple.com/documentation/webkit/wkuidelegate/webview(_:requestmediacapturepermissionfor:initiatedbyframe:type:decisionhandler:)>), [local networking ATS setting](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking).

## Checks

```sh
npm test
npm run ios:prepare
xcodebuild -project ios/GripIt.xcodeproj -scheme GripIt \
  -sdk iphonesimulator -derivedDataPath ios/build CODE_SIGNING_ALLOWED=NO build

# Substitute an available simulator ID from xcrun simctl list devices available.
xcodebuild test -project ios/GripIt.xcodeproj -scheme GripIt \
  -destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_ID' \
  -derivedDataPath ios/build CODE_SIGNING_ALLOWED=NO
```

The Swift tests verify HTTP asset delivery, WASM MIME type, HEAD responses, missing files, path traversal rejection, studio/canvas loading, the native export bridge/file round trip, and offline detector initialization/frame processing inside iOS WebKit. The GitHub Actions workflow repeats the web tests and simulator tests on macOS.
