// View models for the window. They only hold what the screen shows; all logic stays in
// PowerShell. Kept to C# 5 so the compiler built into Windows PowerShell can build it.

using System;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.InteropServices;

namespace Debloater.Ui
{
    public class Observable : INotifyPropertyChanged
    {
        public event PropertyChangedEventHandler PropertyChanged;

        protected void Raise(string name)
        {
            PropertyChangedEventHandler handler = PropertyChanged;
            if (handler != null) handler(this, new PropertyChangedEventArgs(name));
        }
    }

    // What an icon needs: a picture, and a glyph that stands in when there is none.
    public class IconVm : Observable
    {
        public string Glyph { get; set; }
        // Typed as object so this file does not need to reference the WPF assemblies.
        public object Icon { get; set; }
        public bool HasIcon { get { return Icon != null; } }
    }

    // One thing the tool can change: an app to remove or a setting to switch off.
    public class ItemVm : Observable
    {
        // Raised when a person ticks or unticks any item.
        public static event EventHandler AnySelectionChanged;

        public string Id { get; set; }
        public string Title { get; set; }
        public string Description { get; set; }
        public string Details { get; set; }
        public string StateText { get; set; }
        public bool NeedsAdmin { get; set; }
        public bool Recommended { get; set; }
        public string AdminText { get; set; }
        public string RecommendedText { get; set; }
        public string DetailsLabel { get; set; }

        public bool HasDescription { get { return !string.IsNullOrEmpty(Description); } }

        bool selected;
        public bool IsSelected
        {
            get { return selected; }
            set
            {
                if (selected == value) return;
                selected = value;
                Raise("IsSelected");
                EventHandler handler = AnySelectionChanged;
                if (handler != null) handler(this, EventArgs.Empty);
            }
        }

        // Changes the tick from code without announcing it, for bulk updates.
        public void SetSelectedQuietly(bool value)
        {
            if (selected == value) return;
            selected = value;
            Raise("IsSelected");
        }

        bool expanded;
        public bool IsExpanded
        {
            get { return expanded; }
            set { if (expanded == value) return; expanded = value; Raise("IsExpanded"); }
        }
    }

    public class GroupVm
    {
        public GroupVm() { Items = new ObservableCollection<ItemVm>(); }
        public string Title { get; set; }
        public string CountText { get; set; }
        public ObservableCollection<ItemVm> Items { get; private set; }
    }

    // A page's icon and name, for the top bar buttons and the heading of the page.
    public class NavVm : IconVm
    {
        public string Id { get; set; }

        string title;
        public string Title { get { return title; } set { title = value; Raise("Title"); } }
    }

    // One area's row on the overview.
    public class AreaVm : IconVm
    {
        public AreaVm() { Chip = ""; ChipKind = ""; }
        public string Id { get; set; }
        public string Title { get; set; }
        public string Summary { get; set; }
        // The small box at the end of the row, such as "23 / 43". Empty hides it.
        public string Chip { get; set; }
        // "" for a plain count, "quiet" when nothing is ticked, "done" for something achieved.
        public string ChipKind { get; set; }
    }

    // One area's card on the debloating screen. It comes forward while that area is
    // being worked on and gets a tick when it is finished.
    public class LaneVm : IconVm
    {
        public string Id { get; set; }
        public string Title { get; set; }
        public string TotalText { get; set; }
        public int Total { get; set; }
        public int Count { get; set; }

        string countText = "0";
        public string CountText { get { return countText; } set { countText = value; Raise("CountText"); } }

        double progress;
        public double Progress { get { return progress; } set { progress = value; Raise("Progress"); } }

        string status = "";
        public string Status { get { return status; } set { status = value ?? ""; Raise("Status"); } }

        bool active;
        public bool IsActive { get { return active; } set { if (active == value) return; active = value; Raise("IsActive"); } }

        bool done;
        public bool IsDone { get { return done; } set { if (done == value) return; done = value; Raise("IsDone"); } }

        // Set when the area finished but something in it failed or was skipped.
        bool problem;
        public bool HasProblem { get { return problem; } set { if (problem == value) return; problem = value; Raise("HasProblem"); } }
    }

    // One line of the "just done" list under the lanes: the newest is bright, older
    // ones fade as more arrive.
    public class FeedVm : Observable
    {
        public string Title { get; set; }
        public string Area { get; set; }
        // "ok", "failed" or "skipped"
        public string Kind { get; set; }

        double strength = 1;
        public double Strength { get { return strength; } set { strength = value; Raise("Strength"); } }
    }

    // One line of the confirmation sheet, with the icon of the area it is about.
    public class SummaryVm : IconVm
    {
        public string Text { get; set; }
        public string Note { get; set; }
    }

    public class NoteVm
    {
        public string Text { get; set; }
        public string Glyph { get; set; }
        // "info", "warning" or "success"
        public string Kind { get; set; }
    }

    // One line on the progress and result screens.
    public class StepVm : Observable
    {
        public string Id { get; set; }
        public string Title { get; set; }

        string message = "";
        public string Message { get { return message; } set { message = value ?? ""; Raise("Message"); } }

        // "pending", "running", "ok", "failed" or "skipped"
        string status = "pending";
        public string Status { get { return status; } set { status = value; Raise("Status"); } }

        string statusText = "";
        public string StatusText { get { return statusText; } set { statusText = value; Raise("StatusText"); } }
    }

    public class StatVm
    {
        public string Value { get; set; }
        public string Label { get; set; }
        // "ok", "failed" or "skipped"
        public string Kind { get; set; }
    }

    public class AppLinkVm
    {
        public string Name { get; set; }
        public string Family { get; set; }
        public string Tip { get; set; }
    }

    public class RunVm
    {
        public RunVm() { Apps = new ObservableCollection<AppLinkVm>(); }
        public string Dir { get; set; }
        public string Title { get; set; }
        public string Subtitle { get; set; }
        public bool HasSubtitle { get { return !string.IsNullOrEmpty(Subtitle); } }
        public bool CanUndo { get; set; }
        public string UndoText { get; set; }
        public string OpenText { get; set; }
        public string AppsLabel { get; set; }
        public bool HasApps { get { return Apps.Count > 0; } }
        public ObservableCollection<AppLinkVm> Apps { get; private set; }
    }

    // One option in a pick-one list on the Settings page.
    public class ChoiceVm : Observable
    {
        public string Id { get; set; }
        public string Title { get; set; }

        bool chosen;
        public bool IsChosen { get { return chosen; } set { if (chosen == value) return; chosen = value; Raise("IsChosen"); } }
    }

    // One selection in the list on the overview: its name, how many changes it would
    // tick on this PC, and whether it is the one in use. One that somebody saved can be
    // renamed, written to a file or deleted, so it carries a button for that.
    public class PickVm
    {
        public string Id { get; set; }
        public string Title { get; set; }
        public string Count { get; set; }
        public bool IsChosen { get; set; }
        public bool CanEdit { get; set; }
        public string EditTip { get; set; }
    }

    public static class Win32
    {
        [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
        static extern int SetCurrentProcessExplicitAppUserModelID(string appId);

        // Gives the window its own taskbar button and icon instead of PowerShell's.
        public static void SetAppId(string appId)
        {
            try { SetCurrentProcessExplicitAppUserModelID(appId); } catch { }
        }

        [DllImport("dwmapi.dll")]
        static extern int DwmSetWindowAttribute(IntPtr window, int attribute, ref int value, int size);

        // Asks Windows 11 for rounded corners and for a frame that matches a dark or a
        // light window. Older versions of Windows do not know these and ignore them.
        public static void SetWindowLook(IntPtr window, bool dark)
        {
            try
            {
                int round = 2;
                DwmSetWindowAttribute(window, 33, ref round, 4);
                int mode = dark ? 1 : 0;
                DwmSetWindowAttribute(window, 20, ref mode, 4);
            }
            catch { }
        }
    }
}
