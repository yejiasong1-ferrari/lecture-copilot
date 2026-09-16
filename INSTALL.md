# Lecture Copilot 完整安装说明

这份说明面向第一次安装 Mac 小工具的用户。按照顺序完成即可，不需要会编程。

## 安装前检查

你需要：

1. macOS 14 Sonoma 或更新版本。
2. Apple Silicon Mac（M1/M2/M3/M4）用于预编译版本；Intel Mac 请看文末的源码安装。
3. 已安装、打开并登录过的豆包 Mac 客户端。
4. 可以访问 GitHub。

## 方法一：一行安装，推荐

### 第一步：打开终端

按 `Command + 空格`，输入「终端」或 `Terminal`，按回车。

### 第二步：运行安装命令

完整复制下面这一行，粘贴进终端，按回车：

```bash
curl -fsSL https://raw.githubusercontent.com/yejiasong1-ferrari/lecture-copilot/main/install-release.sh | bash
```

脚本会从 [GitHub Releases](https://github.com/yejiasong1-ferrari/lecture-copilot/releases/latest) 下载最新版，验证签名，安装到：

```text
/Applications/Lecture Copilot.app
```

它还会在桌面创建 Lecture Copilot 启动入口。此方法不需要 Xcode，也不需要自己编译。

## 方法二：手动下载

1. 打开 [最新版本下载页](https://github.com/yejiasong1-ferrari/lecture-copilot/releases/latest)。
2. 下载 `Lecture-Copilot-macOS-Apple-Silicon.zip`。
3. 双击解压，把 `Lecture Copilot.app` 拖入「应用程序」。
4. 如果 macOS 阻止打开，推荐回到方法一；当前版本尚未经过 Apple 公证。

## 必须设置的权限

安装器会把下面路径复制到剪贴板：

```text
/Applications/Lecture Copilot.app
```

在两个权限都打开之前，请不要启动 App。

### 屏幕录制与系统音频录制

1. 打开「系统设置 → 隐私与安全性 → 屏幕录制与系统音频录制」。
2. 点击 `+`。
3. 按 `Command + Shift + G`。
4. 粘贴 `/Applications/Lecture Copilot.app`，按回车并添加。
5. 打开右侧开关。

### 辅助功能

1. 打开「系统设置 → 隐私与安全性 → 辅助功能」。
2. 点击 `+`。
3. 按 `Command + Shift + G`。
4. 粘贴相同路径并添加。
5. 打开右侧开关。

### 第一次自动化授权

第一次把截图发送给豆包时，macOS 可能询问是否允许 Lecture Copilot 控制 System Events。请选择「允许」。

如果之前点过不允许，请前往「系统设置 → 隐私与安全性 → 自动化」重新打开。

## 第一次启动

两个权限都打开后，从以下任一位置启动：

- 桌面的 Lecture Copilot 图标
- 「应用程序」里的 Lecture Copilot
- Launchpad

启动后会看到：

- Dock 中的 Lecture Copilot 图标
- 菜单栏里的小图标
- 屏幕右上角的 Start Class 浮窗

如果豆包没有运行，Lecture Copilot 会尝试打开它。

## 第一次测试

1. 打开一个含英文文字的网页或幻灯片。
2. 按 `Shift + ←`。
3. 用鼠标框住一小段英文。
4. 等程序自动回到原页面。
5. 等豆包完成后按 `Shift + Return`。
6. 右上角浮窗应出现英文和中文对照。

## 快捷键说明

- `Shift + ←`：逐句翻译
- `Shift + →`：解释当前页面
- `Shift + ↑`：直接回答问题
- 0.6 秒内连续两次 `Shift + ↑`：生成可直接说出口的英文
- `Shift + Return`：读取豆包最新回答
- `Shift + ↓`：回到课堂页面
- 裸按两下 `Shift`：隐藏或显示浮窗

快捷键仅在菜单中的 Class Mode 开启时工作。

## 课堂模式

1. 点 **Start** 开始计时和记录。
2. 点 **End** 结束计时。
3. 点 **Summary** 才会发送本节记录生成总结。
4. 豆包完成后按 `Shift + Return`。
5. 点 **Save**，选择名称和位置保存 Markdown。
6. 点 **New** 开始下一节课。

课堂笔记默认保存到：

```text
~/Documents/Lecture Copilot/
```

## 更新

重新运行同一条安装命令即可更新：

```bash
curl -fsSL https://raw.githubusercontent.com/yejiasong1-ferrari/lecture-copilot/main/install-release.sh | bash
```

安装器会先保留旧版本；只有新版本成功安装后才替换。更新后 macOS 可能要求重新添加屏幕录制和辅助功能权限。

## 卸载

1. 退出 Lecture Copilot。
2. 删除 `/Applications/Lecture Copilot.app`。
3. 删除桌面的 Lecture Copilot 启动入口。
4. 如果还要删除设置与调试文件，再删除：

```text
~/Library/Application Support/Lecture Copilot/
```

已保存到 `~/Documents/Lecture Copilot/` 的课堂笔记不会自动删除。

## 故障排查

### 菜单栏和浮窗都没有出现

确认 App 正在运行。可以打开「活动监视器」搜索 Lecture Copilot，或重新双击桌面图标。

### 快捷键完全没有反应

确认菜单里的 Class Mode 已打开，并重新检查辅助功能权限。

### 能截图，豆包没有动作

确认豆包已登录；检查辅助功能和自动化权限。

### 找到了 Copy，但浮窗没有答案

先等豆包停止生成，再按 `Shift + Return`。如果持续失败，打开菜单中的 Inspect Doubao，并附上：

```text
~/Library/Application Support/Lecture Copilot/debug.log
~/Library/Application Support/Lecture Copilot/last-copy-search.png
```

### 更新后权限突然失效

在权限列表中删除旧的 Lecture Copilot，再重新点击 `+` 添加 `/Applications/Lecture Copilot.app`。

### 提示下载失败

先在浏览器确认 GitHub 可以访问，然后重新运行安装命令。

### Intel Mac

预编译包目前只提供 Apple Silicon。Intel Mac 需要安装 Xcode Command Line Tools 并从源码构建：

```bash
xcode-select --install
git clone https://github.com/yejiasong1-ferrari/lecture-copilot.git
cd lecture-copilot
./install.sh
```

## 安装器具体做了什么

为了让你知道一行命令的行为，`install-release.sh` 只执行以下操作：

1. 从本项目的 GitHub Latest Release 下载固定名称的 zip。
2. 使用 macOS `codesign` 验证 App 包没有损坏。
3. 安装到 `/Applications`，失败时恢复上一版。
4. 清除 GitHub 下载产生的 quarantine 标记。
5. 创建桌面启动入口。
6. 重置本 App 的三项权限记录，并打开系统设置。

你可以在运行前直接查看 [安装脚本源码](install-release.sh)。
