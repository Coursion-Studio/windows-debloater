// WindowsDebloaterSetup.exe: installs, updates and uninstalls Windows Debloater.
//
// Double-clicked, it shows its window, asks and installs. A copy of it stays in the
// program's folder as Uninstall.exe, which is what Settings > Apps starts.
//
// For scripts, and for the tool updating itself:
//
//   WindowsDebloaterSetup.exe /S [/desktop] [/launch]     install or update, showing nothing
//   WindowsDebloaterSetup.exe /update                     update with only the bar, then open the tool
//   Uninstall.exe /uninstall /S [/purge]                  remove; /purge also removes the history
//   /dir=<folder>                                         install somewhere else
//   /lang=<code>                                          the language of the window, such as tr
//
// It ends with 0 when it worked and 1 when it did not; what went wrong is added to
// %TEMP%\WindowsDebloaterSetup.log.
//
// Two more are for building and testing. /sandbox=<folder> keeps an install inside
// that folder and a scratch registry key. /shots=<folder> draws every page of the
// window into PNG files and installs nothing.

using System;
using System.IO;
using System.Runtime.InteropServices;

namespace Debloater.Setup
{
    static class Program
    {
        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        static extern int MessageBoxW(IntPtr owner, string text, string caption, uint type);

        [STAThread]
        static int Main(string[] args)
        {
            bool uninstall = Has(args, "/uninstall");
            bool update = Has(args, "/update");
            bool silent = Has(args, "/S") || Has(args, "/silent");
            try
            {
                string sandbox = ValueOf(args, "/sandbox=");
                string folder = ValueOf(args, "/dir=");
                if (sandbox != null) Installer.UseSandbox(sandbox);
                else if (folder != null) Installer.Dir = Path.GetFullPath(folder);
                else Installer.UseTheInstalledFolder();

                if (silent)
                {
                    Action<double, string> quiet = delegate (double done, string step) { };
                    if (uninstall) Installer.Uninstall(Has(args, "/purge"), quiet);
                    else
                    {
                        Installer.Install(Has(args, "/desktop"), quiet);
                        if (update || Has(args, "/launch")) Installer.Launch();
                    }
                    return 0;
                }

                Texts.Load(ValueOf(args, "/lang="));
                string shots = ValueOf(args, "/shots=");
                if (shots != null)
                {
                    new SetupWindow(false, false).SaveShots(shots);
                    return 0;
                }
                return new SetupWindow(uninstall, update).Run();
            }
            catch (Exception problem)
            {
                Log(problem);
                // The window itself could not be shown, so this is said the plain way.
                if (!silent) MessageBoxW(IntPtr.Zero, problem.Message, Installer.AppName, 0x10);
                return 1;
            }
        }

        static bool Has(string[] args, string name)
        {
            foreach (string arg in args)
                if (string.Equals(arg, name, StringComparison.OrdinalIgnoreCase)) return true;
            return false;
        }

        static string ValueOf(string[] args, string prefix)
        {
            foreach (string arg in args)
                if (arg.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)) return arg.Substring(prefix.Length).Trim('"');
            return null;
        }

        public static void Log(Exception problem)
        {
            try
            {
                string line = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "  " + Installer.Version + "  " + problem + Environment.NewLine;
                File.AppendAllText(Path.Combine(Path.GetTempPath(), "WindowsDebloaterSetup.log"), line);
            }
            catch { }
        }
    }
}
