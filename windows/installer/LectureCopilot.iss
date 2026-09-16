#define MyAppName "Lecture Copilot"
#define MyAppVersion "1.1.0"
#define MyAppPublisher "Lecture Copilot"
#define MyAppExeName "Lecture Copilot.exe"

[Setup]
AppId={{77E97677-31D6-4B2D-ACD7-2248060B1E78}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={localappdata}\Programs\Lecture Copilot
DefaultGroupName=Lecture Copilot
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputDir=..\dist\installer
OutputBaseFilename=Lecture-Copilot-Windows-x64-Setup
SetupIconFile=..\LectureCopilot.Windows\Assets\AppIcon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=yes
RestartApplications=no
AppMutex=LectureCopilot.Windows.SingleInstance

[Languages]
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "快捷方式："; Flags: checkedonce
Name: "startup"; Description: "登录 Windows 时自动启动"; GroupDescription: "启动选项："; Flags: unchecked

[Files]
Source: "..\dist\win-x64\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\Lecture Copilot"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\Lecture Copilot"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon
Name: "{userstartup}\Lecture Copilot"; Filename: "{app}\{#MyAppExeName}"; Tasks: startup

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "启动 Lecture Copilot"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}"
