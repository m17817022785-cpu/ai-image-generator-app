# ⚠️ AI Agent 必读项目记忆

> 修改、构建或维护本仓库前，必须先阅读根目录 [`AGENTS.md`](./AGENTS.md)。  
> 该文件记录了项目稳定规则、签名/构建注意事项、禁止大重构/反向优化约束、重要功能保护清单。  
> 后续任何 AI Agent、Copilot、自动脚本或人工维护者都应优先遵守该项目记忆。

---

# Luna AI Flutter Client

一个基于 Flutter 开发的专业 AI 助手客户端，支持 OpenAI 通用兼容格式的流式聊天、视觉分析、AI 图像生成和现代化深色 UI。

## ✨ 特性

- **OpenAI 通用兼容格式**：聊天固定使用 `/chat/completions`，画图固定使用 `/images/generations`。
- **统一输入入口**：聊天、生图、看图分析合并在同一个输入框中。
- **令牌分离配置**：聊天和生图可以使用不同 API Key。
- **接口分离配置**：聊天接口和生图接口可以使用不同 Base URL。
- **模型保护**：自动阻止 `gpt-40`、`gpt-4o`、`gpt-4o-mini` 等聊天模型被误用于画图接口。
- **流式对话**：支持 OpenAI SSE 流式响应，同时兼容部分服务商的非流式 JSON 返回。
- **AI 生图**：兼容图片接口返回 `url` 或 `b64_json`。
- **视觉分析**：支持 OpenAI 多模态消息格式上传图片分析。
- **相册保存**：生成的网络图片可一键保存至系统相册。
- **现代 UI**：深色渐变背景、玻璃态面板、快捷功能卡片、悬浮输入栏和新版消息气泡。

## 🆕 当前版本

```text
1.1.4+6
```

本版本重点修复：

- 将聊天和画图请求统一整理为 OpenAI 通用兼容格式。
- 聊天请求：`POST {聊天 Base URL}/chat/completions`。
- 画图请求：`POST {生图 Base URL}/images/generations`。
- Base URL 自动去除末尾 `/`，避免拼接成 `//chat/completions`。
- 聊天模型自动清洗：如果误填 `gpt-40`，会自动改用 `gpt-4o`。
- 生图模型自动清洗：如果误填 `gpt-40`、`gpt-4o`、`gpt-4o-mini` 等聊天模型，会自动改用 `dall-e-3`。
- 生图接口兼容 OpenAI 常见返回：`data[0].url` 和 `data[0].b64_json`。
- 保留“聊天 API Key / 生图 API Key”和“聊天 Base URL / 生图 Base URL”分离配置。

## ⚙️ 推荐配置

设置页包含：

```text
聊天 API Key
生图 API Key（可留空沿用聊天令牌）
聊天 Base URL
生图 Base URL（可留空沿用聊天接口）
聊天模型
生图模型
```

### 聊天和生图来自同一个 OpenAI 兼容服务

```text
聊天 API Key = sk-xxxx
生图 API Key = 留空
聊天 Base URL = https://xxx.example.com/v1
生图 Base URL = 留空
聊天模型 = gpt-4o-mini / gpt-4o / 服务商支持的聊天模型
生图模型 = dall-e-3 / dall-e-2 / gpt-image-1 / 服务商支持的图片模型
```

### 聊天和生图来自不同服务商

```text
聊天 API Key = sk-llm-xxxx
生图 API Key = sk-image-xxxx
聊天 Base URL = https://llm.example.com/v1
生图 Base URL = https://image.example.com/v1
聊天模型 = gpt-4o-mini
生图模型 = dall-e-3
```

## ⚠️ 重要说明

你遇到的错误：

```text
model not found: No available channel for model gpt-40
```

说明 `gpt-40` 被服务商当成了请求模型。`gpt-40` 通常是把字母 `o` 误写成数字 `0`。新版中：

- 聊天模型填 `gpt-40` 会自动修正为 `gpt-4o`。
- 生图模型填 `gpt-40` / `gpt-4o` / `gpt-4o-mini` 会自动回退为 `dall-e-3`。

OpenAI 通用画图接口 `/images/generations` 应填写图片模型，例如：

```text
dall-e-3
dall-e-2
gpt-image-1
```

不要把“生图模型”填写为：

```text
gpt-40
gpt-4o
gpt-4o-mini
```

如果服务商不支持 `dall-e-3`，请把“生图模型”改为服务商明确支持的图片模型，并确保“生图 Base URL”指向支持 `/images/generations` 的服务。

## 🚀 快速开始

1. 确保已安装 Flutter 环境。
2. 在设置界面配置 API Key、Base URL 和模型。
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
