# 安装 Lecture Copilot（给完全不写代码的人）

把这份说明当成说明书。你不需要会编程。你会复制、会按回车，就够了。

更短、更好玩的介绍在 [README.md](README.md)。这里是一步都不敢跳过的版本。

---

## 先承认三件事

1. **只支持苹果电脑 Mac**，系统要 macOS 14 或更新。Windows 装了也打不开。
2. 电脑里要先有 **豆包**，并且打开登录过。没有豆包，它就是个不会说话的学士帽。
3. 装完后 macOS 会刁难你两次权限。两次都通过，它才会干活。这不是程序出错，是苹果的规矩。

---

## 一条命令（推荐）

打开 **终端**：按 `Command + 空格`，输入「终端」或 `Terminal`，回车。

从 GitHub 安装：

```bash
git clone https://github.com/yejiasong1-ferrari/lecture-copilot.git
cd lecture-copilot
./install.sh
```

如果只是下载了 zip：解压后把文件夹拖进终端窗口，再输入：

```bash
./install.sh
```

文件夹在桌面时，也可以：

```bash
cd ~/Desktop/"Lecture Copilot"
./install.sh
```

脚本会检查系统、编译、装到：

```text
/Applications/Lecture Copilot.app
```

然后把这条路径复制到剪贴板，并打开系统设置。

中间如果弹出 **安装命令行工具**，点安装，等它结束，再运行一次 `./install.sh`。不必去装整个 Xcode，那个太大了。

**看到 Install finished 之后先不要打开 App。** 往下做权限。

---

## 安装前还可以再确认一下

### 1. 真的是 Mac 吗

左上角苹果菜单 → 关于本机。需要 macOS 14 Sonoma 或更新。

### 2. 豆包电脑版

到豆包官网下载 Mac 版，装进「应用程序」。先自己打开一次、登录好。Lecture Copilot 只会去按这台电脑上的豆包。

### 3. 命令行工具

编译需要苹果的小工具箱，**不必安装完整 Xcode**。没有的话，运行：

```bash
xcode-select --install
```

---

## 权限（必须，两扇门都要开）

macOS 不会自动放行。请把**这一条精确路径**加进去：

```text
/Applications/Lecture Copilot.app
```

安装脚本已经把它复制到剪贴板。两个开关都变成蓝色之前，**不要打开 App**。

### 第一扇：屏幕录制

用来框选老师的幻灯片。

1. **系统设置 → 隐私与安全性 → 屏幕录制与系统音频录制**
2. 点 **+**
3. 按 `Command + Shift + G`（前往文件夹）
4. 粘贴路径，回车，打开
5. 右边开关变成蓝色

### 第二扇：辅助功能

用来把截图塞进豆包，再把答案捞回来。

1. **系统设置 → 隐私与安全性 → 辅助功能**
2. 同样点 **+**，再 `Command + Shift + G`，粘贴同一条路径
3. 开关变成蓝色

### 然后才能打开 App

```bash
open "/Applications/Lecture Copilot.app"
```

或去启动台点 **Lecture Copilot**。菜单栏右上角会出现小小的学士帽。

第一次发给豆包时，电脑可能问：要不要控制 **System Events**？点 **允许**。

如果点了不允许，去 **系统设置 → 隐私与安全性 → 自动化** 里打开它。

---

## 上课怎么用

点学士帽，勾选 **Class Mode**。课堂软件留在前台。

| 你按的键 | 它帮你干啥 |
|---|---|
| `Shift + ←` | Translate，逐句英译中 |
| `Shift + →` | Explain，讲懂这页 |
| `Shift + ↑` | Direct Answer，直接答题 |
| `Shift + ↑↑`（0.6 秒内连按两下） | Say in Class，能开口说的英文 |
| `Return` | 豆包写完后，把答案读到浮窗 |
| `Shift + ↓` | 回到刚才的课堂窗口 |

推荐动作：

1. 按快捷键，框选幻灯片
2. 人继续听课，别去翻豆包
3. 感觉它写完了，按 **Return**
4. 右上角出现 `Answer`；鼠标移上去展开，移开就缩回去

---

## 文件在哪

App：

```text
/Applications/Lecture Copilot.app
```

最后一次截图和回答：

```text
~/Library/Application Support/Lecture Copilot/
```

| 文件 | 作用 |
|---|---|
| `last-answer.txt` | 最后一次回答 |
| `last-answer.png` | 浮窗截图 |
| `last-capture.png` | 最后一次框选 |
| `prompts.json` | 四种提问词，可自己改 |
| `debug.log` | 翻车时看这个 |

它只留最后一次。完整聊天在豆包历史里。

---

## 更新之后权限会丢

再运行 `./install.sh` 或 `./scripts/build_app.sh`，macOS 会把 App 当成新软件。必须重新加路径，不要只拨旧开关。

---

## 卸载

```bash
pkill -f "Lecture Copilot.app/Contents/MacOS/Lecture Copilot" || true
rm -rf "/Applications/Lecture Copilot.app"
rm -rf "$HOME/Library/Application Support/Lecture Copilot"
```

系统设置里如果还留着它，删掉即可。

---

## 翻车急救

**菜单栏没有学士帽**  
确认 App 已打开。关掉 Class Mode 时帽子会消失。

**快捷键没反应**  
Class Mode 要打勾，辅助功能要蓝。

**能截图，豆包没动静**  
辅助功能或 System Events 没开。

**浮窗说还没读到回答**  
再等一会儿，再按 Return。

**开关是蓝的，App 仍说没权限**  
重新编译过。退出 App，重新添加路径。

**提示缺少 swift**  
`xcode-select --install`，装完再 `./install.sh`。

**找不到豆包**  
装到 `/Applications`，打开登录一次。

---

## 发给同学的三行

```bash
git clone https://github.com/yejiasong1-ferrari/lecture-copilot.git
cd lecture-copilot
./install.sh
```

然后把剪贴板里的路径加进「屏幕录制」和「辅助功能」，两个开关打开后再打开 App。
