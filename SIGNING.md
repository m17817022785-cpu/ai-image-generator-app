# Android release signing

The Android package name is `com.example.ai_image_generator`. Android only allows
an installed app to be upgraded by another APK signed with the same certificate.

This repository standardizes on the local release keystore:

```text
android/app/luna-release.jks
alias: luna
certificate SHA-256: f71fc348afc87587eebb2467bc867374fccd322789e93d7c1a03f8786930527e
```

Do not regenerate this keystore unless you are intentionally starting a new
install line. Regenerating it, using a debug keystore, or using a different CI
secret will produce APKs that cannot upgrade existing installs.

## Local signing

Local release builds use `android/key.properties`:

```properties
storeFile=luna-release.jks
storePassword=...
keyAlias=luna
keyPassword=...
```

Both `android/key.properties` and `android/app/luna-release.jks` are ignored by
Git on purpose.

## GitHub Actions signing

Configure these repository Secrets in GitHub:

```text
ANDROID_RELEASE_KEYSTORE_BASE64
ANDROID_RELEASE_KEYSTORE_PASSWORD
ANDROID_RELEASE_KEY_ALIAS
ANDROID_RELEASE_KEY_PASSWORD
```

`ANDROID_RELEASE_KEYSTORE_BASE64` is the base64 content of
`android/app/luna-release.jks`.

From PowerShell, generate it with:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("D:\ai-image-generator-app\android\app\luna-release.jks"))
```

Set the other values to match `android/key.properties`.

The APK workflows verify the restored keystore and the final APK certificate
against the SHA-256 fingerprint above. If the secret is missing or mismatched,
the workflow fails instead of publishing an APK with a conflicting signature.
