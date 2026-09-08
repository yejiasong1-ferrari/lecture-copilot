# Lecture Copilot Mode Spec

这份文档定义 Lecture Copilot v1.0 每个快捷键模式的稳定输出规则。以后如果输出跑偏，优先检查这里和 `PromptStore.swift` / `prompts.json` 是否一致。

## Translate: Shift + Left

目标：把截图里的英文内容翻译成中文，方便上课时快速对照阅读。

默认行为：

- 只要截图里有完整句子、段落、标题、编号或 bullet，就必须逐句/逐条翻译。
- 保留原来的标题、编号和项目符号结构。
- 每条按固定格式输出：一句英文，下一行一句中文，然后空一行再继续。不要写“英文：”“中文：”标签。重要关键词写成 中文（English term）。

```text
The proposal is worth 5% of the final grade.
提案（Proposal）占总成绩的 5%。

Write a memo proposal requesting authorization to research a real problem.
撰写一份备忘录式提案（memo proposal），申请获准调研一个真实问题。
```

单词行为：

- 只有截图几乎只有一个单词、一个短语，或少于 3 个孤立术语，并且没有完整句子时，才解释单词。
- 格式：

```text
单词：term
意思：中文意思（term）
课堂语境：一句话说明它在这里怎么用。
```

禁止：

- 不要输出“核心关键词对照表”。
- 不要只挑关键词翻译。
- 不要合并成总结。
- 不要添加截图外信息。
- 不要输出推荐问题、延伸问题或“以下是翻译”。

## Explain: Shift + Right

目标：解释截图内容，而不是逐句翻译。

输出风格：

一段中文，像同学在旁边把这页讲懂。不要逐句翻译，不要「核心 / 结构 / 关系」小标题。

例如：

```text
这页的意思是：数据库里的两张表可以通过一个相同的字段连接起来。比如 PUBLISHER 表里的 PubID 是主键（primary key），用来唯一识别每个出版社；BOOKS 表里也有一个 PubID，但它是外键（foreign key），用来表示这本书属于哪个出版社。因为一个出版社可以出版很多本书，所以这是一个 1:M 的关系，而外键通常放在 many side，也就是 BOOKS 表里。
```

禁止：

- 不要逐句翻译整页。
- 不要写长篇 essay。
- 不要输出推荐问题。

## Direct Answer: Shift + Up

目标：快速回答截图里的课堂问题、讨论题或作业问题。

输出结构：

```text
直接答案：
...

要点：
- ...
- ...
```

规则：

- 先给结论。
- 最多 1-2 个要点。
- 保留关键英文术语，用 中文（English term）对应。

禁止：

- 不要翻译整页。
- 不要展开背景。
- 不要输出推荐问题。

## Say in Class: Shift + Up, Up

目标：把问题转换成可以课堂直接说的英文回答，并在下面给中文翻译，方便确认意思。

输出结构：

```text
英文发言：
I think ...
...

中文翻译：
我认为……
```

规则：

- 英文发言在上面，中文翻译在下面。
- 英文发言 2-4 句。
- 英文自然、简单、口语化。
- 有明确观点和简单理由。

禁止：

- 不要复述题干或选项。
- 不要 essay 风格。
- 不要推荐问题。

## Back to Class: Shift + Down

目标：回到上一次课堂窗口，例如 Zoom、Teams、Chrome 或 Canvas。

规则：

- 每次执行 Translate / Explain / Direct Answer / Say in Class 前保存 `previousActiveApp`。
- Shift + Down 激活 `previousActiveApp`。

## Reading Strategy

读取豆包回答的顺序：

1. Accessibility 读取 `Doubao Browser` 和 `Doubao` 可见文本。
2. 如果读到的是页面标题、菜单、帮助、prompt 残片，则忽略。
3. 如果读不到有效回答，尝试点击豆包回答附近的“复制”按钮，直接拿完整文本。
4. 如果复制失败，使用 macOS Vision OCR 截取豆包窗口。
5. OCR 结果必须过滤侧边栏、底部工具栏、推荐追问。

## Known Pitfalls

- 本地 ad-hoc 签名 app 每次 rebuild 后，macOS 可能把它当成新 app，导致权限开关看起来是蓝色但实际不可用。
- 出现权限循环时，按照 `PERMISSION_FIX.md` 重置 ScreenCapture / Accessibility / AppleEvents。
- OCR 只能读取当前窗口可见内容，长回答可能不如“复制按钮”稳定。
