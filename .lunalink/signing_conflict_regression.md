# APK signing conflict regression

## Error

The user reported Android signing conflict again after the versionCode fix. I had verified versionName/versionCode but did not close the loop on APK signing certificate consistency.

## Cause

Android can only upgrade an installed app when all of these are true:

1. The package/applicationId is the same.
2. The new versionCode is higher.
3. The APK signing certificate is exactly the same as the installed app.

The previous Gradle and CI setup allowed release builds to fall back to debug signing when no release keystore was configured. That can produce APKs signed by different certificates across local debug, CI debug, release keystore, or regenerated keystore builds, causing Android signature conflict.

## Correct fix

Release APK builds must use one stable release keystore. CI must require these GitHub Secrets:

- ANDROID_KEYSTORE_BASE64
- ANDROID_KEYSTORE_PASSWORD
- ANDROID_KEY_ALIAS
- ANDROID_KEY_PASSWORD

If these secrets are missing, CI must fail and must not upload a fallback-debug-signed release APK. Gradle release builds must also fail when release signing is missing. Build logs should print the signing certificate SHA-256 fingerprint for verification.

## Future requirement

For APK install failures, upgrade failures, signing conflicts, or reports like old version / cannot install / conflict, always check:

1. versionName
2. Android versionCode
3. applicationId
4. APK signing certificate SHA-256 fingerprint
5. whether CI used fallback debug signing
6. whether the installed app was signed by the same certificate

Never treat Actions success or versionCode alone as proof that an APK can upgrade the installed app.
