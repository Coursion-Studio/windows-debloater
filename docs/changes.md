# What Windows Debloater changes

This file is generated from `src/catalog` by `scripts/build-docs.ps1`. Do not edit it by hand.

Windows Debloater only changes what you tick. Items marked **admin** are machine-wide and need the one administrator prompt; everything else applies to the signed-in user only.

## Apps

### Safe to remove

- **Clipchamp** (recommended)
  - removes the app package `Clipchamp.Clipchamp`
- **Solitaire Collection** (recommended)
  - removes the app package `Microsoft.MicrosoftSolitaireCollection`
- **Candy Crush games** (recommended)
  - removes the app package `king.com.CandyCrushSaga`
  - removes the app package `king.com.CandyCrushSodaSaga`
  - removes the app package `king.com.CandyCrushFriends`
- **News** (recommended)
  - removes the app package `Microsoft.BingNews`
- **Weather** (recommended)
  - removes the app package `Microsoft.BingWeather`
- **Bing Search** (recommended)
  - removes the app package `Microsoft.BingSearch`
- **Widgets and news feed** (recommended)
  - removes the app package `MicrosoftWindows.Client.WebExperience`
  - removes the app package `Microsoft.WidgetsPlatformRuntime`
  - removes the app package `Microsoft.StartExperiencesApp`
- **Maps** (recommended)
  - removes the app package `Microsoft.WindowsMaps`
- **Movies & TV** (recommended)
  - removes the app package `Microsoft.ZuneVideo`
- **People** (recommended)
  - removes the app package `Microsoft.People`
- **Mail and Calendar (old)** (recommended)
  - removes the app package `microsoft.windowscommunicationsapps`
- **Microsoft To Do** (recommended)
  - removes the app package `Microsoft.Todos`
- **Power Automate** (recommended)
  - removes the app package `Microsoft.PowerAutomateDesktop`
- **Dev Home** (recommended)
  - removes the app package `Microsoft.Windows.DevHome`
- **Get Help** (recommended)
  - removes the app package `Microsoft.GetHelp`
- **Tips** (recommended)
  - removes the app package `Microsoft.Getstarted`
- **Feedback Hub** (recommended)
  - removes the app package `Microsoft.WindowsFeedbackHub`
- **Quick Assist** (recommended)
  - removes the app package `MicrosoftCorporationII.QuickAssist`
- **Edge Game Assist** (recommended)
  - removes the app package `Microsoft.Edge.GameAssist`
- **Cortana** (recommended)
  - removes the app package `Microsoft.549981C3F5F10`
- **Skype** (recommended)
  - removes the app package `Microsoft.SkypeApp`
- **Mixed Reality Portal** (recommended)
  - removes the app package `Microsoft.MixedReality.Portal`
- **3D Viewer** (recommended)
  - removes the app package `Microsoft.Microsoft3DViewer`

### Your call

- **Outlook (new)**
  - removes the app package `Microsoft.OutlookForWindows`
- **Microsoft Teams**
  - removes the app package `MicrosoftTeams`
  - removes the app package `MSTeams`
- **Copilot**
  - removes the app package `Microsoft.Copilot`
- **Microsoft 365 hub**
  - removes the app package `Microsoft.MicrosoftOfficeHub`
- **Phone Link**
  - removes the app package `Microsoft.YourPhone`
  - removes the app package `MicrosoftWindows.CrossDevice`
- **Sticky Notes**
  - removes the app package `Microsoft.MicrosoftStickyNotes`
- **Sound Recorder**
  - removes the app package `Microsoft.WindowsSoundRecorder`
- **Clock**
  - removes the app package `Microsoft.WindowsAlarms`
- **Camera**
  - removes the app package `Microsoft.WindowsCamera`
- **LinkedIn**
  - removes the app package `7EE7776C.LinkedInforWindows`
- **Spotify**
  - removes the app package `SpotifyAB.SpotifyMusic`
- **Disney+**
  - removes the app package `Disney.37853FC22B2CE`
- **Prime Video**
  - removes the app package `AmazonVideo.PrimeVideo`
- **Netflix**
  - removes the app package `4DF9E0F8.Netflix`
- **TikTok**
  - removes the app package `BytedancePte.Ltd.TikTok`
- **Facebook and Instagram**
  - removes the app package `Facebook.Facebook`
  - removes the app package `Facebook.InstagramBeta`

### Xbox and gaming

- **Xbox app**
  - removes the app package `Microsoft.GamingApp`
- **Xbox Game Bar**
  - removes the app package `Microsoft.XboxGamingOverlay`
  - removes the app package `Microsoft.XboxGameOverlay`
- **Xbox sign-in helpers**
  - removes the app package `Microsoft.Xbox.TCUI`
  - removes the app package `Microsoft.XboxIdentityProvider`
  - removes the app package `Microsoft.XboxSpeechToTextOverlay`
- **Stop Game Bar pop-ups**
  - sets `HKCU\Software\Microsoft\Windows\CurrentVersion\GameDVR\AppCaptureEnabled` to `0`
  - sets `HKCU\System\GameConfigStore\GameDVR_Enabled` to `0`
  - sets `HKCU\Software\Microsoft\GameBar\UseNexusForGameBarEnabled` to `0`

## Ads and suggestions

### Promoted apps

- **Stop Windows installing promoted apps** (recommended)
  - sets `HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager\SilentInstalledAppsEnabled` to `0`
  - sets `HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager\PreInstalledAppsEnabled` to `0`
  - sets `HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager\OemPreInstalledAppsEnabled` to `0`

### Start menu and search

- **No app suggestions in Start** (recommended)
  - sets `HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager\SystemPaneSuggestionsEnabled` to `0`
  - sets `HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager\SubscribedContent-338388Enabled` to `0`
  - sets `HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\Start_IrisRecommendations` to `0`
- **No account reminders in Start** (recommended)
  - sets `HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\Start_AccountNotifications` to `0`
- **No web results in Start search** (recommended, **admin**)
  - sets `HKCU\Software\Microsoft\Windows\CurrentVersion\Search\BingSearchEnabled` to `0`
  - sets `HKCU\Software\Policies\Microsoft\Windows\Explorer\DisableSearchBoxSuggestions` to `1`

### Tips and nags

- **No tips and welcome screens** (recommended)
  - sets `HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager\SoftLandingEnabled` to `0`
  - sets `HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager\SubscribedContent-338389Enabled` to `0`
  - sets `HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager\SubscribedContent-310093Enabled` to `0`
- **No "finish setting up your device" screen** (recommended)
  - sets `HKCU\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement\ScoobeSystemSettingEnabled` to `0`
- **No suggested notifications** (recommended)
  - sets `HKCU\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\Windows.SystemToast.Suggested\Enabled` to `0`
- **No suggestions in Settings** (recommended)
  - sets `HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager\SubscribedContent-338393Enabled` to `0`
  - sets `HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager\SubscribedContent-353694Enabled` to `0`
  - sets `HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager\SubscribedContent-353696Enabled` to `0`
- **No ads in File Explorer** (recommended)
  - sets `HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\ShowSyncProviderNotifications` to `0`

### Personalised ads

- **Turn off the advertising ID** (recommended)
  - sets `HKCU\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo\Enabled` to `0`
- **No tailored experiences** (recommended)
  - sets `HKCU\Software\Microsoft\Windows\CurrentVersion\Privacy\TailoredExperiencesWithDiagnosticDataEnabled` to `0`

## Edge and widgets

### Microsoft Edge

- **Stop Edge starting with Windows** (recommended)
  - Removes the `MicrosoftEdgeAutoLaunch_*` values from `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`.
- **Turn off Edge startup boost** (recommended, **admin**)
  - sets `HKLM\SOFTWARE\Policies\Microsoft\Edge\StartupBoostEnabled` to `0`
- **Stop Edge running in the background** (recommended, **admin**)
  - sets `HKLM\SOFTWARE\Policies\Microsoft\Edge\BackgroundModeEnabled` to `0`

### Widgets

- **Block Widgets** (recommended, **admin**)
  - sets `HKLM\SOFTWARE\Policies\Microsoft\Dsh\AllowNewsAndInterests` to `0`
  - sets `HKLM\SOFTWARE\Policies\Microsoft\Dsh\DisableWidgetsBoard` to `1`
- **No widgets on the lock screen** (recommended, **admin**)
  - sets `HKLM\SOFTWARE\Policies\Microsoft\Dsh\DisableWidgetsOnLockScreen` to `1`

## Desktop and lock screen

### Lock screen

- **No tips on the lock screen** (recommended)
  - sets `HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager\RotatingLockScreenOverlayEnabled` to `0`
  - sets `HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager\SubscribedContent-338387Enabled` to `0`
- **Plain lock screen picture**
  - sets `HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager\RotatingLockScreenEnabled` to `0`
  - Sets the lock screen picture to `%SystemRoot%\Web\Screen\img100.jpg`.

### Desktop

- **Standard desktop picture**
  - Sets the desktop picture to `%SystemRoot%\Web\Wallpaper\Windows\img0.jpg` (`img19.jpg` in dark mode).

## OneDrive

### OneDrive

- **Remove OneDrive and move folders back**
  - Downloads online-only files, copies Desktop, Documents, Pictures, Music and Videos out of the OneDrive folder, runs the OneDrive uninstaller and points the known folders back at `%USERPROFILE%`.
