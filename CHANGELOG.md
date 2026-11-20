# Changelog

## 0.4.2 - 2026-11-20

Open source again, with a sharper page.

- Windows Debloater is open source under the MIT licence again, as it was up to 0.4.0, and its code is back in the public repository. Version 0.4.1 was published under Coursion Studio's own licence.
- Setup and Settings say so, and both still show the licence.
- The pictures on the project page are drawn at twice the size, as windows with their corners and shadow, and the page opens with a banner.

## 0.4.1 - 2026-11-20

The licence changes, and the tool says who makes it.

- From this version on, Windows Debloater comes under Coursion Studio's own licence. It is in `LICENSE.md`, and one click away in Setup and in Settings. Versions up to 0.4.0 were published under the MIT licence.
- Setup says that installing means agreeing to the licence, and shows the licence right there.
- Settings > About shows the copyright, the licence, the website and the support address.
- The zip now carries the README written for people who use the tool.

## 0.4.0 - 2026-11-20

A real program with an installer, Revert, and updates over the air.

- **`WindowsDebloater.exe`** takes the place of the `.cmd` file. It runs the tool's scripts inside its own process, so the window has its own name and icon in the taskbar and in Task Manager, no console window flashes up, and a problem at start-up is shown in a message. Starting it a second time brings the open window forward.
- **`WindowsDebloaterSetup.exe`** installs it: just for you, with no administrator prompt, into `%LocalAppData%\Programs\WindowsDebloater`, with a Start menu entry and an entry under Settings > Apps > Installed apps. A newer setup updates in place. Uninstalling removes exactly the files that were installed and keeps your history unless you ask otherwise. For scripts it works without its window: `/S`, `/uninstall`, `/purge`, `/desktop`, `/launch`, `/dir=`.
- The zip is still there for anyone who would rather install nothing. It now holds `WindowsDebloater.exe` in place of the `.cmd`.
- **Revert** takes the place of "Put settings back", on the finished overview and on every run in History. It puts the settings back as before, and now also brings back the apps the run removed, from the copy Windows itself keeps, and installs OneDrive again. An app Windows no longer has is named, with its Store link in History. The sheet says what will come back before anything happens.
- **Updates.** When a newer version is out, a pill appears in the top bar. It opens what is new and one button that downloads the new installer from this project's releases on GitHub, checks its SHA-256 and Coursion Studio's signature, updates in place and opens the tool again. An installer that is damaged or not signed with the update key is never run. A copy that was unpacked from the zip is pointed at the release page.
- The tool now asks the internet one thing: once a day at most, when it opens, whether there is a newer version. Settings has a switch to turn that off and a button to check by hand. A dry run and demo mode never ask. PRIVACY.md says exactly what the request carries.
- The lines under a row of the confirmation sheet now sit below it and wrap, so a longer explanation fits.
- Every release file comes with a `.sha256` file next to it, and each release carries a signed `update.json` that installed copies read.
- Both programs are built by `scripts/build-exe.ps1` with the C# compiler that is part of Windows; there is nothing to install to build them.
- Not yet: the programs are not code-signed, so Windows SmartScreen warns about a downloaded copy. Bringing apps and OneDrive back has been proven in tests with stand-ins, not yet on a real PC.

## 0.3.0 - 2026-11-20

One Debloat button, Coursion's house style, and a run you can watch.

- The overview lists the areas, each row showing what was found and how much of it is ticked, next to a panel with the number of changes that are ready and the one Debloat button.
- The sidebar is gone. A row leads to its area, every page has an Overview button to come back, and History and Settings are two buttons in the top bar.
- One main button, Debloat, applies everything ticked in every area. It is on the overview and stays at the foot of every area page.
- The recommended changes are ticked when the tool opens. A switch adds the optional ones.
- Pressing Debloat shows a short summary to confirm, replacing the separate review page.
- A new look in Coursion's house style: warm ink, or warm paper in the light theme, flat cards drawn with hairlines, monospaced labels, and one coral accent that is kept for what can be pressed and what is selected. Areas are told apart by their icons and names, not by a colour each.
- The Debloat button breathes: a soft light swells and settles behind it while a band of light travels along its rim.
- While it runs, every area is a lane that fills up. The one being worked on comes forward; a finished lane gets a tick. The full list of steps is behind Details.
- Once everything recommended is applied, the overview says what was done: when it ran, what is in place in each area, and a tick where the Debloat button was until something is ticked again.
- "Put settings back" is on that finished overview as well as in History, and now asks before it starts.
- The page icons are the soft 3D ones from Coursion's Hutch. They are plain PNG files: put your own in `design/icons` and run `scripts/import-icons.ps1` to replace them.
- A new app icon: four app tiles, one of them only an outline.
- The README opens with a film of Windows 11 before and after, and compares the two in a table. The film is made by `scripts/build-demo.ps1` from the real window; nothing is recorded from the screen.
- The window moves. Pages rise into place, rows arrive one after another and the number on the panel counts up. Buttons and rows answer the pointer, ticks draw themselves in, the switch slides, and the confirmation arrives with a small bounce.
- While debloating, the lane bars glide, each count swells as it changes, and a list under the lanes says what has just been done. The bars turn green when a run ends well.
- The PC is looked at in the background, at the start and after a run, so the window no longer stands still while it scans.
- A larger window shows the same layout bigger, up to 1.6 times, and no longer stretches it. The window opens at the size it was left at, and on Windows 11 it has rounded corners and a shadow.
- The mouse wheel glides in every list, and Ctrl+F goes to the search box of an area.
- No animations when Windows is set to show none (Settings > Accessibility > Visual effects), or on a PC that draws without a graphics card.
- Settings shows what you can change on the left and the app's details on the right.
- Dark is the default appearance.
- Keyboard: Ctrl+Enter is the main action of the current screen, Ctrl+R goes back to the recommended selection, Esc closes the confirmation or returns to the overview.
- Fixed: the overall progress bar stayed empty until a run was half done, then jumped to full.

## 0.2.0 - 2026-11-19

Renamed from Slate to Windows Debloater, with a new interface in the style of Coursion's Mac apps.

- New look: dark by default, with a light theme and an option to follow Windows.
- Home dashboard: how much there is to clean up, a one-click "Clean up recommended", and a tile per category.
- Category pages: search, select all, and "What this changes" on every item, showing the exact app package or registry value.
- Items that are already done are listed separately instead of being mixed in.
- Review: remove single items from the selection before applying.
- Progress: a step list with live status instead of a text log.
- Result: counts for done, failed and skipped, with problems listed first.
- Settings page: language, appearance, version and links. Language and theme are remembered.
- Keyboard shortcuts: Ctrl+R select recommended, Ctrl+A select all on a page, Ctrl+Enter for the main button, Esc to go back.
- App icon and its own taskbar button.
- An item that needs both administrator and normal rights is no longer marked as skipped outright when the administrator prompt is declined; its normal part still runs.

## 0.1.0 - 2026-11-18

First release, under the name Slate.

- Apps page: remove preinstalled Windows apps, grouped into "Safe to remove", "Your call" and "Xbox and gaming". Only installed apps are listed.
- Ads and suggestions page: promoted app installs, Start suggestions, tips, setup reminders, File Explorer ads, web results in Start search, advertising ID.
- Edge and widgets page: Edge autostart, startup boost and background mode; Widgets board and lock screen widgets.
- Desktop and lock screen page: plain lock screen picture without Spotlight or tips, standard desktop picture.
- OneDrive page: remove OneDrive safely and move the known folders back.
- Review step before anything is applied, with a single administrator prompt for machine-wide settings.
- History page: put the settings of an earlier run back, and reinstall removed apps from the Microsoft Store.
- Dry run and demo modes that change nothing.
- English and Turkish.
