# APK 签名与构建稳定记忆

> 本文件是项目长期维护记忆的一部分。后续 AI Agent、Copilot、人工维护者在处理 APK 构建/安装/升级问题时必须阅读。

## 1. 背景：为什么会出现签名冲突

Android 同一个 `applicationId` 的 App 覆盖安装时，要求新 APK 和手机上已安装 APK 的签名证书完全一致。

如果签名证书变了，即使包名相同、版本号更高，也会出现类似：

```text
应用未安装
签名冲突
INSTALL_FAILED_UPDATE_INCOMPATIBLE
Package ... signatures do not match previously installed version
```

本项目曾经出现过这个问题，原因是 release APK 构建时过度依赖隐式 `signingConfigs.debug` 或 runner/debug keystore 状态，导致不同构建之间可能使用了不同证书。

## 2. 当前稳定策略

当前稳定构建入口是：

```text
.github/workflows/build_apk.yml
```

该 workflow 必须显式给 Gradle release signing 传入以下环境变量：

```text
ANDROID_KEYSTORE_PATH=/home/runner/.android/debug.keystore
ANDROID_KEYSTORE_PASSWORD=android
ANDROID_KEY_ALIAS=androiddebugkey
ANDROID_KEY_PASSWORD=android
```

`android/app/build.gradle` 会优先读取这些环境变量作为 release 签名配置。

## 3. 严禁退回隐式签名

不要把构建逻辑改回只依赖：

```groovy
signingConfig signingConfigs.debug
```

也不要删除 workflow 中的显式签名环境变量。

如果没有显式 release signing，GitHub runner、Gradle、Android debug keystore、cache 命中情况都可能造成签名漂移。

## 4. 构建后必须验证签名

workflow 应保留 APK 签名验证步骤：

```bash
apksigner verify --print-certs build/app/outputs/flutter-apk/app-release.apk
```

构建日志里应能看到证书 SHA-1 / SHA-256 信息。后续排查签名问题时，优先比较不同 APK 的证书指纹。

## 5. 安装冲突处理方式

如果用户手机已经安装了旧的不同签名 APK，则修复签名后的第一个 APK 仍然无法直接覆盖安装。

这种情况不是构建失败，而是 Android 安全机制。处理方式：

1. 备份需要的数据；
2. 卸载手机上的旧包；
3. 安装修复后新构建的 APK；
4. 后续只要继续使用同一个 workflow/签名配置构建，就可以正常覆盖升级。

## 6. 版本号与签名是两件事

- 版本号低会导致降级安装失败；
- 签名不同会导致签名冲突；
- 两者需要同时保证。

本项目 workflow 会用 GitHub run number 抬高 build number，避免版本号回退。

## 7. 后续更稳方案

当前方案已显式签名并验证。若未来要彻底替换为正式生产签名，应：

1. 生成固定 release keystore；
2. 用 GitHub Secrets 保存 base64 keystore 和密码；
3. workflow 每次从 Secrets 还原 keystore；
4. 更新本文件和 `AGENTS.md`；
5. 明确告知用户：切换正式签名后的第一次安装可能仍需卸载旧签名版本。

在没有正式 keystore Secrets 前，不要擅自改签名方案。
