// Movement that has to be worked out on every frame, which is too often for PowerShell:
// mouse-wheel scrolling that glides, and numbers that count up. Everything else that
// moves is plain WPF animation, started from Debloater.UI.ps1 or described in
// MainWindow.xaml.
//
// Kept to C# 5 so the compiler built into Windows PowerShell can build it.

using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;

namespace Debloater.Ui
{
    // Makes the mouse wheel glide to where it is going instead of jumping there.
    public static class Glide
    {
        public static bool Enabled = true;

        class State
        {
            public ScrollViewer Viewer;
            public double Target;
            public double Expected = double.NaN;
            public bool Running;
            public TimeSpan Last;

            public void OnFrame(object sender, EventArgs e)
            {
                RenderingEventArgs args = e as RenderingEventArgs;
                TimeSpan now = args != null ? args.RenderingTime : TimeSpan.Zero;
                double seconds = Last == TimeSpan.Zero ? 1.0 / 60 : (now - Last).TotalSeconds;
                // The event can be raised more than once for the same frame.
                if (seconds <= 0) return;
                if (seconds > 0.1) seconds = 0.1;
                Last = now;

                double current = Viewer.VerticalOffset;
                // Something else moved the list: the scrollbar was dragged, or a new page
                // went back to the top. Let it be.
                if (!double.IsNaN(Expected) && Math.Abs(current - Expected) > 3) { Stop(); return; }
                if (Target > Viewer.ScrollableHeight) Target = Viewer.ScrollableHeight;
                double left = Target - current;
                if (Math.Abs(left) < 0.6) { Viewer.ScrollToVerticalOffset(Target); Stop(); return; }
                double next = current + left * (1 - Math.Exp(-seconds * 15));
                Expected = next;
                Viewer.ScrollToVerticalOffset(next);
            }

            public void Stop()
            {
                Running = false;
                Expected = double.NaN;
                CompositionTarget.Rendering -= OnFrame;
            }
        }

        public static void Attach(ScrollViewer viewer)
        {
            if (viewer == null) return;
            State state = new State();
            state.Viewer = viewer;
            viewer.PreviewMouseWheel += delegate(object sender, MouseWheelEventArgs e)
            {
                if (!Enabled || e.Handled || viewer.ScrollableHeight <= 0) return;
                if (!state.Running) state.Target = viewer.VerticalOffset;
                state.Target = Math.Max(0, Math.Min(viewer.ScrollableHeight, state.Target - e.Delta * 0.9));
                e.Handled = true;
                if (!state.Running)
                {
                    state.Running = true;
                    state.Last = TimeSpan.Zero;
                    state.Expected = double.NaN;
                    CompositionTarget.Rendering += state.OnFrame;
                }
            };
        }
    }

    // Counts a number up (or down) in a text block, fast at first and settling at the end.
    public static class Counter
    {
        public static void Run(TextBlock block, int from, int to, double milliseconds, double delay)
        {
            if (block == null) return;
            if (milliseconds <= 0 || from == to) { block.Text = to.ToString(); return; }
            block.Text = from.ToString();
            DateTime start = DateTime.UtcNow.AddMilliseconds(delay);
            EventHandler onFrame = null;
            onFrame = delegate(object sender, EventArgs e)
            {
                double part = (DateTime.UtcNow - start).TotalMilliseconds / milliseconds;
                if (part < 0) return;
                if (part >= 1 || !block.IsVisible)
                {
                    block.Text = to.ToString();
                    CompositionTarget.Rendering -= onFrame;
                    return;
                }
                double eased = 1 - Math.Pow(1 - part, 3);
                block.Text = ((int)Math.Round(from + (to - from) * eased)).ToString();
            };
            CompositionTarget.Rendering += onFrame;
        }
    }
}
