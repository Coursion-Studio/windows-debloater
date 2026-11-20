# Code signing policy

Free code signing provided by [SignPath.io](https://about.signpath.io/), certificate by [SignPath Foundation](https://signpath.org/).

> **Status:** Windows Debloater has applied to the SignPath Foundation open-source programme. Until the application is approved, releases are built the same way described below, but are **not code-signed**, and Windows SmartScreen calls the publisher unknown. This page will say so here when that changes.

## What is signed

Every release on [GitHub Releases](https://github.com/Coursion-Studio/windows-debloater/releases) is built from this repository's source by GitHub Actions ([`.github/workflows/release.yml`](.github/workflows/release.yml)). The signed files are:

| File | What it is |
|---|---|
| `WindowsDebloater.exe` | The program people start. It runs the scripts below. |
| `src/*.ps1`, `src/*.psm1` | The PowerShell scripts that do the work, some of them with administrator rights. They ship as loose files in the zip and inside the installer, so each is signed. |
| `WindowsDebloaterSetup.exe` | The installer, built after the program and scripts it carries were signed. It also serves as the uninstaller. |

Signed files carry the publisher **SignPath Foundation**. Nothing else is signed with this certificate: no third-party binaries, and no files built outside the release workflow.

## How a release is built

1. The maintainer pushes a version tag (`v1.2.3`) for a commit on `main`.
2. GitHub Actions checks out that tag, runs the tests (`test/Run-Tests.ps1`), and builds both programs with the C# compiler that ships with Windows (`scripts/build-exe.ps1`). No binary is checked into the repository and nothing is built on a personal computer.
3. The program and scripts are sent to SignPath as a GitHub Actions artifact. SignPath verifies the artifact came from this repository's workflow run, and a signing request waits for **manual approval** by an approver (below).
4. The installer is built again around the signed files and goes through the same approval.
5. The workflow checks every signature and creates a **draft** release with the zip, the installer, and their SHA-256 files.
6. The maintainer adds `update.json` (see below) and publishes the draft.

### The update signature, which is not code signing

Separately from code signing, installed copies only accept an update whose installer carries a signature made with the project's own update key. Only the public half of that key is in this repository (`src/update-key.xml`). The private half never goes to GitHub or SignPath. It stays on the maintainer's computer, so writing `update.json` is the one release step that runs there (`scripts/write-update-feed.ps1`). That step downloads the installer the workflow built, checks it against the published SHA-256, and signs those exact bytes. It doesn't build or change any file.

## Team roles

Windows Debloater is maintained by [Coursion Studio](https://coursion.studio).

| Role | Who |
|---|---|
| Committers and reviewers | [@kuraydev](https://github.com/kuraydev) (Coursion Studio) |
| Approvers | [@kuraydev](https://github.com/kuraydev) (Coursion Studio) |

- Committers may push to the repository. Changes from anyone else come as pull requests, which a reviewer reads in full before merging.
- Approvers approve each signing request in SignPath, after checking that it comes from a release tag of this repository.
- Everyone in these roles uses multi-factor authentication on GitHub and on SignPath.

## Privacy policy

This program will not transfer any information to other networked systems unless specifically requested by the user or the person installing or operating it, with one exception that can be switched off: when the tool opens, at most once a day, it asks this project's GitHub releases whether there is a newer version. Settings has a switch to turn that check off. [PRIVACY.md](PRIVACY.md) says exactly what that request carries and what the tool stores on the PC.

## Reporting a problem

If a file signed for this project looks wrong, or you think the signing process was misused, open an issue or email [support@coursion.studio](mailto:support@coursion.studio). You can also contact [SignPath Foundation](https://signpath.org/) directly.
