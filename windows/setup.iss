; SEE THE DOCUMENTATION FOR DETAILS ON CREATING INNO SETUP SCRIPT FILES!

#define MyAppVersion GetEnv("VERSION")
#define MyAppPublisher "Gephyra OÜ"
#define MyAppURL "https://geph.io/"
#define MyAppExeName "gephgui-wry.exe"

[Setup]
AppId={{09220679-1AE0-43B6-A263-AAE2CC36B9E3}
AppName={cm:MyAppName}
AppVersion={#MyAppVersion}
;AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={pf}\{cm:MyAppName}
DefaultGroupName={cm:MyAppName}
OutputBaseFilename=geph-windows-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=classic
; The privileged manager (geph5.exe register-manager) needs admin; force elevation.
PrivilegesRequired=admin
; Let the Restart Manager close a running GUI (e.g. during a /SILENT self-update)
; so its locked files can be replaced.
CloseApplications=yes

[Languages]
Name: "en"; MessagesFile: "compiler:Default.isl"
Name: "zht"; MessagesFile: "ChineseTraditional.isl"
Name: "zhs"; MessagesFile: "ChineseSimplified.isl"

[CustomMessages]
en.MyAppName=Geph
zht.MyAppName=迷霧通
zhs.MyAppName=迷雾通

[Tasks]
; ①  Default‑ON desktop icon —— just drop the “unchecked” flag.
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[InstallDelete]
Type: filesandordirs; Name: "{app}\*"

[Files]
; Everything in blobs\win-ia32 ships into {app}: the build-staged binaries
; (gephgui-wry.exe GUI, geph5.exe manager, geph5-client.exe engine) plus the
; vendored wintun.dll and MicrosoftEdgeWebview2Setup.exe bootstrapper.
Source: "..\blobs\win-ia32\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; NOTE: WinDivert + winproxy are gone — the manager uses WinTUN + WFP and
; configures the system proxy itself (geph5 __apply-proxy).
; NOTE: Don't use "Flags: ignoreversion" on any shared system files

[Icons]
Name: "{group}\{cm:MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{cm:MyAppName}}"; Filename: "{uninstallexe}"
Name: "{commondesktop}\{cm:MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon
; Start the GUI at every login, hidden to the tray. The manager already autostarts
; at boot (the "Geph Manager" task), so the tray is always present whenever the
; tunnel is up. This is an all-users Startup shortcut ({commonstartup}) rather
; than an HKCU "Run" value because the installer runs elevated — an HKCU write
; would land in the admin's hive, not the logged-in user's. `--hidden` makes the
; GUI come up as just the tray icon. The shortcut is removed on uninstall.
Name: "{commonstartup}\{cm:MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Parameters: "--hidden"

[Run]
; ①  Register + start the privileged background manager. This creates the
;     "Geph Manager" scheduled task (LocalSystem, runs at boot) and starts it now.
;     Reuses geph5-app `service::register` — do NOT duplicate the schtasks XML here.
Filename: "{app}\geph5.exe"; Parameters: "register-manager"; StatusMsg: "Registering the Geph manager..."; Flags: runhidden waituntilterminated
; ②  WebView 2 bootstrapper (unchanged)
Filename: "{app}\MicrosoftEdgeWebview2Setup"; StatusMsg: "Installing WebView2..."; Parameters: "/install"; Check: WebView2IsNotInstalled
; ③  Optional *Launch Geph* checkbox on the finished page — default checked.
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{cm:MyAppName}}"; Flags: postinstall nowait skipifsilent

[UninstallRun]
; Stop + delete the "Geph Manager" scheduled task (reuses `service::unregister`)
; before the files it points at are removed.
Filename: "{app}\geph5.exe"; Parameters: "unregister-manager"; RunOnceId: "UnregGephManager"; Flags: runhidden waituntilterminated

[Code]
function WebView2IsNotInstalled: Boolean;
  var Pv: String;
  var key64: String;
  var key32: String;
begin
    key64 := 'SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}';
    key32 := 'SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}';
    Result := True;
    if RegQueryStringValue(HKEY_LOCAL_MACHINE, key64, 'pv', Pv) then
    begin
        Result := 0 = Length(pV);
    end
    else begin
       if RegQueryStringValue(HKEY_LOCAL_MACHINE, key32, 'pv', Pv)  then
       begin
          Result := 0 = Length(pV);
       end;
    end;
end;

// Best-effort: stop a previously-installed manager and any running GUI so their
// files aren't locked when [InstallDelete] wipes {app} and the new files land.
procedure StopRunningGeph;
  var ResultCode: Integer;
  var GephExe: String;
begin
  GephExe := ExpandConstant('{app}\geph5.exe');
  if FileExists(GephExe) then
    Exec(GephExe, 'unregister-manager', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  // `unregister-manager` does `schtasks /End`, which TerminateProcess'es the manager
  // without running its graceful child-teardown, so the engine child orphans and
  // keeps geph5-client.exe locked. Kill it (and the manager, as a backstop) directly
  // so [InstallDelete] / the file copy can replace them. Older managers predate the
  // kill-on-close job object that now prevents this, so this stays load-bearing for
  // upgrades from them.
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /IM geph5-client.exe', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /IM geph5.exe', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  // Free the GUI exe (a running instance, or the launcher of a silent self-update).
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /IM gephgui-wry.exe', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
end;

// Runs before [InstallDelete] and file copy.
function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  StopRunningGeph();
  Result := '';
end;

// Runs at the very start of uninstall. The manager itself is torn down by the
// [UninstallRun] entry above; here we just free the GUI exe.
function InitializeUninstall(): Boolean;
  var ResultCode: Integer;
begin
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /IM gephgui-wry.exe', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Result := True;
end;
