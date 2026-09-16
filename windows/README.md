# Lecture Copilot for Windows

Windows 版与 macOS 版使用相同的课堂流程，但代码、安装器和本地数据完全分开。Windows 代码位于 `windows/`，不会参与 Swift/macOS App 的构建。

## 系统要求

- 64 位 Windows 10 22H2 或 Windows 11
- 已安装、打开并登录豆包 Windows 客户端
- x64 电脑；当前安装包暂不提供 Windows on ARM 原生版本

## 推荐安装

从 [GitHub Releases](https://github.com/yejiasong1-ferrari/lecture-copilot/releases/latest) 下载：

```text
Lecture-Copilot-Windows-x64-Setup.exe
```

双击安装即可。默认安装到当前用户目录，不需要管理员权限，并可选择创建桌面快捷方式和开机启动。

也可以打开 PowerShell，运行：

```powershell
irm https://raw.githubusercontent.com/yejiasong1-ferrari/lecture-copilot/main/windows/install.ps1 | iex
```

脚本会下载最新安装器并验证 SHA-256，再启动安装向导。

> 当前安装器还没有购买 Windows 代码签名证书。Windows SmartScreen 第一次可能显示「Windows 已保护你的电脑」。确认下载地址来自本仓库后，可以点「更多信息 → 仍要运行」。

## 第一次使用

1. 先启动并登录豆包 Windows 客户端。
2. 打开 Lecture Copilot。右上角会出现深色玻璃 HUD，任务栏通知区域会出现图标。
3. 打开一页课件，按 `Shift + ←`。
4. Windows 截图工具出现后，拖动框选内容。
5. Lecture Copilot 会短暂打开豆包、建立新对话、粘贴截图和 prompt，然后回到课堂窗口。
6. 豆包生成完成后按 `Shift + Return`，回答会进入 HUD。

Windows 不需要 macOS 的「屏幕录制」或「辅助功能」授权。Lecture Copilot 和豆包应以相同权限运行；不要只把其中一个设置为管理员运行。

## 快捷键

- `Shift + ←`：Translate
- `Shift + →`：Explain
- `Shift + ↑`：Direct Answer
- 0.6 秒内连续两次 `Shift + ↑`：Say in Class
- `Shift + Return`：读取豆包最新回答
- `Shift + ↓`：回到课堂窗口
- 裸按两下 `Shift`：隐藏或显示 HUD

Class Mode 关闭时，上述快捷键不会执行。

## 课堂记录

1. 点 HUD 的 **Start** 开始课堂。
2. Explain、Direct Answer、Say in Class 会自动写入本节记录；Translate 默认不记录。
3. 点 **End** 只停止计时。
4. 点 **Summary** 才把课堂记录发给豆包。
5. 总结生成完成后按 `Shift + Return`。
6. 点 **Review Note** 预览，或点 **Save** 保存 Markdown 和截图文件夹。
7. 点 **New** 开始下一节课。

笔记默认保存到：

```text
%USERPROFILE%\Documents\Lecture Copilot
```

运行数据位于：

```text
%LOCALAPPDATA%\Lecture Copilot
```

其中包含 `prompts.json`、`debug.log`、最后一次截图/答案和课堂 session。

## 豆包 Copy 读取策略

Windows 版不 OCR 豆包正文。读取时会：

1. 激活豆包并滚到当前对话底部。
2. 优先通过 Windows UI Automation 查找名称为 Copy/复制的最后一个按钮。
3. 如果按钮没有名称，查找回答底部的操作按钮组。
4. 优先调用按钮的 Invoke 动作，失败再点击按钮中心，并缓存相对位置。
5. 使用 clipboard sentinel 判断是否真的复制成功。

如果豆包仍在生成或没有暴露按钮，HUD 会显示 `Still generating...`。等一两秒再按 `Shift + Return`。

## 故障排查

### 快捷键没有反应

- 确认托盘菜单中的 Class Mode 已勾选。
- 检查是否有其他软件占用了同一组全局快捷键。
- 退出 Lecture Copilot 后重新打开。

### 能截图但豆包没有收到

- 确认是豆包 Windows 桌面客户端，并且已经登录。
- 不要以管理员身份单独运行豆包或 Lecture Copilot。
- 打开 `%LOCALAPPDATA%\Lecture Copilot\debug.log` 查看失败步骤。

### 找不到 Copy

- 先确认豆包回答已经完全生成。
- 保持豆包主聊天窗口没有被其他窗口覆盖，然后再按一次 `Shift + Return`。
- 从托盘菜单选择 **Inspect Doubao**，会生成 `doubao-accessibility.txt`，可用于适配新版豆包。

### 卸载

打开「设置 → 应用 → 已安装的应用」，找到 Lecture Copilot 并卸载。课堂笔记和 `%LOCALAPPDATA%\Lecture Copilot` 数据默认保留，避免误删用户内容。

## 从源码构建

需要 Windows 10/11 和 .NET 8 SDK：

```powershell
git clone https://github.com/yejiasong1-ferrari/lecture-copilot.git
cd lecture-copilot
dotnet build windows/LectureCopilot.Windows/LectureCopilot.Windows.csproj -c Release
```

生成自包含版本：

```powershell
dotnet publish windows/LectureCopilot.Windows/LectureCopilot.Windows.csproj -c Release -r win-x64 --self-contained true -o windows/dist/win-x64
```

安装 Inno Setup 6 后运行 `windows/build.ps1`，即可同时生成安装器和 SHA-256 文件。
