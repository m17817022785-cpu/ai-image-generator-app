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
Do not upload those signing files to GitHub.

## Test on Android

For quick local debugging, install and launch an APK with ADB:

```powershell
adb install -r D:\ai-image-generator-app\dist\github-actions-apk\app-release.apk
adb shell am start -n com.example.ai_image_generator/io.flutter.embedding.android.FlutterActivity
```

The GitHub Actions release artifact is signed with the repository-compatible signing certificate:

```text
120e5cf415cf7cbd17a66b29503a1ff57f5025f14a4caebab4790db94c197b19
```

Prefer the GitHub Actions APK for install/upgrade testing. Local release builds use the local keystore and may not upgrade over the GitHub-signed app.
