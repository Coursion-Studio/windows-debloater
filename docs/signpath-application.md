# SignPath Foundation application: draft

This is a draft for the maintainer to submit at <https://signpath.org/apply>. Nothing has been sent. Check every answer against the current form, since the fields may differ.

## Before applying

- [ ] Two-factor authentication is on for the GitHub account that owns or maintains `Coursion-Studio/windows-debloater`, and is required for the organisation (Settings > Authentication security).
- [ ] The README links to [CODE_SIGNING_POLICY.md](../CODE_SIGNING_POLICY.md), and both carry the line "Free code signing provided by SignPath.io, certificate by SignPath Foundation".
- [ ] The CI workflow on `main` is green (Actions > CI), so the reviewers can see the build is fully automated.
- [ ] At least one release has been built by `.github/workflows/release.yml`, unsigned, so they can see that releases come out of CI.
- [ ] Optional but helpful: a few weeks of activity, some issues or stars, and a release or two. The Foundation looks at whether a project is maintained and used. The repository is new, so that is the weakest point of this application.

## Answers

**Project name**
Windows Debloater

**Repository URL**
https://github.com/Coursion-Studio/windows-debloater

**Project homepage**
https://github.com/Coursion-Studio/windows-debloater

**License**
MIT (OSI-approved). See `LICENSE.md`.

**Short description**
Windows Debloater gives Windows 11 a clean start. It removes preinstalled apps and switches off ads and suggestions with one button. The user confirms before anything changes, and every run can be reverted, including bringing removed apps back.

**What will be signed**
- `WindowsDebloater.exe`, a small .NET Framework launcher, compiled from `exe/WindowsDebloater.cs`. It hosts Windows PowerShell and runs the project's scripts.
- The PowerShell scripts in `src/` (`Debloater.ps1`, `Debloater.UI.ps1`, `Debloater.Engine.psm1`). They do the actual work, and machine-wide changes run elevated. They ship as loose files in the release zip and inside the installer, so signing them matters as much as signing the executable.
- `WindowsDebloaterSetup.exe`, the per-user installer and uninstaller, compiled from `setup/`. It embeds the signed program and scripts.

No third-party or proprietary components are included or signed. Everything is built from this repository's source with the C# compiler that ships with Windows (`csc.exe`, .NET Framework 4.x).

**How is it built?**
Fully automated with GitHub Actions on `windows-latest`:
- `.github/workflows/ci.yml` runs on every push and pull request. It runs the test suite (`test/Run-Tests.ps1`) and builds and packages the release unsigned.
- `.github/workflows/release.yml` runs on `v*` tags. It runs the tests and builds the programs. It submits the program and scripts to SignPath (artifact configuration `payload`), rebuilds the installer around the signed files, and submits the installer (artifact configuration `installer`). Then it checks every signature and creates a draft GitHub release.

Both artifact configurations are in the repository under `.signpath/`. The signing steps are already in the workflow and are switched on by the repository variable `SIGNING=signpath` once the project is approved.

**Is anything built or modified outside CI?**
No binary is. The only release step on the maintainer's machine is writing `update.json`, the tool's own update feed. It holds an RSA signature over the installer's bytes, made with a private update key that is deliberately never uploaded to GitHub. That step downloads the CI-built, SignPath-signed installer, checks its SHA-256, and signs it as-is. It doesn't change or rebuild any file.

**Signing policy / approval**
Every signing request needs manual approval (signing policy `release-signing`). Only requests from tag builds of this repository's release workflow are approved. The policy and team roles are in `CODE_SIGNING_POLICY.md`.

**Maintainers / team**
Coursion Studio, maintained by @kuraydev on GitHub, who is committer, reviewer and approver. Multi-factor authentication is enforced on GitHub and will be on SignPath.

**Does the software download or run other code?**
Its own updates only. Once a day at most, unless switched off in Settings, it reads `update.json` from this project's latest GitHub release. An update is installed only when the user presses "Update now". The installer is run only if its SHA-256 matches and it carries the project's update-key signature. It also runs built-in Windows components (PowerShell, the Appx cmdlets, registry edits) to make the changes the user confirms. See `PRIVACY.md`.

**Does it need administrator rights? Why?**
The installer doesn't: it installs per user. The tool asks for elevation only for machine-wide settings the user picked (for example policies under `HKLM`). It does that by starting an elevated PowerShell worker for those items. Everything it changes is recorded first so it can be reverted.

**Why does the project need code signing?**
The tool runs PowerShell scripts with administrator rights. Users should be able to verify that what they run is the project's published, unmodified code. An unsigned release currently triggers SmartScreen's "unknown publisher" warning. Signing gives users a verifiable publisher, and lets Windows and antivirus products build reputation across releases.

**Anything else**
The maintainer is based in Türkiye. Azure Trusted Signing is not available there for individuals or organisations, which is why we are applying to the SignPath Foundation.

## After approval

1. In SignPath: create the project `windows-debloater`, the signing policy `release-signing` with manual approval, and the artifact configurations `payload` and `installer` from `.signpath/payload.xml` and `.signpath/installer.xml`. Link the GitHub repository as a trusted build system. Create a CI user and copy its API token.
2. In GitHub, under Settings > Secrets and variables > Actions, add the variables `SIGNING=signpath`, `SIGNPATH_ORGANIZATION_ID`, `SIGNPATH_PROJECT_SLUG=windows-debloater` and `SIGNPATH_SIGNING_POLICY_SLUG=release-signing`, and the secret `SIGNPATH_API_TOKEN`.
3. Update the status note at the top of `CODE_SIGNING_POLICY.md`.
4. Tag the next version. Approve the two signing requests in SignPath. Run `scripts\write-update-feed.ps1 -Tag vX.Y.Z` and publish the draft.
