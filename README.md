<p align="center">
  <img src="docs/assets/lecture-copilot-brand.png" width="420" alt="Lecture Copilot — Listen, Understand, Keep Up">
</p>

<h1 align="center">Lecture Copilot</h1>

<p align="center">
  <strong>老师突然点你。幻灯片全是英文。选择题还剩 12 秒。</strong><br>
  你还在课堂页面，框一下，答案出现在右上角。
</p>

<p align="center">
  不用 API Key · 不切去豆包复制粘贴 · Mac / Windows 都能用
</p>

<p align="center">
  <a href="https://github.com/yejiasong1-ferrari/lecture-copilot/releases/latest/download/Lecture-Copilot-Windows-x64-Setup.exe"><img src="https://img.shields.io/badge/Windows-下载安装包%20·%2070MB-1674EA?logo=windows&logoColor=white" alt="Download Windows installer"></a>
  &nbsp;
  <a href="https://github.com/yejiasong1-ferrari/lecture-copilot/releases/latest"><img src="https://img.shields.io/badge/macOS-一行安装-black?logo=apple" alt="Install on macOS"></a>
  &nbsp;
  <img src="https://img.shields.io/badge/version-v1.0-4F8CFF" alt="v1.0">
  <img src="https://img.shields.io/badge/API%20Key-not%20required-31B57B" alt="No API key required">
</p>

Lecture Copilot 是坐在你旁边的那个「会框屏幕的同学」。  
它不会新开一个 AI 网站，只会去按你电脑里已经登录的 **豆包**：截图、提问、把回答送回右上角小浮窗。你继续盯着老师，豆包在旁边写。

---

## 上课会遇到的四件事

| 场景 | 你按 | 它帮你干啥 |
|---|---|---|
| 这页英文完全看不懂 | `Shift + ←` | **Translate**：只翻图上看得见的字，不给你编一整章讲义 |
| 概念跳太快，没跟上 | `Shift + →` | **Explain**：用几句中文把这页讲懂，像旁边同学低声说 |
| 选择题 / 问答题倒计时 | `Shift + ↑` | **Direct Answer**：直接给答案，再补一句为什么 |
| 老师点名让你开口 | `Shift + ↑↑`（连按两下） | **Say in Class**：给你 1–2 句能马上说出口的英文 |

框完幻灯片，人继续留在 Zoom / 浏览器 / WPS。  
豆包写完后按 **`Shift + Return`**，答案进右上角浮窗。鼠标移上去才展开，移开就缩回去。

连按两下 **Shift** 可以藏起浮窗。老师走过你屏幕时，用得上。

---

## 现在就下载

### Windows 10 / 11（推荐：直接下安装包）

点这里下载，然后双击：

**[Lecture-Copilot-Windows-x64-Setup.exe](https://github.com/yejiasong1-ferrari/lecture-copilot/releases/latest/download/Lecture-Copilot-Windows-x64-Setup.exe)**

大约 70 MB，不用预装 .NET，不用管理员权限。

> 第一次 Windows 可能弹出 SmartScreen「已保护你的电脑」。确认是这个 GitHub 仓库后，点 **更多信息 → 仍要运行**。

也可以在 PowerShell 里粘贴**整行**（末尾的 `| iex` 不能少）：

```powershell
irm https://raw.githubusercontent.com/yejiasong1-ferrari/lecture-copilot/main/windows/install.ps1 | iex
```

这一行也会去 GitHub 拉那 70 MB。国内网络经常要 **2–10 分钟**，进度条看起来不动是正常的，**不要关窗口**。嫌慢就用上面的浏览器下载。

完整说明：[Windows 使用说明](windows/README.md)

### Mac（macOS 14+，Apple Silicon）

先装好并登录豆包。打开「终端」，整行粘贴：

```bash
curl -fsSL https://raw.githubusercontent.com/yejiasong1-ferrari/lecture-copilot/main/install-release.sh | bash
```

装完**先别打开**。按终端提示，把这个 App 加进：

1. **屏幕录制**
2. **辅助功能**

两个开关都蓝了，再从桌面点圆角 logo 启动。  
逐步截图见 [macOS 安装说明](INSTALL.md)。

---

## 三步就会用

1. **打开豆包，确认已经登录。** Lecture Copilot 没有自己的模型，全靠这只豆包。
2. **打开 Lecture Copilot。** 右上角出现浮窗；菜单栏 / 托盘里能看到 logo。确认 Class Mode 是开着的。
3. **上课时按快捷键 → 拖一个框圈住幻灯片 → 继续听课。** 豆包停笔后按 `Shift + Return`，看浮窗。

完整一轮大概是这样：

```text
Shift + →     圈这页英文
（人还在课堂）  豆包正在写
Shift + Return  浮窗出现中文讲解
Shift + ↓      如果焦点跑丢了，拉回课堂窗口
```

---

## 一节课怎么记

下课后不想让这节课蒸发：

1. 浮窗点绿色 **Start**，开始计时。
2. Explain / Direct Answer / Say in Class 会自动记进这节课。Translate 默认不记。
3. 下课点红色 **End**。它只停表，**不会**偷偷发给豆包。
4. 想总结再点 **Summary**；不想总结就点橙色 **New**。
5. 总结出来后按 `Shift + Return`，再点 **Save**，自己起名、选文件夹。

笔记默认在：

- Mac：`~/Documents/Lecture Copilot/`
- Windows：`文档\Lecture Copilot`

---

## 它不会做什么

- 不会要你的 OpenAI / Claude Key，也不会刷那些 tokens。
- 不会在老师眼皮底下弹出一个巨大聊天窗口。
- 不会在你按 End 的时候自作主张去写总结。
- Windows 不需要 macOS 那两扇权限门；Mac 需要，因为系统就是这么规定截图和自动操作的。

截图和 prompt 只进你本机已登录的豆包，完整对话还在豆包自己的聊天记录里。

---

## 常见问题

**PowerShell 一直停在「正在写入请求流 / Downloading…」**  
它在下载 70 MB 安装包。国内连 GitHub 很慢，进度条几乎不更新。等几分钟，或关掉窗口，改用[浏览器下载](https://github.com/yejiasong1-ferrari/lecture-copilot/releases/latest/download/Lecture-Copilot-Windows-x64-Setup.exe)。整行命令末尾必须有 `| iex`。

**快捷键没反应**  
Class Mode 要打开。Mac 还要检查辅助功能。别的软件可能抢了同一组 Shift + 方向键。

**能截图，豆包没动**  
豆包要先打开并登录。Mac 第一次会问能不能控制 System Events，选允许。Windows 上不要只把其中一个设成「以管理员运行」。

**浮窗写 Still generating**  
豆包还在写，或 Copy 按钮还没出来。等一两秒，再按一次 `Shift + Return`。

**Mac 说无法验证开发者**  
用上面的一行安装命令。当前是 ad-hoc 签名，还没有 Apple 公证。

---

## v1.0

- Mac / Windows 都能用，安装器和数据互不影响。
- Start / End / Summary / Save / New，下课再决定要不要总结。
- 双击 Shift 藏浮窗；品牌圆角 logo。
- 豆包 Copy 读取更稳；没开豆包会尝试帮你打开。

完整记录：[CHANGELOG.md](CHANGELOG.md)
