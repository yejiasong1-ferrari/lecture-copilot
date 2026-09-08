# Lecture Copilot

**v1.0 · For Mac · 不用 API · 不消耗 tokens**

[![macOS](https://img.shields.io/badge/platform-macOS%2014%2B-black?logo=apple)](https://github.com/yejiasong1-ferrari/lecture-copilot)
[![version](https://img.shields.io/badge/version-v1.0-0A84FF)](https://github.com/yejiasong1-ferrari/lecture-copilot/releases/tag/v1.0.0)
[![license](https://img.shields.io/badge/Windows-not%20supported-lightgrey)](https://github.com/yejiasong1-ferrari/lecture-copilot)

上课听到一半，幻灯片全是英文，选择题还在倒计时——

你只要框一下屏幕，本机豆包就会帮你翻译、讲解、直接给答案。回答出现在右上角一条小浮窗里。鼠标移上去才展开，移开又缩回去，老师不一定看得出来你在看小抄。

| 不用 API | 不消耗 tokens | 安装简单 |
| :---: | :---: | :---: |
| 没有 Key，没有账单，不用去 OpenAI / Claude 注册 | 本项目不调用任何云端模型接口，不会刷你的 API quota | 打开终端，复制三行，回车。脚本自己编译、自己装 |

它**不是**一个新的 AI 网站。它只会去按你电脑里已经装好的 **豆包**，像有个隐形同学帮你复制粘贴。豆包自己聊多少，跟这个小工具无关。

> 只支持 Mac（macOS 14 或更新）。Windows 同学先别兴冲冲地下载。

---

## 你需要这三样

1. **一台 Mac**（苹果电脑）
2. **豆包电脑版**，打开过、登录过
3. **大约 5 分钟**，其中 3 分钟是在跟 macOS 权限较劲

没有豆包的话，先去装一个，打开登录好，再回来。

---

## 小白安装：就这三行

不用填 Key，不用买额度，不用注册新账号。打开电脑自带的 **终端**（`Command + 空格`，输入「终端」，回车），整段复制：

```bash
git clone https://github.com/yejiasong1-ferrari/lecture-copilot.git
cd lecture-copilot
./install.sh
```

没有 `git` 也没关系。把本仓库下载成 zip、解压，然后：

```bash
cd ~/Downloads/lecture-copilot
./install.sh
```

（如果解压出来的文件夹名不一样，把 `lecture-copilot` 改成你看到的那个名字。）

脚本会自己编译、装到「应用程序」。第一次可能会弹出 **Xcode Command Line Tools** 安装窗口——点安装，喝口水等它结束，再把上面的 `./install.sh` 运行一次。

**装完先别点开 App。** macOS 还要你亲手开两扇门。

---

## 最关键的两扇门（不做这个，App 就是个摆设）

安装脚本会打开系统设置，并把路径复制到剪贴板。路径永远是这一条：

```text
/Applications/Lecture Copilot.app
```

两扇门都打开之前，**不要打开 Lecture Copilot**。

### 第一扇：屏幕录制

用来框选老师的幻灯片。

1. **系统设置 → 隐私与安全性 → 屏幕录制与系统音频录制**
2. 点 **+**
3. 按 `Command + Shift + G`
4. 粘贴上面的路径，回车
5. 打开右边开关，变成 **蓝色**

### 第二扇：辅助功能

用来帮你把截图塞进豆包，再把答案捞回来。

1. **系统设置 → 隐私与安全性 → 辅助功能**
2. 同样点 **+**，再 `Command + Shift + G`，粘贴同一条路径
3. 开关变成 **蓝色**

两扇都蓝了，再打开 App：

```bash
open "/Applications/Lecture Copilot.app"
```

或去启动台点 **Lecture Copilot**。

菜单栏右上角会出现一顶小小的学士帽。那就是它。

第一次真正发给豆包时，电脑可能再问：要不要让它控制 **System Events**？点 **允许**。这是最后一次弹窗。

更细的步骤、卸载、翻车急救，看 [INSTALL.md](INSTALL.md)。

---

## 上课怎么用

先点学士帽，确认菜单里 **Class Mode** 打了勾。然后让课堂软件留在屏幕上，别切去豆包。

| 你按的键 | 它帮你干啥 |
|---|---|
| `Shift + ←` | **Translate** 逐句英译中，上课对照着看 |
| `Shift + →` | **Explain** 用短中文讲懂这页 |
| `Shift + ↑` | **Direct Answer** 选择题直接给答案 |
| `Shift + ↑↑`（很快连按两下） | **Say in Class** 给你一句能开口说的英文 |
| `Shift + Return` | 切到豆包，点复制，把答案读到浮窗 |
| `Shift + ↓` | 回到刚才的课堂窗口 |

推荐动作，背下来就行：

1. 按快捷键，拖一个框，把幻灯片圈进去  
2. 人继续盯着老师，别去翻豆包  
3. 感觉豆包该写完了，按 **Shift + Return**  
4. 右上角出现一条 `Answer`；鼠标移上去展开，移开就缩回去

浮窗上可以点 **Start Class**。上课后右边会一直有 **End**。Explain / Direct Answer / Say in Class 会自动记进这节课；Translate 默认不记。下课后把记录发给豆包总结，再按 **Shift + Return** 复制，可保存成 Markdown：

```text
~/Documents/Lecture Copilot/
```

它很安静。安静才是优点。

---

## 常见翻车

**窗口说没权限 / 快捷键没反应**  
回去看那两扇门是不是蓝的。重新编译过一次，就要重新加路径，不要只拨一下旧开关。

**能截图，但豆包没动静**  
辅助功能没开，或第一次问 System Events 时点了不允许。

**浮窗说还没读到回答**  
豆包可能还在写。等它停一下，再按 Shift + Return。

**我是 Windows**  
这套工具跟你无缘，去找座位上的 Mac 同学。

---

## 它不会干什么

- 不用 API Key，也不会消耗你的 ChatGPT / Claude tokens  
- 不会把你的课上传到「某个云端大模型账号」——它只去按本机豆包  
- 不会保存全部历史聊天；课堂笔记可自己保存成 Markdown，调试文件仍只留最后一次截图和回答  
- 不会替你举手发言（Speak 模式只是给你稿子）

数据在：

```text
~/Library/Application Support/Lecture Copilot/
```

完整对话还在豆包自己的聊天记录里。

---

## 开发者

```bash
./scripts/build_app.sh
```

会得到 `dist/Lecture Copilot.app`。每次重新打包，macOS 都当它是新 App，权限要重加。别人请用 `./install.sh` 装到 `/Applications`。
