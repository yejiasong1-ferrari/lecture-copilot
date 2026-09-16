# Windows 功能对齐清单

这份清单用于确保 Windows 版和 macOS 版的用户流程一致，同时保持两个平台的实现完全隔离。

## 已实现

- [x] Translate、Explain、Direct Answer、Say in Class 四种模式
- [x] Shift + 方向键和 Shift + Return 全局快捷键
- [x] 连按 Shift + ↑ 触发 Say in Class
- [x] 双击裸 Shift 隐藏/显示 HUD
- [x] Windows 原生区域截图并保存最后一次截图
- [x] 新建豆包对话、发送截图与 prompt、返回原窗口
- [x] UI Automation Copy-first 回答读取，不对正文 OCR
- [x] Copy 缓存位置、Invoke、物理点击重试和 clipboard sentinel
- [x] 180 秒普通回答、480 秒总结读取窗口
- [x] 5 秒 Shift + Return 冷却
- [x] 深色玻璃 HUD，悬停展开、离开收起、可拖动
- [x] Start、End、Summary、Review、Save、New 课堂状态
- [x] Explain、Direct Answer、Say in Class 自动记录
- [x] 可选 Record Translate
- [x] JSON session、截图副本、Markdown 与 shots 导出
- [x] 系统托盘菜单、Prompt 设置、最后回答、最后截图翻译
- [x] 豆包 UI Automation 树导出
- [x] Windows 自包含 x64 构建、安装器、SHA-256 与 CI 自测

## 平台差异

- macOS 使用 `screencapture`；Windows 使用系统 Screen Clipping。
- macOS 使用 Carbon/AppKit/Accessibility；Windows 使用 Win32、WPF 和 Windows UI Automation。
- macOS 数据在 `~/Library/Application Support`；Windows 数据在 `%LOCALAPPDATA%`。
- macOS 需要屏幕录制与辅助功能权限；Windows 不需要对应授权，但 Lecture Copilot 与豆包必须处于相同权限等级。
