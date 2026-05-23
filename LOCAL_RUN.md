# Local Run

## Web preview

The repository includes a static UI preview that can run without Flutter:

```powershell
cd D:\ai-image-generator-app
python -m http.server 5173
```

Open:

```text
http://127.0.0.1:5173/OPEN_WEB_PREVIEW.html
```

## Flutter app

This computer has been configured with:

- Flutter: `D:\dev\flutter-sdk\flutter`
- Android SDK: `D:\dev\android-sdk`
- JDK 17: `D:\dev\jdk-17`
- Pub cache: `D:\dev\pub-cache`
- Gradle cache: `D:\dev\gradle`

Open a new PowerShell window, then run:

```powershell
cd D:\ai-image-generator-app
flutter pub get
flutter run
```

On first launch, the app now defaults to:

- Base URL: `https://api.openai.com/v1`
- Chat model: `gpt-4o-mini`
- Text-to-image model: `dall-e-3`
- Image-edit model: `gpt-image-1`

You only need to enter your API key in the settings dialog before making real API calls.

## Build APK

```powershell
cd D:\ai-image-generator-app
flutter build apk --release
```

The signed APK is generated at:

```text
D:\ai-image-generator-app\build\app\outputs\flutter-apk\app-release.apk
```

This local build uses `android\key.properties` and `android\app\luna-release.jks`.
Do not commit those signing files. GitHub Actions must use the same keystore through
repository Secrets; see `SIGNING.md`.

## Test on Android

For quick local debugging, install and launch an APK with ADB:

```powershell
adb install -r D:\ai-image-generator-app\dist\github-actions-apk\app-release.apk
adb shell am start -n com.example.ai_image_generator/io.flutter.embedding.android.FlutterActivity
```

The local release APK and the GitHub Actions release artifact must both be signed
with this certificate:

```text
f71fc348afc87587eebb2467bc867374fccd322789e93d7c1a03f8786930527e
```

If a device has an older build signed by another certificate, Android cannot upgrade
it in place. Uninstall that one time, install this release-signed APK, and future
release builds from local or GitHub Actions will upgrade normally.
