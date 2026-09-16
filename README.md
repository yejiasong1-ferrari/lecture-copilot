<p align="center">
  <img src="docs/assets/lecture-copilot-brand.png" width="560" alt="Lecture Copilot — Listen, Understand, Keep Up">
</p>

<h1 align="center">Lecture Copilot</h1>

<p align="center">
  留在课堂页面，框选任何内容，通过已登录的豆包完成翻译、讲解、回答与课堂总结。
</p>

<p align="center">
  <a href="https://github.com/yejiasong1-ferrari/lecture-copilot/releases/latest"><img src="https://img.shields.io/badge/version-v1.1.0-4F8CFF" alt="v1.1.0"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-black?logo=apple" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Windows-10%2F11-1674EA?logo=windows" alt="Windows 10/11">
  <img src="https://img.shields.io/badge/download-Apple%20Silicon-8A63D2" alt="Apple Silicon download">
  <img src="https://img.shields.io/badge/API%20Key-not%20required-31B57B" alt="No API key required">
</p>

Lecture Copilot 是一个轻量的 macOS 与 Windows 课堂助手。按快捷键框选幻灯片后，它会短暂操作电脑上已经登录的豆包，再把结果放进右上角的玻璃浮窗。你可以继续看 Zoom、浏览器或课件，不必来回复制粘贴。

它适合英文授课、术语密集的课程、临时没听懂的概念，以及课后整理课堂记录。

> macOS 版支持 macOS 14+ 和 Apple Silicon；Intel Mac 可从源码构建。Windows 版支持 64 位 Windows 10/11 x64。两个版本的源码、安装器和本地数据完全隔离。

## 选择你的系统

### Windows 10 / 11

从 [最新 Release](https://github.com/yejiasong1-ferrari/lecture-copilot/releases/latest) 下载并双击：

```text
Lecture-Copilot-Windows-x64-Setup.exe
```

或者在 PowerShell 运行带 SHA-256 验证的一行安装：

```powershell
irm https://raw.githubusercontent.com/yejiasong1-ferrari/lecture-copilot/main/windows/install.ps1 | iex
```

完整步骤和 Windows 故障排查见 [Windows 使用说明](windows/README.md)。

### macOS 14+

开始前先安装并登录豆包 Mac 客户端。

打开 macOS 自带的「终端」，复制下面整行并按回车：

```bash
curl -fsSL https://raw.githubusercontent.com/yejiasong1-ferrari/lecture-copilot/main/install-release.sh | bash
```

安装器会：

1. 从 GitHub Release 下载最新版，不安装 Xcode、不在你的电脑上编译。
2. 校验下载包并安装到 `/Applications/Lecture Copilot.app`。
3. 在桌面创建带图标的启动入口。
4. 把 App 路径复制到剪贴板，并打开需要设置的两个权限页面。

安装结束后，先不要打开 App。按照终端里的提示打开：

1. **屏幕录制与系统音频录制**：点 `+`，按 `Command + Shift + G`，粘贴，添加 Lecture Copilot，并打开开关。
2. **辅助功能**：重复同样步骤，并打开开关。
3. 两个开关都打开后，再从桌面或「应用程序」启动 Lecture Copilot。

需要逐屏说明、手动下载、更新、卸载和故障排查，请看 [macOS 完整安装说明](INSTALL.md)。

## 它能做什么

- **Translate**：把截图中的英文按句翻成中文，保留术语原文。
- **Explain**：用简短中文把当前页面讲懂。
- **Direct Answer**：对截图中的问题给出直接答案和简短理由。
- **Say in Class**：生成一两句可以直接开口说的英文。
- **Class Session**：记录本节课的讲解、回答和发言建议，下课后生成总结并保存为 Markdown。
- **Quiet HUD**：答案停在屏幕右上角；鼠标移入展开，移开收起；裸按两下 Shift 可以隐藏或显示。

## 上课怎么用

先点击菜单栏的 Lecture Copilot 图标，确认 **Class Mode** 已打开。

- `Shift + ←`：Translate
- `Shift + →`：Explain
- `Shift + ↑`：Direct Answer
- 0.6 秒内连续两次 `Shift + ↑`：Say in Class
- `Shift + Return`：去豆包复制本次回答并显示在浮窗
- `Shift + ↓`：回到刚才的课堂 App
- 裸按两下 `Shift`：隐藏或显示浮窗

一次完整操作是：

1. 按功能快捷键。
2. 拖框选中幻灯片或题目。
3. 程序发送后自动回到课堂页面。
4. 豆包生成完成后按 `Shift + Return`。
5. 答案出现在右上角浮窗。

## 课堂记录

1. 在浮窗点 **Start** 开始一节课。
2. Explain、Direct Answer、Say in Class 会自动记入本节课；Translate 默认不记录，可在菜单开启。
3. 点红色 **End** 只停止计时，不会立刻发送总结。
4. 点 **Summary** 后才把课堂记录发给豆包。
5. 总结生成完后按 `Shift + Return`。
6. 用 **Save** 保存 Markdown，或用 **New** 开始下一节课。

默认保存目录：macOS 为 `~/Documents/Lecture Copilot/`，Windows 为 `%USERPROFILE%\Documents\Lecture Copilot`。

## 为什么需要这些权限

- **macOS 屏幕录制**：只用于你主动框选课堂内容时截图。
- **macOS 辅助功能与自动化**：用于切换豆包、粘贴内容、点击 Copy，并返回课堂页面。
- **Windows**：使用系统截图工具和 Windows UI Automation，不需要上述 macOS 权限；Lecture Copilot 与豆包需使用相同权限等级。

Lecture Copilot 不调用模型 API，也不需要 API Key，不会产生单独的 API 账单。你选中的截图和提示词会通过电脑上已登录的豆包客户端发送，并受豆包自身的服务和隐私政策约束。完整聊天仍保存在豆包中。

本地运行数据位于 macOS 的 `~/Library/Application Support/Lecture Copilot/`，或 Windows 的 `%LOCALAPPDATA%\Lecture Copilot`。

## 常见问题

**快捷键没有反应**

确认 Class Mode 已打开，并检查辅助功能权限。更新 App 后如果权限失效，请重新运行安装命令并重新添加权限。

**能截图，但豆包没有动作**

确认豆包已经安装、登录，并在「系统设置 → 隐私与安全性 → 自动化」中允许 Lecture Copilot 控制 System Events。

**浮窗显示 Still generating**

豆包可能仍在生成，或 Copy 按钮尚未出现。等一两秒，再按一次 `Shift + Return`。

**macOS 说无法验证开发者**

请使用上面的一行安装命令。安装器会校验 GitHub 下载包并清理下载隔离标记。当前版本使用 ad-hoc 签名，还没有 Apple 公证。

**支持其他模型吗**

当前自动化流程针对豆包桌面版。macOS 与 Windows 都不调用模型 API。

## macOS 从源码安装

适合开发者或 Intel Mac 用户。需要 Xcode Command Line Tools：

```bash
git clone https://github.com/yejiasong1-ferrari/lecture-copilot.git
cd lecture-copilot
./install.sh
```

只构建、不安装：

```bash
./scripts/build_app.sh --no-reset
```

输出位于 `dist/Lecture Copilot.app`。

## 版本

### v1.1.0

- 新的 App、菜单栏和 HUD 品牌图标。
- Start / End / Summary / Save / New 课堂流程更完整。
- 双击 Shift 隐藏或显示 HUD。
- Copy 图标识别与点击增加视觉定位、重复点击和辅助功能兜底。
- 提供无需编译的一行安装和 GitHub Release 下载包。
- 新增独立的 Windows 10/11 x64 版本、安装器和使用说明。

完整更新记录见 [CHANGELOG.md](CHANGELOG.md)。
