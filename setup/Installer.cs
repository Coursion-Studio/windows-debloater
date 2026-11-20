// What the installer does to the PC: put the program in place, take it away again.
//
// It installs for the person who runs it. No administrator rights are asked for, and
// nothing outside their own profile is touched:
//
//   %LocalAppData%\Programs\WindowsDebloater     the program and its scripts
//   Start menu                                   one shortcut
//   Settings > Apps > Installed apps             one entry, kept in their own registry hive
//
// Uninstalling removes exactly the files that were installed, by name, from a list
// written at install time. It never deletes a folder with whatever happens to be in it.

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Text;
using System.Threading;
using Microsoft.Win32;

namespace Debloater.Setup
{
    // Something the person can do something about. The message is the key of a text
    // in the language files, such as "setup.problem.open".
    class SetupProblem : Exception
    {
        public SetupProblem(string key) : base(key) { }
    }

    static class Installer
    {
        public const string AppName = "Windows Debloater";
        public const string ExeName = "WindowsDebloater.exe";
        public const string UninstallerName = "Uninstall.exe";
        // The same id the window gives itself in src\Debloater.UI.ps1.
        public const string AppId = "Coursion.WindowsDebloater";
        const string ProcessName = "WindowsDebloater";
        const string ListName = "installed.txt";
        const string Site = "https://github.com/Coursion-Studio/windows-debloater";

        static readonly string Local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);

        public static string Dir = Path.Combine(Local, "Programs", "WindowsDebloater");
        public static string MenuDir = Environment.GetFolderPath(Environment.SpecialFolder.Programs);
        public static string DesktopDir = Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
        // Where the tool keeps its history and preferences. See Get-DebloaterDataRoot.
        public static string DataDir = Path.Combine(Local, "WindowsDebloater");
        public static string UninstallKey = @"Software\Microsoft\Windows\CurrentVersion\Uninstall\CoursionStudio.WindowsDebloater";

        public static string ExePath { get { return Path.Combine(Dir, ExeName); } }
        static string UninstallerPath { get { return Path.Combine(Dir, UninstallerName); } }
        static string ListPath { get { return Path.Combine(Dir, ListName); } }
        public static string MenuShortcut { get { return Path.Combine(MenuDir, AppName + ".lnk"); } }
        public static string DesktopShortcut { get { return Path.Combine(DesktopDir, AppName + ".lnk"); } }
        static string Self { get { return Assembly.GetExecutingAssembly().Location; } }

        // For the tests: everything goes into one folder and a scratch registry key, so
        // an install can be tried from start to finish without the PC noticing.
        public static void UseSandbox(string folder)
        {
            folder = Path.GetFullPath(folder);
            Dir = Path.Combine(folder, "program files");
            MenuDir = Path.Combine(folder, "start menu");
            DesktopDir = Path.Combine(folder, "desktop");
            DataDir = Path.Combine(folder, "data");
            UninstallKey = @"Software\DebloaterSelfTest\Uninstall";
            // Opening the tool "when done" must not put a window on the screen during a
            // test, so there it does its off-screen walk in demo mode and leaves a report.
            LaunchArguments = "-Demo -Lang en -SelfTest \"" + Path.Combine(folder, "launched") + "\"";
        }

        static string LaunchArguments = "";

        public static string Version
        {
            get
            {
                var stamp = Assembly.GetExecutingAssembly().GetCustomAttribute<AssemblyInformationalVersionAttribute>();
                return stamp == null ? "0.0.0" : stamp.InformationalVersion;
            }
        }

        public static bool IsInstalled { get { return File.Exists(ExePath); } }

        // Whether the desktop has a shortcut to this copy of the program.
        public static bool HasDesktopShortcut
        {
            get
            {
                string target, id;
                Shortcut.Read(DesktopShortcut, out target, out id);
                return target != null && SamePath(target, ExePath);
            }
        }

        public static string InstalledVersion
        {
            get
            {
                using (RegistryKey key = Registry.CurrentUser.OpenSubKey(UninstallKey))
                    return key == null ? null : key.GetValue("DisplayVersion") as string;
            }
        }

        // An update or an uninstall works on the copy that is there, wherever it was
        // put: the folder this program is in when it is that copy's uninstaller, or
        // else the folder Windows has on record.
        public static void UseTheInstalledFolder()
        {
            string own = Path.GetDirectoryName(Self);
            if (File.Exists(Path.Combine(own, ExeName)) && File.Exists(Path.Combine(own, ListName))) { Dir = own; return; }
            using (RegistryKey key = Registry.CurrentUser.OpenSubKey(UninstallKey))
            {
                string recorded = key == null ? null : key.GetValue("InstallLocation") as string;
                if (!string.IsNullOrEmpty(recorded) && File.Exists(Path.Combine(recorded, ExeName))) Dir = recorded;
            }
        }

        // ------------------------------------------------------------ install and update

        public static void Install(bool desktopShortcut, Action<double, string> progress)
        {
            progress(0.05, "close");
            CloseTheProgram();

            progress(0.2, "copy");
            Directory.CreateDirectory(Dir);
            // An update first takes away what the older version put there, so a file
            // the new version no longer has does not linger.
            RemoveListedFiles();
            List<string> written = Unpack();
            if (!SamePath(Self, UninstallerPath)) WriteWithRetry(UninstallerPath, File.ReadAllBytes(Self));
            written.Add(UninstallerName);
            File.WriteAllLines(ListPath, written.ToArray(), new UTF8Encoding(false));

            progress(0.7, "shortcut");
            string says = "Remove preinstalled apps, ads and suggestions from Windows 11";
            Shortcut.Create(MenuShortcut, ExePath, Dir, says, AppId);
            if (desktopShortcut) Shortcut.Create(DesktopShortcut, ExePath, Dir, says, AppId);

            progress(0.85, "register");
            Register();
            progress(1, "done");
        }

        public static void Launch()
        {
            Process.Start(new ProcessStartInfo(ExePath, LaunchArguments) { UseShellExecute = true, WorkingDirectory = Dir });
        }

        // ------------------------------------------------------------ uninstall

        public static void Uninstall(bool removeHistory, Action<double, string> progress)
        {
            progress(0.1, "close");
            CloseTheProgram();

            progress(0.3, "shortcut");
            TryDelete(MenuShortcut);
            // A desktop shortcut goes only if it is ours: one of that name pointing
            // somewhere else belongs to the person.
            string target, id;
            Shortcut.Read(DesktopShortcut, out target, out id);
            if (target != null && SamePath(target, ExePath)) TryDelete(DesktopShortcut);
            Registry.CurrentUser.DeleteSubKeyTree(UninstallKey, false);

            progress(0.6, "files");
            RemoveListedFiles();
            if (removeHistory) RemoveHistory();

            // This program may be the Uninstall.exe in that folder, and a running
            // program cannot delete itself. A hidden command waits for it to end,
            // deletes that one file, then removes the folder if nothing else is in it.
            if (SamePath(Path.GetDirectoryName(Self), Dir))
            {
                string command = "/c ping 127.0.0.1 -n 3 >nul & del /f /q \"" + Self + "\" & rmdir \"" + Dir + "\"";
                Process.Start(new ProcessStartInfo("cmd.exe", command)
                {
                    CreateNoWindow = true, UseShellExecute = false, WindowStyle = ProcessWindowStyle.Hidden,
                    WorkingDirectory = Environment.SystemDirectory
                });
            }
            else
            {
                TryDelete(UninstallerPath);
                RemoveIfEmpty(Dir);
            }
            progress(1, "done");
        }

        // ------------------------------------------------------------ files

        // Writes the packed files into the folder and returns their names.
        static List<string> Unpack()
        {
            var written = new List<string>();
            string root = Path.GetFullPath(Dir).TrimEnd('\\') + "\\";
            using (Stream packed = Assembly.GetExecutingAssembly().GetManifestResourceStream("payload.zip"))
            {
                if (packed == null) throw new InvalidOperationException("This installer was built without its files.");
                using (var zip = new ZipArchive(packed, ZipArchiveMode.Read))
                {
                    foreach (ZipArchiveEntry entry in zip.Entries)
                    {
                        string name = entry.FullName.Replace('/', '\\');
                        if (name.EndsWith("\\", StringComparison.Ordinal)) continue;
                        string target = Path.GetFullPath(Path.Combine(root, name));
                        if (!target.StartsWith(root, StringComparison.OrdinalIgnoreCase))
                            throw new InvalidOperationException("The installer holds a file that does not belong in its folder: " + name);
                        Directory.CreateDirectory(Path.GetDirectoryName(target));
                        using (var data = new MemoryStream())
                        {
                            using (Stream source = entry.Open()) source.CopyTo(data);
                            WriteWithRetry(target, data.ToArray());
                        }
                        written.Add(name);
                    }
                }
            }
            return written;
        }

        // A text that travels inside the installer, such as LICENSE.md. Null when it is not there.
        public static string ReadPacked(string name)
        {
            try
            {
                using (Stream packed = Assembly.GetExecutingAssembly().GetManifestResourceStream("payload.zip"))
                using (var zip = new ZipArchive(packed, ZipArchiveMode.Read))
                {
                    foreach (ZipArchiveEntry entry in zip.Entries)
                    {
                        if (!string.Equals(entry.FullName.Replace('/', '\\'), name, StringComparison.OrdinalIgnoreCase)) continue;
                        using (var reader = new StreamReader(entry.Open(), Encoding.UTF8)) return reader.ReadToEnd();
                    }
                }
            }
            catch { }
            return null;
        }

        // Deletes the files a previous install listed, then the folders they leave
        // empty. A file that was added by someone else stays, and so does its folder.
        static void RemoveListedFiles()
        {
            if (!File.Exists(ListPath)) return;
            string root = Path.GetFullPath(Dir).TrimEnd('\\') + "\\";
            var folders = new List<string>();
            foreach (string line in File.ReadAllLines(ListPath))
            {
                string name = line.Trim();
                if (name.Length == 0) continue;
                string target = Path.GetFullPath(Path.Combine(root, name));
                if (!target.StartsWith(root, StringComparison.OrdinalIgnoreCase)) continue;
                // The uninstaller may be this very program. It is dealt with at the end.
                if (SamePath(target, UninstallerPath)) continue;
                TryDelete(target);
                string folder = Path.GetDirectoryName(target);
                while (folder.Length > root.Length && !folders.Contains(folder))
                {
                    folders.Add(folder);
                    folder = Path.GetDirectoryName(folder);
                }
            }
            TryDelete(ListPath);
            // Longest path first, so a folder is looked at after the folders inside it.
            folders.Sort(delegate (string a, string b) { return b.Length.CompareTo(a.Length); });
            foreach (string folder in folders) RemoveIfEmpty(folder);
        }

        // History and preferences: the run logs with the recorded old values, and the
        // settings file. Removing them means earlier runs can no longer be put back.
        static void RemoveHistory()
        {
            try
            {
                string runs = Path.Combine(DataDir, "runs");
                if (Directory.Exists(runs)) Directory.Delete(runs, true);
                string updates = Path.Combine(DataDir, "updates");
                if (Directory.Exists(updates)) Directory.Delete(updates, true);
                TryDelete(Path.Combine(DataDir, "settings.json"));
                RemoveIfEmpty(DataDir);
            }
            catch { }
        }

        static void WriteWithRetry(string path, byte[] data)
        {
            for (int attempt = 0; ; attempt++)
            {
                try { File.WriteAllBytes(path, data); return; }
                catch (IOException) { if (attempt >= 15) throw; }
                catch (UnauthorizedAccessException) { if (attempt >= 15) throw; }
                Thread.Sleep(200);
            }
        }

        static void TryDelete(string path)
        {
            try { if (File.Exists(path)) File.Delete(path); } catch { }
        }

        static void RemoveIfEmpty(string folder)
        {
            try
            {
                if (Directory.Exists(folder) && Directory.GetFileSystemEntries(folder).Length == 0) Directory.Delete(folder, false);
            }
            catch { }
        }

        static bool SamePath(string a, string b)
        {
            try { return string.Equals(Path.GetFullPath(a).TrimEnd('\\'), Path.GetFullPath(b).TrimEnd('\\'), StringComparison.OrdinalIgnoreCase); }
            catch { return false; }
        }

        // ------------------------------------------------------------ the running program

        // Asks an open Windows Debloater from this folder to close, the way its own
        // close button does. It is never ended by force: it may be in the middle of
        // changing settings.
        static void CloseTheProgram()
        {
            foreach (Process running in Process.GetProcessesByName(ProcessName))
            {
                try
                {
                    string path = null;
                    try { path = running.MainModule.FileName; } catch { }
                    if (path == null || !SamePath(path, ExePath)) continue;
                    try { running.CloseMainWindow(); } catch { }
                    if (!running.WaitForExit(8000)) throw new SetupProblem("setup.problem.open");
                }
                finally { running.Dispose(); }
            }
        }

        // ------------------------------------------------------------ Windows' list of installed apps

        static void Register()
        {
            long bytes = 0;
            foreach (string file in Directory.GetFiles(Dir, "*", SearchOption.AllDirectories)) bytes += new FileInfo(file).Length;
            using (RegistryKey key = Registry.CurrentUser.CreateSubKey(UninstallKey))
            {
                key.SetValue("DisplayName", AppName);
                key.SetValue("DisplayVersion", Version);
                key.SetValue("Publisher", "Coursion Studio");
                key.SetValue("DisplayIcon", ExePath + ",0");
                key.SetValue("InstallLocation", Dir);
                key.SetValue("InstallDate", DateTime.Now.ToString("yyyyMMdd"));
                key.SetValue("UninstallString", "\"" + UninstallerPath + "\" /uninstall");
                key.SetValue("QuietUninstallString", "\"" + UninstallerPath + "\" /uninstall /S");
                key.SetValue("URLInfoAbout", Site);
                key.SetValue("HelpLink", Site + "/issues");
                key.SetValue("NoModify", 1, RegistryValueKind.DWord);
                key.SetValue("NoRepair", 1, RegistryValueKind.DWord);
                key.SetValue("EstimatedSize", (int)(bytes / 1024), RegistryValueKind.DWord);
            }
        }
    }
}
