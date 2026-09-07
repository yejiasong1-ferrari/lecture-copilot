# Lecture Copilot 权限问题修复记录

给别人安装请看仓库根目录的 [INSTALL.md](INSTALL.md)。别人装好后的 App 路径是：

```text
/Applications/Lecture Copilot.app
```

下面这份是开发时用 `./scripts/build_app.sh` 之后、权限失效时的处理说明。开发副本在 `dist/Lecture Copilot.app`。

## 现象

Lecture Copilot 已经在系统设置里打开了权限，但使用时仍然反复提示：

- 需要打开辅助功能权限
- 需要允许控制 System Events
- 需要打开屏幕录制权限
- 已经重新打开 App 还是不行

常见表现是：截图已经成功，但无法自动粘贴截图、输入 Prompt、发送到豆包。
也可能表现为：系统设置里的 `Lecture Copilot` 开关已经是蓝色，但 App 仍然说没有屏幕录制权限。

## 这次找到的原因

不是用户没有打开权限，而是 macOS 的 TCC 权限数据库还记着旧版本 Lecture Copilot 的授权记录。

Lecture Copilot 是本地构建出来的 app，并且目前是 ad-hoc 签名。每次重新 build 后，app 的代码签名哈希可能会变化。macOS 会把它当成一个“新的版本/新的身份”。

所以会出现这种情况：

- 系统设置里看起来已经有 `Lecture Copilot`
- 但当前运行的 `Lecture Copilot.app` 签名和旧授权记录对不上
- macOS 继续拒绝辅助功能权限
- 日志里会看到类似：

```text
Failed to match existing code requirement for subject com.local.lecturecopilot and service kTCCServiceAccessibility
```

或者：

```text
Failed to match existing code requirement for subject com.local.lecturecopilot and service kTCCServiceScreenCapture
```

## 修复方法

先退出 Lecture Copilot：

```bash
pkill -f 'Lecture Copilot.app/Contents/MacOS/Lecture Copilot' || true
```

只重置 Lecture Copilot 的辅助功能权限：

```bash
tccutil reset Accessibility com.local.lecturecopilot
```

如果屏幕录制页面里明明已经打开 `Lecture Copilot`，但 App 还是提示没有屏幕录制权限，也重置屏幕录制权限：

```bash
tccutil reset ScreenCapture com.local.lecturecopilot
```

如果豆包自动化也一直失败，也重置 Apple Events / Automation 权限：

```bash
tccutil reset AppleEvents com.local.lecturecopilot
```

打开辅助功能设置：

```bash
open 'x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture'
```

先手动添加屏幕录制权限：

1. 在 `系统设置 -> 隐私与安全性 -> 屏幕录制与系统音频录制` 里点 `+`
2. 按 `Command + Shift + G`
3. 粘贴：

```text
<项目文件夹>/dist/Lecture Copilot.app
```

4. 添加后，把 `Lecture Copilot` 右边开关打开成蓝色

然后打开辅助功能设置：

```bash
open 'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility'
```

再手动添加辅助功能权限：

1. 在 `系统设置 -> 隐私与安全性 -> 辅助功能` 里点 `+`
2. 按 `Command + Shift + G`
3. 粘贴：

```text
<项目文件夹>/dist/Lecture Copilot.app
```

4. 添加后，把 `Lecture Copilot` 右边开关打开成蓝色

最后重新打开 App：

```bash
open "<项目文件夹>/dist/Lecture Copilot.app"
```

第一次自动操作豆包时，macOS 可能会再问是否允许 Lecture Copilot 控制 `System Events`。这里要点允许。

## 每次更新后必须做

每次重新运行 `./scripts/build_app.sh` 之后，都必须按本文重新处理权限。不要假设系统设置里旧的蓝色开关仍然有效。

`build_app.sh` 结束时会自动：退出旧进程、重置 Accessibility / ScreenCapture / AppleEvents、把 App 路径复制到剪贴板、打开屏幕录制和辅助功能页面。之后仍需手动点 `+` 添加并打开开关，然后再打开 App。

## 重要提醒

修好权限后，先不要再重新运行：

```bash
./scripts/build_app.sh
```

因为重新 build 可能改变 app 的签名哈希，让 macOS 再次把它当成新 app。下次如果必须 rebuild，而权限又失效，就重新按照本文档的修复方法操作。

## 豆包已经生成回答，但 Lecture Copilot 读不到

如果小窗提示：

```text
截图已经发送到豆包，但还没有读到豆包回答。
```

说明截图和发送流程已经成功，问题出在“读取豆包回答”这一步。豆包是浏览器/Electron 类 App，聊天内容不一定稳定暴露给 macOS 辅助功能。

当前修复方式：

- 先尝试用 Accessibility 读取 `Doubao Browser` 和 `Doubao`
- 如果读不到，再短暂切到豆包窗口
- 截取豆包窗口
- 用 macOS 内置 Vision OCR 识别窗口里的回答
- 再切回课堂窗口并显示浮窗

这个方案仍然不用 API。

## 当前 app 信息

当前使用的 app 路径：

```text
<项目文件夹>/dist/Lecture Copilot.app
```

Bundle ID：

```text
com.local.lecturecopilot
```

权限页面中文名称：

- `Accessibility` = `辅助功能`
- `Automation` = `自动化`
- `Screen Recording` = `屏幕录制与系统音频录制` 或 `屏幕录制`
