# AGENTS.md — AI Image Generator 项目强制记忆

> 所有 AI Agent、Copilot、脚本维护者、后续对话在修改本仓库前必须先阅读本文件。  
> 如果你正在执行本项目，不管是否记得上下文，都必须把本文件当作最高优先级的项目约束。

## 0. 绝对优先级

1. **先读本文件，再改代码。**
2. **稳定优先，不做大重构。** 本项目是已经能构建 APK 的 Flutter Android 项目，禁止为了“优化结构”而重写架构、迁移框架、重排大量文件。
3. **小步提交，小步验证。** 每次只修复明确问题，优先最小补丁。
4. **不得反向优化。** 不要删除已经可用的兼容逻辑、签名逻辑、构建 workflow、模型兜底、错误处理、超时处理、多图处理、新会话能力。
5. **构建 APK 优先使用 GitHub Actions：** `.github/workflows/build_apk.yml`。

## 1. 项目身份

- 仓库：`m17817022785-cpu/ai-image-generator-app`
- 项目类型：Flutter Android App
- App 方向：AI 聊天 + 文生图 + 图生图 / 多参考图生成
- 包用途：面向 Android 安装 APK
- 主要代码目录：`lib/`
- Android 工程目录：`android/`
- 稳定构建 workflow：`.github/workflows/build_apk.yml`

## 2. 必须保护的稳定能力

以下能力已经反复修过，禁止无故删除或倒退：

- 聊天与图片分离配置：聊天 API Key/Base URL/模型，图片 API Key/Base URL/文生图模型/图生图模型。
- 图片 API Key、图片 Base URL 留空时沿用聊天配置。
- 模型保护：聊天模型误填到图片模型时，要有兜底或友好提示。
- `gpt-40` 应识别为用户常见误写，聊天可修正到 `gpt-4o`，图片应避免误用于图片接口。
- 支持多张参考图，限制数量，允许删除、清空、追加。
- 支持图片数量 `1..4`。
- 支持画幅比例与质量选项。
- 新会话按钮：清空当前聊天界面，但保留 API 配置和图片参数。
- 智能创作面板可收起，并持久化收起状态。
- 服务器返回空 `choices` / 空 `data` 时禁止 RangeError 崩溃，要友好提示。
- 网络中断、超时、接口返回 HTML、JSON 解析失败都要给用户可理解提示。
- 图片生成超时要比普通聊天长。

## 3. 构建与签名记忆

### 3.1 稳定构建入口

优先使用：

```text
.github/workflows/build_apk.yml
```

此 workflow 已经成功构建过 APK。不要随便删除或替换它。

### 3.2 APK artifact

稳定产物名称：

```text
AI-Image-Generator-release-apk
```

内部 APK 文件通常为：

```text
AI-Image-Generator-release.apk
```

### 3.3 签名规则

当前仓库使用 GitHub Actions 内的 fallback/debug keystore 机制保证 APK 可安装和可持续升级：

- Java 17
- Flutter `3.24.5` stable
- 使用缓存的 Android debug keystore 作为 fallback signing
- 构建命令应保留 `--build-name` 与 `--build-number`
- build number 应至少不低于 GitHub run number，避免安装升级降级失败

不要删除 workflow 里的 keystore/cache/signing 相关步骤，除非明确替换为更稳定的正式签名方案。

## 4. 版本号规则

`pubspec.yaml` 的版本格式：

```text
version: x.y.z+buildNumber
```

要求：

- 每次发新 APK，`buildNumber` 必须递增或由 workflow 用 GitHub run number 抬高。
- 不要把版本号降级。
- 如果用户要安装覆盖旧包，优先 bump `+buildNumber`。

当前已见版本包括：

```text
1.2.5+1001
```

后续必须只增不减。

## 5. GitHub Actions 注意事项

- 已有多个历史修复 workflow，有些是临时 patch workflow，可能失败；不要以失败的临时 workflow 判断主构建失败。
- 判断 APK 是否可用，以 `Build APK` / `.github/workflows/build_apk.yml` 成功为准。
- 如果要新增 workflow，保持 YAML 简短，避免超长内嵌脚本导致工具 JSON 解析失败。
- 对于大规模源码修复，不要把长脚本塞进一次 API 调用；优先直接更新源码文件，或拆小提交。

## 6. 开发原则

### 6.1 禁止大重构

不要做这些事：

- 不要迁移到新状态管理框架。
- 不要重写 UI 架构。
- 不要拆散现有服务层和页面层，除非用户明确要求。
- 不要删除中文提示词和错误提示。
- 不要把多图、图生图、文生图逻辑合并成不可调试的大函数。
- 不要用“代码更优雅”为理由改变已稳定的接口行为。

### 6.2 推荐小修

应该这样做：

- 先读相关文件。
- 精确定位问题。
- 最小替换。
- 保留兼容逻辑。
- 触发 `build_apk.yml` 构建验证。
- 最终说明 artifact 下载位置。

## 7. 关键文件

- `lib/screens/home_screen.dart`：主界面、聊天、图片生成、新会话、参数面板、多参考图。
- `lib/services/api_service.dart`：OpenAI 兼容 API、聊天流、模型列表、文生图、图生图、错误解析、超时。
- `lib/services/settings_service.dart`：API 配置、图片参数、面板收起状态持久化。
- `lib/models/message.dart`：消息结构、多图字段、OpenAI 消息转换。
- `lib/services/image_save_service.dart`：图片保存到相册。
- `.github/workflows/build_apk.yml`：稳定 APK 构建。
- `pubspec.yaml`：版本号和依赖。

## 8. API 与模型兼容记忆

- 聊天接口通常：`POST {Base URL}/chat/completions`
- 文生图接口通常：`POST {Image Base URL}/images/generations`
- 图生图接口通常：`POST {Image Base URL}/images/edits`
- 若 Base URL 已经包含 `/chat/completions` 或 `/images/generations`，代码应避免重复拼接。
- 图片接口常见返回：`data[0].url` 或 `data[0].b64_json`。
- 部分服务会返回 HTML 错误页，要检测并提示 Base URL 错误。
- `model not found` / `No available channel` 通常是模型或中转站渠道配置问题，应提示用户检查聊天模型、文生图模型、图生图模型。

## 9. 用户偏好

- 用户希望项目以后稳定推进。
- 用户明确不希望“反向优化”、不希望忘记签名/构建/稳定规则。
- 用户希望重要事项写在 GitHub，后续每次执行项目都能读到。
- 因此每次开始任务，应主动读取 `AGENTS.md` 和 README 顶部提示。

## 10. 每次执行项目的固定流程

1. 读取 `AGENTS.md`。
2. 读取用户需求。
3. 读取相关代码文件。
4. 制定小步 todo。
5. 最小修改。
6. 触发或建议触发 `.github/workflows/build_apk.yml`。
7. 检查 Actions 结果。
8. 给出 APK artifact 链接或下载说明。

## 11. 如果上下文冲突

如果当前对话、旧 workflow、旧 README 与本文件冲突：

- 以用户最新明确指令为最高优先级。
- 其次以本 `AGENTS.md` 为项目稳定约束。
- 不要根据旧失败 workflow 做破坏性回滚。

---

维护备注：本文件是项目记忆，不是普通文档。除非用户明确要求，否则不要删除、弱化或重写本文件。