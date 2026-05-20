# Luna AI Flutter Client

一个基于 Flutter 开发的专业 AI 助手客户端，支持流式聊天、视觉分析、AI 图像生成和现代化深色 UI。

## ✨ 特性

- **统一输入入口**：聊天、生图、看图分析合并在同一个输入框中。
- **接口分离配置**：聊天接口和生图接口可以使用不同的 Base URL。
- **流式对话**：支持 GPT 级别的打字机实时响应效果。
- **AI 生图**：输入“画一张…”、“生成图片…”或点击画笔按钮即可生成图像。
- **视觉分析**：支持上传图片进行多模态视觉分析。
- **相册保存**：生成的 AI 图像可一键保存至系统相册。
- **现代 UI**：深色渐变背景、玻璃态面板、快捷功能卡片、悬浮输入栏和新版消息气泡。
- **网页版预览**：`web_preview/` 内提供纯静态网页，用于快速查看 UI 效果。

## 🆕 当前版本

```text
1.1.2+4
```

本版本重点修复：

- 新增“生图 Base URL”设置项。
- 支持聊天接口和生图接口分别配置不同服务商地址。
- “生图 Base URL”留空时自动沿用“聊天 Base URL”，兼容旧配置。
- 保留生图模型保护：误填聊天模型时自动回退到 `dall-e-3` 并给出友好提示。

## ⚙️ 接口配置说明

设置页现在包含：

```text
API Key
聊天 Base URL
生图 Base URL（可留空沿用聊天接口）
聊天模型
生图模型
```

如果你的 LLM 和生图来自同一个 OpenAI 兼容服务：

```text
聊天 Base URL = https://xxx/v1
生图 Base URL = 留空
```

如果 LLM 和生图来自不同服务：

```text
聊天 Base URL = https://llm.example.com/v1
生图 Base URL = https://image.example.com/v1
```

生图模型请填写图片模型，例如：

```text
dall-e-3
dall-e-2
gpt-image-1
```

不要把“生图模型”填写为聊天模型，例如：

```text
gpt-40
gpt-4o
gpt-4o-mini
```

这些聊天模型通常不能用于 `/images/generations` 生图接口。

## 🚀 快速开始

1. 确保已安装 Flutter 环境。
2. 在设置界面配置您的 API Key、Base URL 和模型。
3. 运行项目：

```bash
flutter pub get
flutter run
```

## 🌐 网页版预览

直接打开项目根目录中的：

```text
OPEN_WEB_PREVIEW.html
```

或打开：

```text
web_preview/index.html
```

注意：网页版预览是纯静态 UI 预览，不会真实调用 AI API。
