// WindowsDebloater.exe: the program people start.
//
// The tool itself is the set of PowerShell scripts in the src folder next to this
// program. This program runs src\Debloater.ps1 inside its own process, which is what
// makes it a program and not a script someone has to start: the window belongs to
// WindowsDebloater.exe, so it has the right name and icon in the taskbar and in Task
// Manager, it can be pinned, no console window flashes up, and a problem at start-up
// is shown in a message and not lost.
//
// Whatever is written after the program's name is handed to the script:
//
//   WindowsDebloater.exe -DryRun        goes through every step and changes nothing
//   WindowsDebloater.exe -Demo          a dry run that pretends everything needs doing
//   WindowsDebloater.exe -Lang tr -Theme light
//
// Built by scripts\build-exe.ps1 with the C# compiler that is part of Windows.

using System;
using System.Diagnostics;
using System.IO;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Reflection;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

namespace Debloater.App
{
    static class Program
    {
        const string Name = "Windows Debloater";

        // Set by the first window that is opened the ordinary way. A second start finds
        // it, asks that window to come forward and leaves.
        const string ShowSignal = @"Local\Coursion.WindowsDebloater.Show";

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        static extern int MessageBoxW(IntPtr owner, string text, string caption, uint type);
        [DllImport("user32.dll")]
        static extern bool SetForegroundWindow(IntPtr window);
        [DllImport("user32.dll")]
        static extern bool ShowWindow(IntPtr window, int command);
        [DllImport("user32.dll")]
        static extern bool IsIconic(IntPtr window);
        [DllImport("user32.dll")]
        static extern bool AllowSetForegroundWindow(int processId);

        [STAThread]
        static int Main(string[] args)
        {
            string home = Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location);
            string script = Path.Combine(home, "src", "Debloater.ps1");
            string testFolder = ValueOf(args, "-SelfTest");
            try
            {
                if (!File.Exists(script))
                    throw new FileNotFoundException("The src folder that belongs next to this program is missing. Unpack the whole download, or run the installer again.", script);

                if (args.Length == 0 && !ClaimTheOnlyWindow()) return 0;
                Run(script, args);
                return 0;
            }
            catch (Exception problem)
            {
                Report(Describe(problem), testFolder);
                return 1;
            }
        }

        // True for the first start. A later start wakes the first one and gets false.
        static bool ClaimTheOnlyWindow()
        {
            bool first;
            var signal = new EventWaitHandle(false, EventResetMode.AutoReset, ShowSignal, out first);
            if (!first)
            {
                // Only the program the person just started may bring a window forward,
                // so it passes that right on.
                AllowSetForegroundWindow(-1);
                signal.Set();
                return false;
            }
            var listener = new Thread(delegate ()
            {
                while (true)
                {
                    signal.WaitOne();
                    try
                    {
                        Process self = Process.GetCurrentProcess();
                        self.Refresh();
                        IntPtr window = self.MainWindowHandle;
                        if (window == IntPtr.Zero) continue;
                        if (IsIconic(window)) ShowWindow(window, 9);
                        SetForegroundWindow(window);
                    }
                    catch { }
                }
            });
            listener.IsBackground = true;
            listener.Start();
            return true;
        }

        // Kept out of Main, so that a PC without Windows PowerShell gets a message from
        // Main and not a crash before it starts.
        [MethodImpl(MethodImplOptions.NoInlining)]
        static void Run(string script, string[] args)
        {
            InitialSessionState state = InitialSessionState.CreateDefault();
            // The same as starting powershell.exe with -ExecutionPolicy Bypass: it applies
            // to this process only and changes no setting of the PC.
            state.ExecutionPolicy = Microsoft.PowerShell.ExecutionPolicy.Bypass;
            state.ApartmentState = ApartmentState.STA;
            state.ThreadOptions = PSThreadOptions.UseCurrentThread;

            using (Runspace space = RunspaceFactory.CreateRunspace(state))
            {
                space.Open();
                Runspace.DefaultRunspace = space;
                using (PowerShell shell = PowerShell.Create())
                {
                    shell.Runspace = space;
                    shell.AddCommand(script);
                    // -Name value, or -Name alone for a switch.
                    for (int i = 0; i < args.Length; i++)
                    {
                        if (!args[i].StartsWith("-", StringComparison.Ordinal))
                            throw new ArgumentException("\"" + args[i] + "\" is not something this program understands. Options start with a dash, such as -DryRun.");
                        string name = args[i].TrimStart('-');
                        if (i + 1 < args.Length && !args[i + 1].StartsWith("-", StringComparison.Ordinal))
                            shell.AddParameter(name, args[++i]);
                        else
                            shell.AddParameter(name, true);
                    }
                    shell.Invoke();
                }
            }
        }

        static string ValueOf(string[] args, string name)
        {
            for (int i = 0; i + 1 < args.Length; i++)
                if (string.Equals(args[i], name, StringComparison.OrdinalIgnoreCase)) return args[i + 1];
            return null;
        }

        static string Describe(Exception problem)
        {
            var text = new StringBuilder();
            var fromScript = problem as RuntimeException;
            text.Append(problem.Message);
            if (fromScript != null && fromScript.ErrorRecord != null && fromScript.ErrorRecord.InvocationInfo != null)
            {
                string where = fromScript.ErrorRecord.InvocationInfo.PositionMessage;
                if (!string.IsNullOrEmpty(where)) text.Append("\r\n\r\n").Append(where);
            }
            return text.ToString();
        }

        // A test has nobody to press OK, so there the message goes into a file.
        static void Report(string message, string testFolder)
        {
            if (testFolder != null)
            {
                try
                {
                    Directory.CreateDirectory(testFolder);
                    File.WriteAllText(Path.Combine(testFolder, "exe-error.txt"), message);
                }
                catch { }
                return;
            }
            MessageBoxW(IntPtr.Zero, Name + " ran into a problem and has to close.\r\n\r\n" + message, Name, 0x10);
        }
    }
}
