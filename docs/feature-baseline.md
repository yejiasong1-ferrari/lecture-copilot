# Lecture Copilot 功能基线

改代码之后，用这份清单核对：**现有功能有没有被改掉、删掉、行为跑偏**。
记录日期：2026-09-11。对应本机产品身份 **v1.0 · Mac only**（`CFBundleShortVersionString` = `1.0.0`，bundle `com.local.lecturecopilot`）。

模式输出细则仍以 `PromptStore.swift` 和 `~/Library/Application Support/Lecture Copilot/prompts.json` 为准。`docs/modes.md` 里有过时描述（例如用裸 Return 提取），不要拿它当现状。

---

## 产品边界（不能破）

- [ ] 只支持 **macOS 14+**。没有 Windows。
- [ ] **不用 API Key**，不调用 OpenAI / Claude 等云端接口，不消耗那些 tokens。
- [ ] 只操作本机 **豆包**（`豆包` / `Doubao` / `豆包浏览器`）。截图和 prompt 发给豆包，答案从豆包 Copy 回来。
- [ ] 菜单栏有 logo，**Dock 里运行时也会出现圆角 logo**。顶部有时看不见时，点 Dock 图标会重新显示浮窗。桌面上的 **Lecture Copilot.app** 启动器点一下也会打开。
- [ ] 开发副本路径永远是：

```text
/Users/jacksonyip/Desktop/Lecture Copilot/dist/Lecture Copilot.app
```

- [ ] 给别人装的路径是 `/Applications/Lecture Copilot.app`。Jackson 本机 **不要**跑 `./install.sh`。
- [ ] 每次 `./scripts/build_app.sh` 会改 ad-hoc 签名。必须重新加 **屏幕录制** 和 **辅助功能**，两个开关都蓝了才能打开 App。第一次豆包自动化可能再问 System Events。

---

## 上课主流程（不能破）

1. Class Mode 打开。
2. 按模式快捷键 → 框选幻灯片。
3. App 把截图 + 对应 prompt 发给本机豆包，然后立刻回到课堂窗口。
4. 人继续看老师。豆包写完后按 **Shift + Return** 提取答案。
5. 右上角浮窗出现 Answer；鼠标移上去展开，移开缩回。

- [ ] 不会在发送后自动把答案读进浮窗（除非人为放了 `auto-extract` 调试文件）。
- [ ] 裸 **Return** 不能抢课堂输入（WPS / 浏览器等）。提取必须是 **Shift + Return**。
- [ ] 发送前会记住当前前台 App（含 Safari / Chrome 窗口和标签），提取或发送后用 **Shift + ↓** 或自动 restore 回到课堂。

---

## 快捷键（Class Mode ON 才生效）

| 按键 | 功能 | 检查 |
|---|---|---|
| `Shift + ←` | Translate | [ ] |
| `Shift + →` | Explain | [ ] |
| `Shift + ↑` | Direct Answer | [ ] |
| `Shift + ↑↑`（600ms 内两下） | Say in Class | [ ] |
| `Shift + Return` | 切到豆包，点 Copy，把答案放到浮窗 | [ ] |
| `Shift + ↓` | 回到刚才的课堂窗口 | [ ] |
| 连按两下 `Shift` | 隐藏 / 显示浮窗（不要按方向键或 Return） | [ ] |

- [ ] Class Mode 关掉时，这些热键全部不工作。
- [ ] `isBusy` 时忽略新的模式热键和提取，避免并发改剪贴板。
- [ ] **5 秒内连续 Shift+Return 只认第一次**。
- [ ] 普通答案 pending 提取窗口 **180 秒**；课堂总结 **480 秒**。过期后 Shift+Return 不再提取。

---

## 四个模式：该做什么 / 不该做什么

### Translate

- [ ] 只翻译 **这张截图里看得见的字**。
- [ ] 忽略豆包里上一轮对话和其他幻灯片。
- [ ] 不要扩写成讲义，不要补图里没有的公式、例题、下一页。
- [ ] 图里只有标题时，只输出标题对照，例如：

```text
Continuous Probability Distributions
连续概率分布（continuous probability distributions）
```

- [ ] 格式：一句英文，下一行中文，组与组空一行。术语写成 `中文（English）`。
- [ ] 禁止关键词对照表 / PRIMARY KEY 单词表。

### Explain

- [ ] 一段中文，大约 4–8 句，像旁边同学把这页讲懂。
- [ ] 不要逐句翻译，不要「核心 / 结构 / 关系」小标题，不要推荐问题。

### Direct Answer

- [ ] 选择题：`答案：B` + `原因` + `其他选项` 对错各一句。
- [ ] 问答题：`答案` 一句话 + `原因` 一句话。
- [ ] 不要复述题干，不要把选项再抄一遍，不要编新题。

### Say in Class

- [ ] 只有一行中文「你可以很口语地回答：」，下面 1–2 句能开口说的英文。
- [ ] 不要复述题干 / 选项，不要 essay。
- [ ] 连按 Shift+↑ 时，第二次可复用 **30 秒内** 的上次截图（`CapturedImageCache`），不必再框一次。

---

## 浮窗 HUD

- [ ] 深色玻璃浮窗，默认贴在屏幕右上。
- [ ] **没碰到**：窄条，高度只有标题栏，宽度刚好放下文字和按钮（不要把 Start / End / New 挤没）。
- [ ] **碰到**：向左、向下展开成大浮窗（右上角锚点不动）。移开约 0.22s 后缩回。
- [ ] 关闭叉：上课进行中如果正在显示 Answer / Loading，叉回去上课计时条，而不是把整节课关掉。
- [ ] 上课中看 Answer 时，右边红色 **End** 仍在，不必先点叉。
- [ ] 可用鼠标拖动浮窗。

### 课节按钮

| 状态 | 标题栏芯片 | 展开后底部 | 检查 |
|---|---|---|---|
| 未上课 | 绿色 **Start** | 说明文字 | [ ] |
| 上课中 | 红色 **End** + 计时 + Notes 数 | 本节信息 | [ ] |
| 已结束、未总结 | 金色 **Summary** + Notes 数 | **Summary** / **New** | [ ] |
| 总结生成中 | 等待文案 | — | [ ] |
| 总结已复制 | **Save** | **Review Note** / **Save** / **New** | [ ] |
| 已保存 | **Save** | 同上，可再存 | [ ] |

- [ ] **New** 清掉本节，回到 Start 浮窗。未总结或未保存会先确认。底部 **New** 是橙色高对比按钮。
- [ ] **Review Note** 用系统默认 App 打开预览 Markdown。蓝色按钮。
- [ ] **Save** 弹出保存面板，可改文件名、选文件夹。默认目录 `~/Documents/Lecture Copilot/`，Markdown + 同名 `shots/`。绿色按钮。
- [ ] 展开浮窗后，底部按钮都是彩色实心，白字，不能再用看不清的系统灰按钮。
- [ ] 连按两下 Shift：浮窗消失；再连按两下：按当前内容重新显示。Shift+方向键 / Shift+Return 不算双击。

---

## Class Session

- [ ] **Start Class**（浮窗或菜单）开始计时。
- [ ] 默认记录：Explain / Direct Answer / Say in Class（截图副本 + 答案）。
- [ ] **Translate 默认不记**。菜单 **Record Translate** 勾上才记。
- [ ] **End Class** 先确认，只停止计时，**不要**立刻发给豆包。
- [ ] 结束后浮窗出现 **Summary**。点了 Summary 才把记录（文本，不含图）发给豆包做总结，立刻回课堂。不想总结就点 **New**。
- [ ] 总结 prompt 禁止豆包文档 / 画布；只要当前聊天气泡里的纯文本 Markdown。
- [ ] 总结生成完后仍按 **Shift + Return** 复制进浮窗。
- [ ] 进行中的操作没结束时，不能 End / Summary（提示等当前操作结束）。
- [ ] 课节 JSON 写在 `~/Library/Application Support/Lecture Copilot/sessions/`。重启 App **不会**自动恢复「正在上课」状态。
- [ ] 启动时如果豆包 / 豆包浏览器都没开，自动打开豆包。已经在跑就不要抢到前台。

菜单 **Class Session**：

- [ ] 未上课：Start Class
- [ ] 上课中：End Class + `N notes saved`
- [ ] 已结束未总结：Summary + New Class
- [ ] 总结已复制：Save + New Class
- [ ] Record Translate
- [ ] Notes Folder

---

## 菜单栏其它项

- [ ] Class Mode 开关
- [ ] Actions：四个模式 + 灰色「Read Doubao Answer ⇧↩」+ Back to Class + 灰色「Hide / Show HUD ⇧⇧」
- [ ] Doubao：激活豆包
- [ ] Prompts：打开 `prompts.json`
- [ ] Shortcuts：弹出快捷键说明
- [ ] Last Answer：打开最后一次浮窗内容
- [ ] Translate Last Capture：用 `last-capture.png` 再翻一次，不再截图
- [ ] Inspect Doubao：导出辅助功能树
- [ ] Quit

---

## 发给豆包 / 读回答

发送：

- [ ] 交互截图进剪贴板，再粘贴进豆包输入框 + 打 prompt + 发送。
- [ ] 成功后马上 restore 课堂 App。
- [ ] 需要辅助功能。没有权限时浮窗说明，并弹出提示。
- [ ] 粘贴图时不能因为校验太严而连贴两张图。

提取（Shift+Return）：

- [ ] **Copy-first**：滚到对话底部，悬停最新回答，点复制图标。主路径不靠 OCR 当正式答案。
- [ ] 复制前用 sentinel 清剪贴板，避免把旧内容当新答案。
- [ ] Copy 图标找不到或豆包还在写：浮窗写 `Still generating...`，让人稍后再按 Shift+Return。
- [ ] 复制到的文本原样进浮窗（`prepareCopiedForDisplay`），不再当 OCR 去大幅改写。
- [ ] 剪贴板读写走主线程，避免并发崩溃。

---

## 数据落在哪

```text
~/Library/Application Support/Lecture Copilot/
  debug.log
  last-capture.png
  last-answer.txt
  last-copy-search.png
  prompts.json
  sessions/<uuid>/session.json
  sessions/<uuid>/shots/

~/Documents/Lecture Copilot/          # 用户保存的课堂笔记
```

- [ ] 源码和 git 里 **没有** `/Users/jacksonyip` 硬编码进 App 运行逻辑（文档路径除外）。
- [ ] 不把 `debug.log`、`dist/`、笔记截图提交进 git。

---

## 改完必测的最短路径

1. 打开 App，菜单栏有学士帽，浮窗是 **Start**。
2. Start Class → 芯片变红 **End**，计时走动。
3. Shift+→ 框一页英文幻灯片 → 人还在课堂 App → 豆包那边出现图+讲解 prompt。
4. 等豆包停，Shift+Return → 浮窗是 Explain 中文，End 还在。
5. 只框一个标题，Shift+← → 浮窗只有标题对照，没有整章讲义。
6. 裸 Return 在 WPS / 备忘录里仍然换行，不会去豆包。
7. End Class → 确认 → **还没发给豆包**，浮窗是 Summary。点 Summary 才发总结 → Shift+Return → **Review Note / Save / New**。
8. Save → 能改名、选位置保存。New → 回到 Start。
9. 鼠标离开浮窗变窄条，移上去向左下展开。连按两下 Shift 隐藏，再连按显示。
10. 关 Class Mode，快捷键失效。启动时豆包没开会自动打开。桌面点圆角 logo 即可打开 App，不必走命令行。
