# Lecture Copilot Stable Output Fix

这份文档记录本次问题的原因和稳定输出方案。下次如果 Lecture Copilot 又出现“截图是段落，但浮窗只显示单词翻译 / 推荐问题 / 半截内容”，优先按这里检查。

## 这次问题是什么

截图内容是一整段英文 Proposal 说明，但浮窗输出变成了：

- `核心关键词对照表`
- 只翻译少量单词
- 答案后面混入豆包推荐问题，例如“用英文写一份备忘录式提案一”
- 长回答只从中间开始显示

这不是截图权限问题。它主要来自两个地方：

1. Translate Prompt 不够强硬，豆包可能自己判断“课堂内容适合提取关键词”，于是输出了词汇表。
2. Lecture Copilot 读取豆包回答时，优先用 Accessibility；如果豆包没有把完整回答暴露给 macOS，就会 fallback 到复制按钮或 OCR。OCR 只能读当前可见窗口，所以容易读到中间内容或底部推荐问题。

如果浮窗显示：

```text
截图已经发送到豆包，但还没有读到豆包回答。
```

说明截图和发送基本已经成功，问题在读取豆包回答：

- Accessibility 读到的可能只是豆包 UI、标题或旧内容。
- “复制”按钮可能复制到的是浏览器标签页，不是回答正文。
- OCR 可能只读到当前窗口的一小块内容，或者读到的内容不符合当前模式的输出格式。

本次修复已经让自动发送优先控制 `豆包浏览器 / Doubao Browser`，并让 OCR 优先从当前底部答案区开始读取，再向上补读，减少只读到半截内容的概率。

## 2026-09-05 更新：Prompt 残片混入答案

现象：

- 浮窗开头出现 `单词规则`、`单词解释格式`、`禁止输出`。
- 浮窗开头出现一行很奇怪的乱码中文，例如 OCR 把“不要输出推荐问题...”识别坏。
- 翻译正文是对的，但中文或英文被断成多行，例如 `admission portal）` 和 `下载。` 分开。

原因：

- Translate Prompt 太长，豆包窗口中会显示很多规则。
- Copilot 用 OCR 读取豆包窗口时，可能先读到上方的 Prompt，再读到下方答案。
- OCR 会把 Prompt 里的中文规则识别成乱码，造成浮窗开头混入无关内容。

已做修复：

1. 缩短 Translate Prompt，减少规则文本在豆包窗口里占用的空间。
2. `ResponseSanitizer.swift` 会更严格删除 Prompt 残片和 OCR 乱码规则行。
3. `OutputQualityValidator.swift` 会整理 Translate 显示格式：
   - 连续英文换行会合并。
   - 连续中文换行会合并。
   - 一组英文和中文之后自动空一行。
4. `LectureCopilotController.swift` 不再把未经清洗的原始 OCR 文本直接显示到浮窗。

## 重读豆包答案快捷键

如果浮窗提示：

```text
截图已经发送到豆包，但还没有读到完整回答。
```

不要再按 `Shift + ←` / `Shift + →` / `Shift + ↑`，因为这些模式快捷键默认会重新截图。

新的处理方式：

- 等豆包生成完成。
- 直接按 `Return` / `回车`。
- Lecture Copilot 会只读取当前豆包窗口里的答案，不会重新截图，也不会重新发送图片。

`Return` 只在上一轮存在“待重读答案”的状态时生效，平时不会抢走正常输入框里的回车。

## 2026-09-05 更新：中英对照断行和返回课堂失败

不合格输出示例：

- 英文一句还没结束就被拆开。
- 中文翻译里的英文术语括号被拆成两段，例如 `（COMPUTER` 和 `CONTROL & AUTOMATION）` 分到不同段落。
- 中文句子后面粘上下一句英文，例如 `开学。 Based on your application...`。
- 翻译完成后没有自动回到截图前的页面。

已做修复：

1. `OutputQualityValidator.swift` 的 Translate 排版器会合并括号术语断行。
2. 如果中文句号后面粘了新的英文句子，会自动拆成下一组。
3. 常见 OCR 错误会被修正，例如 `Ilook` -> `I look`、`21th` -> `21st`、`| am` -> `I am`。
4. `LectureCopilotController.swift` 不再只保存 `NSRunningApplication` 对象，而是保存截图前 App 的 bundle id、路径和 pid。
5. 回到课堂窗口时会依次尝试 `NSWorkspace`、进程激活和 AppleScript 激活，减少停留在豆包窗口的概率。

## 2026-09-05 更新：单词截图被误判为“没读完整”

现象：

- 截图里只有一个英文单词，例如 `commencing`。
- 豆包已经生成了短答案，例如：

```text
commencing
开始（commencing）
课堂语境：表示课程或项目正式开始。
```

- 但 Lecture Copilot 浮窗仍显示“还没有读到完整回答”。

原因：

- 之前 Translate 模式的校验逻辑主要针对整段翻译，要求中文字符数量足够多。
- 单词解释本来就很短，所以会被误判成“不完整答案”。
- OCR 还可能把豆包底部输入框、工具栏或 Prompt 残片一起读进来，进一步影响判断。

已做修复：

1. Translate 模式现在允许短单词 / 短语答案通过，只要同时包含英文原词和中文解释。
2. 单词输出格式固定为：

```text
term
中文意思（term）
课堂语境：一句话说明它在这里怎么用。
```

3. 读取豆包窗口时，遇到 `发消息`、`按住空格`、`图像生成`、`录音转写` 等界面文字，会直接截断，不再把这些内容混进浮窗。

## 2026-09-05 更新：Explain / Direct Answer 误读截图原文

现象：

- 使用 `Shift + →` Explain 时，浮窗显示的是截图里的英文原文。
- 末尾还混入 Prompt 文字，例如 `假设我是正在上 AI / Business 研究生课程的学生，回答要简洁。`
- 这说明豆包还没生成真正解释时，Copilot 太早把 OCR 读到的截图原文当成了答案。

原因：

- Translate 模式已经有较强的格式校验，但 Explain / Direct Answer 之前只检查“有没有足够中文”。
- 如果 OCR 读到 Prompt 尾巴，里面有中文，旧逻辑就会误判为有效答案。

已做修复：

1. Explain 必须像 Explain 答案，至少包含以下结构之一：
   - `这页真正意思`
   - `老师可能想强调`
   - `重要概念`
2. Direct Answer 必须像 Direct Answer 答案，至少包含以下结构之一：
   - `直接答案`
   - `直接结论`
   - `要点`
3. Prompt 残片现在会被更严格删除或拒绝，例如：
   - `假设我是正在上...`
   - `请按这个结构回答`
   - `请只给答案`
   - `不要逐句翻译`
   - `不要翻译整页`
4. Direct Answer Prompt 已同步改成固定结构：

```text
直接答案：
...

要点：
- ...
```

## 2026-09-05 更新：Direct Answer 空标题被误判

现象：

- 使用 `Shift + ↑` 截选择题时，浮窗显示了整段题干和选项。
- 浮窗里只有空的 `直接答案：`、`要点：`，但没有真正答案。
- 豆包稍后其实生成了正确答案，例如 `正确选项是 B...`，但 Copilot 已经提前采用了更长的题干 OCR。

原因：

- 旧逻辑只要看到 `直接答案` 或 `要点` 这几个字，就认为 Direct Answer 有效。
- OCR 读到 Prompt 里的空结构标题时，也会出现这些字。
- 候选答案选择时偏向字数更长的内容，所以题干比短答案更容易被误选。

已做修复：

1. `直接答案：` 后面必须有真实内容，空标题不再算答案。
2. 如果 OCR 读到题干 + 空标题，会被拒绝。
3. 候选答案现在按“是否更像当前任务模式”评分，而不是只看字数长短。
4. Direct Answer Prompt 已明确禁止：
   - 新建题目
   - 复述题干
   - 复述全部选项
   - 举例、表格、推荐问题
5. Direct Answer 最终显示会整理为：
   - 保留 `直接答案：...`
   - 最多保留 1-2 条要点
   - 删除 OCR 读到的豆包图标，例如 `⑦』凸`

合格 Direct Answer 示例：

```text
直接答案：B. To uniquely identify each record in a table.

要点：
- 主键（primary key）用于唯一标识表中的每一条记录。
```

## 2026-09-05 更新：Say in Class 误读题干和 Prompt 要求

现象：

- 使用 `Shift + ↑↑` 时，浮窗显示整段英文题干和选项。
- 末尾混入 Prompt 内容，例如 `要求：2-4句`。
- 这不是课堂可直接说的英文回答，也没有在下面提供中文翻译。

原因：

- Say in Class 之前只粗略检查“有没有英文”，所以截图题干也会被当作答案。
- 显示层之前会 soft-accept 校验失败的内容，导致明明检测到有中文，也继续显示。

已做修复：

1. Say in Class 现在必须包含英文发言和中文翻译，但不能包含题干、选项或 `要求`。
2. 答案必须像课堂发言，通常包含：
   - `I think...`
   - `I would say...`
   - `My answer is...`
   - `The best answer is...`
3. 中文必须放在英文发言下面，作为翻译，不要变成额外解释。
4. 显示层不再 soft-accept 失败内容；不合格就继续等待豆包真正回答。
5. Say in Class Prompt 已收紧为英文发言 + 中文翻译的固定格式。

合格 Say in Class 示例：

```text
I think the best answer is B, because a primary key is used to uniquely identify each record in a table. It is like a unique ID for each row, so the database can tell records apart clearly.

中文翻译：
我认为最佳答案是 B，因为主键用于唯一标识表中的每一条记录。它就像每一行的唯一 ID，所以数据库可以清楚地区分不同记录。
```

## 稳定输出原则

每个任务模式必须有清楚边界：

- Translate 只做逐句/逐条翻译。
- Explain 只解释意思，不逐句翻译。
- Direct Answer 只给答案，不翻译整页。
- Say in Class 给 2-4 句英文课堂发言，并在下面给中文翻译。
- Back to Class 只回到上课窗口。

不要让一个模式同时做“翻译 + 解释 + 单词表 + 推荐问题”。模式混在一起，豆包最容易跑偏。

## 统一小窗版式

为了上课时更容易扫读，四个输出模式统一成固定版式：

Translate：

```text
English sentence.
对应中文翻译，重要术语写成 中文（English term）。

Next English sentence.
下一句中文翻译。
```

单词或短语：

```text
单词：term
意思：中文意思（term）
课堂语境：一句话说明它在这里怎么用。
```

Explain：

```text
这页真正意思：
...

老师可能想强调：
- ...
- ...

重要概念：
- 中文（English term）：...
```

Direct Answer：

```text
直接答案：...

要点：
- ...
- ...
```

Say in Class：

```text
英文发言：
I think ...

中文翻译：
我认为……
```

## Translate 稳定格式

只要截图里有完整句子、段落、标题、编号或 bullet，就必须使用这个格式：

```text
The proposal is worth 5% of the final grade.
提案（Proposal）占总成绩的 5%。

Write a memo proposal requesting authorization to research a real problem.
撰写一份备忘录式提案（memo proposal），申请获准调研一个真实问题。
```

只有截图几乎只有一个单词、一个短语，或少于 3 个孤立术语，并且没有完整句子时，才允许解释单词。

## 已经加入的保护

代码里现在有三层保护：

1. `PromptStore.swift` 和 `prompts.json` 的 Translate Prompt 已经明确要求逐句/逐条翻译。
2. `OutputQualityValidator.swift` 会拒绝 Translate 模式里的词汇表输出，例如 `核心关键词对照表`、`关键词表`、`词汇表`。
3. `DoubaoResponseReader.swift` 会过滤豆包推荐问题，例如“什么是...”“如何...”“用英文写...”“提供一些...”。

## 如果下次又出现

按顺序检查：

1. 打开 `Prompt Settings`，确认 `translate` 里有这些规则：
   - 必须逐句/逐条翻译
   - 必须一句英文、下一行一句中文
   - 严禁输出 `核心关键词对照表` 或任何词汇表
2. 退出并重新打开 Lecture Copilot，确保新 Prompt 被加载。
3. 如果刚刚重新 build 过 App，按照 `PERMISSION_FIX.md` 重置并重新授予权限。
4. 如果豆包里已经有完整答案，但浮窗仍只显示半截，优先怀疑读取逻辑：复制按钮失败或 OCR 只读到了可见区域。

## 相关文件

- `Sources/LectureCopilot/PromptStore.swift`
- `Sources/LectureCopilot/OutputQualityValidator.swift`
- `Sources/LectureCopilot/DoubaoResponseReader.swift`
- `~/Library/Application Support/Lecture Copilot/prompts.json`
- `MODE_SPEC.md`
- `PERMISSION_FIX.md`
