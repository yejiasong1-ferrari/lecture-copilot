import Foundation

final class PromptStore {
    private let defaults: [String: String] = [
        "translate": """
        只做逐句对照翻译。不要解释。

        先翻标题和正文 bullet，最后翻底部注释。不要把示意图箭头标签做成单词表。

        格式，一组空一行：
        Assumptions
        假设条件

        No back orders or partial shipments
        不允许延期交货，也不允许部分发货。

        规则：
        - 一句英文，下一行中文。长句按句拆开。
        - 术语写成 中文（English），例如 主键（primary key）、SALES（销售）表。
        - 禁止输出 PRIMARY KEY / FOREIGN KEY / PARENT TABLE / BOOKS table 这种单词表。
        - 不要翻译 ISBN、书名、作者、Cengage。
        """,
        "explain": """
        模式：Explain
        任务：用简洁中文讲懂这页课。不要逐句翻译全文。

        只输出解释。不要推荐问题，不要写长 essay。

        按这个顺序写：
        核心：
        一句话说明这页在讲什么。

        结构：
        如果有表或关系，用最少文字标出 PK / FK，例如：
        PUBLISHER
        PK: PubID
        ↓
        BOOKS
        FK: PubID

        关系：
        - 谁是 1，谁是 many
        - 用一句人话说明为什么这样连

        最重要的一句话：
        写出这页真正要记住的规则。例如：在 1:M 关系中，Foreign Key 放在 many side。

        术语写成 中文（English）。假设我是 AI / Business 研究生，要短、清楚。
        """,
        "directAnswer": """
        模式：Direct Answer
        任务：直接回答截图里的题目。不要复述题干，不要把全部选项再抄一遍，不要编新题。

        如果是选择题，必须按这个格式：
        答案：B
        原因：一句话说明为什么对。
        其他选项：
        A 错：一句话
        C 错：一句话
        D 错：一句话

        如果是问答题，必须按这个格式：
        答案：先给一句话结论。
        原因：一句话说明为什么。

        术语保留英文，必要时写成 中文（English）。
        不要写“当然/可以/来一道”，不要表格，不要推荐问题。
        """,
        "sayInClass": """
        模式：Say in Class
        任务：给一句我能在研究生课堂上直接说出口的英文。

        只按这个格式输出：
        你可以很口语地回答：
        1 到 2 句自然口语英文。像学生在说话，不要像背课文。

        要求：
        - 英文简单清楚，直接说结论和理由，例如 The foreign key goes on the many side because it links back to the primary key on the one side.
        - 可以不用 I think / I would say 开头。
        - 中文只保留“你可以很口语地回答：”这一行，下面必须是英文。
        - 不要复述题干，不要列出选项，不要写 essay，不要推荐问题。
        """
    ]

    private var cachedPrompts: [String: String]?

    func prompt(for key: String) -> String {
        if cachedPrompts == nil {
            cachedPrompts = loadPrompts()
        }
        return cachedPrompts?[key] ?? defaults[key] ?? ""
    }

    func ensureSettingsFile() -> URL {
        let url = settingsURL()
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        if !FileManager.default.fileExists(atPath: url.path) {
            write(defaults, to: url)
        }

        return url
    }

    private func loadPrompts() -> [String: String] {
        let url = ensureSettingsFile()
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return defaults
        }

        return defaults.merging(decoded) { _, custom in custom }
    }

    private func write(_ prompts: [String: String], to url: URL) {
        guard let data = try? JSONEncoder.prettyPrinted.encode(prompts) else { return }
        try? data.write(to: url)
    }

    private func settingsURL() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support
            .appendingPathComponent("Lecture Copilot", isDirectory: true)
            .appendingPathComponent("prompts.json")
    }
}

private extension JSONEncoder {
    static var prettyPrinted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
