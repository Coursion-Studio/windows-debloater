<p align="center">
  <img src="docs/banner.png" alt="Windows Debloater: a clean start for Windows 11" width="100%">
</p>

<p align="center">
  <a href="https://github.com/Coursion-Studio/windows-debloater/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/Coursion-Studio/windows-debloater?style=flat-square&color=ff7a59"></a>
  <a href="https://github.com/Coursion-Studio/windows-debloater/releases"><img alt="Downloads" src="https://img.shields.io/github/downloads/Coursion-Studio/windows-debloater/total?style=flat-square&color=e04a8b"></a>
  <img alt="Windows 11" src="https://img.shields.io/badge/Windows-11-0078d4?style=flat-square&logo=windows">
  <img alt="No admin needed to install" src="https://img.shields.io/badge/install-no%20admin%20needed-2ecc71?style=flat-square">
  <a href="LICENSE.md"><img alt="MIT licence" src="https://img.shields.io/badge/licence-MIT-22c55e?style=flat-square"></a>
</p>

<p align="center">
  <b>A clean start for Windows 11.</b><br>
  Remove the apps nobody asked for and switch off ads and suggestions, with one button.<br>
  You confirm before anything changes, and <b>Revert</b> puts it back.
</p>

<p align="center">
  <a href="https://github.com/Coursion-Studio/windows-debloater/releases/latest"><b>⬇ Download Windows Debloater</b></a>
  &nbsp;·&nbsp; <a href="#-install">Install</a>
  &nbsp;·&nbsp; <a href="#-windows-11-before-and-after">Before and after</a>
  &nbsp;·&nbsp; <a href="#-features">Features</a>
  &nbsp;·&nbsp; <a href="#-screenshots">Screenshots</a>
  &nbsp;·&nbsp; <a href="#-faq">FAQ</a>
</p>

---

<p align="center">
  <img src="docs/demo.gif" alt="Windows 11 as it comes, Windows Debloater at work, and the same PC afterwards" width="100%">
  <br><sub><b>See it in action:</b> Windows 11 as it comes, one press of Debloat, and what is left. The window is the real one; the desktop around it is a sketch.</sub>
</p>

## 🚀 Install

1. Download **`WindowsDebloaterSetup-x.y.z.exe`** from the [latest release](https://github.com/Coursion-Studio/windows-debloater/releases/latest).
2. Open it and click **Install**. It installs just for you, so **no admin rights** are needed.
3. Windows Debloater opens. Press **Debloat**, read the summary, and press **Debloat now**.

<p align="center">
  <img src="docs/img/setup.png" width="49%" alt="Windows Debloater Setup">
  <img src="docs/img/setup-done.png" width="49%" alt="Windows Debloater is installed">
</p>

Setup adds Windows Debloater to the **Start menu** and registers it under **Settings → Apps → Installed apps**.
It **updates itself**: it checks once a day and installs a new version with one click. Every update is signed by Coursion Studio.

> **"Windows protected your PC"?** This SmartScreen warning appears because the installer isn't code-signed yet.
> Click **More info → Run anyway**. Each release includes a `.sha256` file so you can verify the download.

**Without installing:** download `WindowsDebloater-x.y.z.zip` instead, unpack it anywhere and open `WindowsDebloater.exe`. It is the same program.

**Uninstall:** **Settings → Apps → Installed apps → Windows Debloater → Uninstall**. You can choose whether to keep your history. Uninstalling does not undo what the tool changed; use **Revert** for that first.

**Requirements:** Windows 11. Nothing else needs installing.

## 🪟 Windows 11 before and after

What Windows 11 does as it comes, and what is left after one press of **Debloat**. Which apps a PC ships with depends on its edition, region and maker; the tool only lists what it actually finds.

| | Windows 11 as installed | After Windows Debloater |
|---|---|---|
| **Start menu** | Promoted apps pinned for you, more installed quietly, plus suggestions and sign-in reminders. | Only what you put there. |
| **Start search** | Web results from Bing mixed into what you type. | Searches this PC. |
| **Preinstalled apps** | Clipchamp, Solitaire, Candy Crush, News, Weather, Maps, To Do, Feedback Hub, Get Help and more. | Removed. Revert brings any of them back. |
| **Widgets** | A taskbar button with a news feed behind it, and news cards on the lock screen. | Blocked, in both places. |
| **Lock screen** | Fun facts, tips and promotions over the picture. | Just the picture. |
| **Microsoft Edge** | Starts with Windows, preloads at sign-in, keeps running after you close it. | Starts when you open it, stops when you close it. Edge stays installed. |
| **File Explorer** | Promotions for OneDrive and Microsoft 365. | None. |
| **Settings app** | Suggested content between the settings. | None. |
| **Tips and nags** | Tips, welcome screens after updates, "finish setting up your device". | Off. |
| **Advertising** | An advertising ID apps can read, and ads tailored from diagnostic data. | Both off. |

That is the recommended selection: 40 changes, ticked when the tool opens. Another 23 are there if you want them and are never applied unless you tick them.

<details>
<summary><b>The 23 optional changes</b></summary>

| Optional | What ticking it does |
|---|---|
| Apps that are a matter of taste | Removes Outlook (new), Teams, Copilot, the Microsoft 365 hub, Phone Link, Sticky Notes, Camera, Clock and Sound Recorder, and promoted apps such as Spotify, Netflix, Disney+, Prime Video, TikTok, LinkedIn, Facebook and Instagram. |
| Xbox and gaming | Removes the Xbox app, Xbox Game Bar and the Xbox sign-in helpers, and stops the pop-ups that follow when Game Bar is gone. |
| Lock screen and desktop pictures | Replaces Windows Spotlight and the desktop picture with the standard Windows pictures. |
| OneDrive | Downloads files that exist only online, moves Desktop, Documents and Pictures back to their normal folders and removes OneDrive. |
</details>

No promises about speed, memory or disk space: none of that has been measured. What changes is what you see, what asks for your attention, and what starts without being asked.

## ✨ Features

|   |   |
|---|---|
| 🧹 **One button** | **Debloat** applies everything that is ticked, in every area, after one confirmation. The recommended changes are ticked when the tool opens. |
| ✅ **You confirm first** | A short summary says what will happen. Nothing changes until you press **Debloat now**. |
| ↩️ **Revert** | Undo a whole run: settings go back to the values they had, the apps it removed come back, and OneDrive is installed again. |
| 🔍 **Nothing hidden** | Every item has a **What this changes** line with the exact app package or registry value. The complete list is in [docs/changes.md](docs/changes.md), and the code is all here. |
| 📦 **Only what is there** | It looks at your PC first and lists only the apps and settings it actually finds. |
| 🛡️ **Careful with OneDrive** | Online-only files are downloaded first, your folders are copied back, and nothing is deleted. Work and school accounts are left alone. |
| 🔄 **Automatic updates** | Checks once a day, shows what's new, and installs with one click. Every update is signed by Coursion Studio. |
| 🔒 **Private** | It does its work on your PC. No account, no analytics, no telemetry. The only network call is the daily update check, and Settings can switch it off. |
| 🌍 **English and Turkish** | It starts in your Windows language, with a dark and a light look. |

## 📸 Screenshots

<p align="center">
  <img src="docs/img/home.png" width="100%" alt="The overview: five areas, how much is ticked, and the Debloat button">
</p>

A row opens its area, where you choose exactly what is ticked. Before anything happens, the summary asks you to confirm.

<p align="center">
  <img src="docs/img/apps.png" width="49%" alt="An area page: the preinstalled apps found on this PC">
  <img src="docs/img/confirm.png" width="49%" alt="The summary to confirm before anything changes">
</p>

While it works, each area is a lane that fills up. Afterwards the overview shows what is in place, with **Revert** to undo the run.

<p align="center">
  <img src="docs/img/progress.png" width="49%" alt="Debloating: one lane per area">
  <img src="docs/img/home-done.png" width="49%" alt="The overview after debloating">
</p>

Revert says what comes back before it starts, and a newer version announces itself in the top bar.

<p align="center">
  <img src="docs/img/revert.png" width="49%" alt="Revert asks first and says what comes back">
  <img src="docs/img/update.png" width="49%" alt="The update sheet">
</p>

## ⌨️ Shortcuts

| Action | Keys |
|---|---|
| The main action of the screen you are on: Debloat, Debloat now, Done | <kbd>Ctrl</kbd>+<kbd>Enter</kbd> |
| Go back to the recommended selection | <kbd>Ctrl</kbd>+<kbd>R</kbd> |
| Tick everything in the current area | <kbd>Ctrl</kbd>+<kbd>A</kbd> |
| Search the current area | <kbd>Ctrl</kbd>+<kbd>F</kbd> |
| Close the confirmation, clear the search box, or return to the overview | <kbd>Esc</kbd> |

## ❓ FAQ

<details>
<summary><b>Can I undo it?</b></summary>

Yes. Press **Revert** on the overview after a run, or open **History** and press **Revert** on any earlier run. Settings always go back to the values they had. Apps come back from the copy Windows itself keeps; if Windows no longer has one, History has a link to that app in the Microsoft Store. OneDrive is installed again, but your folders are not moved back into it: that is yours to choose in OneDrive after signing in.
</details>

<details>
<summary><b>Why does Windows ask for administrator permission?</b></summary>

Installing never needs it. A run asks once, and only if you ticked a machine-wide setting; those are marked **Needs administrator**. Everything else runs as you.
</details>

<details>
<summary><b>Settings now says "Some of these settings are managed by your organisation".</b></summary>

A few changes are set the way a company would set them, as a policy, because that is the only switch Windows offers: blocking Widgets, web results in Start search, and the Edge settings. Windows shows that line wherever a policy is in place. **Revert** removes them again.
</details>

<details>
<summary><b>Does it remove Edge, Defender or the Microsoft Store?</b></summary>

No. Edge stays installed because parts of Windows need it; the tool only stops it starting and running by itself. It does not touch Microsoft Defender, Windows Update or the Store.
</details>

<details>
<summary><b>Will a Windows update bring things back?</b></summary>

It can. A big Windows update sometimes reinstalls an app or resets a setting. Open Windows Debloater again: it lists only what is there now, so one more press of **Debloat** deals with it.
</details>

<details>
<summary><b>Can I try it without changing anything?</b></summary>

Yes. Press <kbd>Win</kbd>+<kbd>R</kbd> and run `"%LocalAppData%\Programs\WindowsDebloater\WindowsDebloater.exe" -Demo`. Demo mode pretends everything still needs doing and changes nothing, so you can go through the whole window, Revert included. `-DryRun` does the same against the real state of your PC.
</details>

<details>
<summary><b>How do I turn off the update check?</b></summary>

**Settings → Check for updates when the tool opens**. With it off, nothing is asked of the internet until you press **Check for updates now** yourself. What the check sends is in [PRIVACY.md](PRIVACY.md).
</details>

<details>
<summary><b>Where does it keep its files?</b></summary>

The program is in `%LocalAppData%\Programs\WindowsDebloater`. Its history, with the old value of every setting it changed, is in `%LocalAppData%\WindowsDebloater`; that is what Revert reads.
</details>

<details>
<summary><b>Has it been tested?</b></summary>

It was built and checked on Windows 11 Pro 25H2. The test suite runs the whole window in a dry run and installs, updates and uninstalls the program in a scratch folder. Two things have not been proven on a real PC yet: Revert bringing apps and OneDrive back, which is new, and the tool as a whole on other editions of Windows 11. Windows Sandbox or a virtual machine is the safe place to try it first.
</details>

## 🛠️ Build from source

There's nothing to install, because the C# compiler that ships with Windows is enough.

```powershell
git clone https://github.com/Coursion-Studio/windows-debloater.git
cd windows-debloater
.\WindowsDebloater.cmd -Demo                                      # run from source, changing nothing
powershell -ExecutionPolicy Bypass -File test\Run-Tests.ps1       # the tests
powershell -ExecutionPolicy Bypass -File scripts\build-exe.ps1    # -> bin\WindowsDebloater.exe and bin\WindowsDebloaterSetup.exe
```

The tests change nothing on the PC apart from a scratch registry key they create and delete. The installer is tried inside a temporary folder, away from the real Start menu and the list of installed apps.

| Path | What's inside |
|---|---|
| `src/Debloater.Engine.psm1` | Catalog, scan, apply, revert and the update check. No window code. |
| `src/Debloater.UI.ps1`, `src/ui/MainWindow.xaml` | The window: its behaviour, and its layout with every visual style. |
| `src/catalog/` | Everything the tool can change, as JSON. Adding an app or a setting is usually a change here plus its texts. |
| `src/lang/` | Texts, one file per language. To add a language, copy `en.json` and translate the values. |
| `exe/` | `WindowsDebloater.exe`: runs the scripts in `src` inside its own process. |
| `setup/` | `WindowsDebloaterSetup.exe`: install, update and uninstall. |
| `scripts/` | Building the programs, the release, the README pictures and the film at the top of this page. |
| `test/` | The tests, and one that applies every setting for real inside Windows Sandbox. |

How it works: the window never changes the PC itself. It writes a plan and starts hidden PowerShell workers, one without elevation for per-user changes and one elevated for machine-wide settings. Each worker reports progress as lines of JSON and records every change before making it, which is what Revert reads.

Releases are signed. `scripts\build-release.ps1` needs the private half of the update key, which only the maintainer has; everything else builds without it. A copy you build yourself will only accept updates signed with that key.

## 🐛 Issues & feedback

Open an issue on this repo, or email [support@coursion.studio](mailto:support@coursion.studio).

## 📄 Licence

MIT. See [LICENSE.md](LICENSE.md). © 2026 Coursion Studio.
Questions: [support@coursion.studio](mailto:support@coursion.studio) · [coursion.studio](https://coursion.studio)
