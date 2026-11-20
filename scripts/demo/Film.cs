// The film at the top of the README: Windows 11 as it comes, the tool at work, and
// what is left afterwards. scripts\build-demo.ps1 films the real window in demo mode
// and hands the frames to this file, which draws a made-up desktop around them and
// writes docs\demo.gif. Nothing is recorded from the real screen.
//
// The desktop is a sketch, not a copy of Windows: plain tiles with names on them. What
// it shows as gone afterwards is what the recommended selection really removes or
// switches off.
//
// Kept to C# 5 so the compiler built into Windows PowerShell can build it. The GIF
// encoder at the end is the one from WinZones.

using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace Debloater.Demo
{
    // The frames filmed from the real window: raw pixels one after another in a file,
    // and the moment each one was taken.
    public sealed class Footage : IDisposable
    {
        readonly FileStream file;
        readonly int width, height;
        readonly double[] times;
        readonly byte[] buffer;
        int loaded = -1;
        BitmapSource frame;

        public Footage(string path, int width, int height, double[] times)
        {
            file = new FileStream(path, FileMode.Open, FileAccess.Read);
            this.width = width;
            this.height = height;
            this.times = times;
            buffer = new byte[width * height * 4];
        }

        // The frame that was on screen at this moment.
        public BitmapSource At(double seconds)
        {
            int index = Array.BinarySearch(times, seconds);
            if (index < 0) index = ~index - 1;
            if (index < 0) index = 0;
            if (index >= times.Length) index = times.Length - 1;
            if (index != loaded)
            {
                file.Seek((long)index * buffer.Length, SeekOrigin.Begin);
                int read = 0;
                while (read < buffer.Length)
                {
                    int count = file.Read(buffer, read, buffer.Length - read);
                    if (count <= 0) break;
                    read += count;
                }
                frame = BitmapSource.Create(width, height, 96, 96, PixelFormats.Pbgra32, null, buffer, width * 4);
                frame.Freeze();
                loaded = index;
            }
            return frame;
        }

        public void Dispose() { file.Dispose(); }
    }

    public sealed class Film
    {
        public const int W = 1280, H = 720, Bar = 44, Fps = 20;

        // The film in seconds: the desktop as it comes until Opens, then the window.
        // The run itself is played faster than it was filmed.
        const double Opens = 3.7, RunSpeed = 2.0, WipeAfter = 0.95, WipeTakes = 1.7, Hold = 3.0;

        readonly Footage shots;
        readonly int fw, fh;
        readonly double ox, oy;
        // Moments in the footage: the pointer arrives on a button, and presses it.
        readonly double hover1, click1, hover2, click2, runEnd, hover3, click3, end;
        readonly Point debloat, confirm, done;
        readonly int[] pixels = new int[W * H];

        // What the window itself listed before it started, shown again at the end.
        public string[] Summary = new string[0];
        public string Total = "";

        static readonly Typeface Regular = Face(FontWeights.Normal);
        static readonly Typeface Semibold = Face(FontWeights.SemiBold);
        static readonly Typeface Bold = Face(FontWeights.Bold);
        static readonly Dictionary<string, SolidColorBrush> brushes = new Dictionary<string, SolidColorBrush>();

        const string Coral = "#FF7A59", Ink = "#0B0A0C", Green = "#2ECC71";
        // Written as numbers so this file stays plain ASCII.
        static readonly string Degree = ((char)0xB0).ToString();
        static readonly string Chevrons = (char)0x2039 + " " + (char)0x203A;

        // marks: hover1, click1, hover2, click2, runEnd, hover3, click3, end (seconds of footage).
        // points: the middle of Debloat, Debloat now and Done, in footage pixels (x, y each).
        public Film(Footage shots, int footageWidth, int footageHeight, double[] marks, double[] points)
        {
            this.shots = shots;
            fw = footageWidth;
            fh = footageHeight;
            ox = Math.Floor((W - fw) / 2.0);
            oy = 58;
            hover1 = marks[0]; click1 = marks[1]; hover2 = marks[2]; click2 = marks[3];
            runEnd = marks[4]; hover3 = marks[5]; click3 = marks[6]; end = marks[7];
            debloat = new Point(ox + points[0], oy + points[1]);
            confirm = new Point(ox + points[2], oy + points[3]);
            done = new Point(ox + points[4], oy + points[5]);
        }

        // ------------------------------------------------------------ Time

        static double P(double t, double from, double to) { return Math.Max(0, Math.Min(1, (t - from) / (to - from))); }
        static double EaseOut(double x) { return 1 - Math.Pow(1 - x, 3); }
        static double EaseInOut(double x) { return x < 0.5 ? 4 * x * x * x : 1 - Math.Pow(-2 * x + 2, 3) / 2; }
        static double EaseBack(double x) { const double c = 1.9; return 1 + (c + 1) * Math.Pow(x - 1, 3) + c * Math.Pow(x - 1, 2); }
        static Point Mix(Point a, Point b, double x) { return new Point(a.X + (b.X - a.X) * x, a.Y + (b.Y - a.Y) * x); }

        // When a moment of the footage is on screen in the film, and the other way round.
        double FilmOf(double footage)
        {
            double start = Opens + 0.2;
            if (footage <= click2) return start + footage;
            if (footage <= runEnd) return start + click2 + (footage - click2) / RunSpeed;
            return start + click2 + (runEnd - click2) / RunSpeed + (footage - runEnd);
        }

        double FootageOf(double film)
        {
            double u = film - (Opens + 0.2);
            if (u <= 0) return 0;
            if (u <= click2) return u;
            double run = (runEnd - click2) / RunSpeed;
            if (u <= click2 + run) return click2 + (u - click2) * RunSpeed;
            return Math.Min(end, runEnd + (u - click2 - run));
        }

        double Closes { get { return FilmOf(end); } }
        double WipeStarts { get { return Closes + WipeAfter; } }
        public double Duration { get { return WipeStarts + WipeTakes + Hold; } }
        public int FrameCount { get { return (int)Math.Round(Duration * Fps); } }

        // ------------------------------------------------------------ Output

        // One frame of the film as pixels.
        public int[] Render(double t)
        {
            DrawingVisual visual = new DrawingVisual();
            using (DrawingContext dc = visual.RenderOpen()) Paint(dc, t);
            RenderTargetBitmap bitmap = new RenderTargetBitmap(W, H, 96, 96, PixelFormats.Pbgra32);
            bitmap.Render(visual);
            bitmap.CopyPixels(pixels, W * 4, 0);
            return pixels;
        }

        public void SaveStill(double t, string path)
        {
            Render(t);
            BitmapSource image = BitmapSource.Create(W, H, 96, 96, PixelFormats.Pbgra32, null, pixels, W * 4);
            PngBitmapEncoder encoder = new PngBitmapEncoder();
            encoder.Frames.Add(BitmapFrame.Create(image));
            using (FileStream stream = File.Create(path)) encoder.Save(stream);
        }

        // Two passes: first the colours the film uses, then the frames.
        public void Save(string path)
        {
            int frames = FrameCount;
            Histogram seen = new Histogram();
            for (int i = 0; i < frames; i += 5) seen.Add(Render(i / (double)Fps), 2);
            Palette palette = Palette.Choose(seen, 255);
            using (Gif gif = new Gif(path, W, H, palette))
            {
                for (int i = 0; i < frames; i++) gif.AddFrame(Render(i / (double)Fps), 100 / Fps);
            }
        }

        // ------------------------------------------------------------ The film

        void Paint(DrawingContext dc, double t)
        {
            double closes = Closes;
            double arrive = EaseOut(P(t, Opens, Opens + 0.5));
            double leave = EaseInOut(P(t, closes, closes + 0.45));
            double window = arrive * (1 - leave);
            // Start, the widgets and the toast step aside while the window is up.
            double flyouts = t < closes ? 1 - P(t, Opens - 0.05, Opens + 0.3) : P(t, closes + 0.15, closes + 0.6);
            double wipe = EaseInOut(P(t, WipeStarts, WipeStarts + WipeTakes));

            if (wipe <= 0)
            {
                Desktop(dc, false, flyouts);
            }
            else if (wipe >= 1)
            {
                Desktop(dc, true, 1);
            }
            else
            {
                // The line travels from left to right. Behind it is the PC afterwards.
                double x = Math.Round(-30 + (W + 60) * wipe);
                Desktop(dc, true, 1);
                dc.PushClip(new RectangleGeometry(new Rect(Math.Max(0, x), 0, W, H)));
                Desktop(dc, false, 1);
                dc.Pop();
                WipeLine(dc, x);
            }

            if (t < Opens) Tags(dc, t);
            if (wipe > 0) Receipt(dc, t);

            if (window > 0.002)
            {
                dc.DrawRectangle(B("#000000", 0.5 * window), null, new Rect(0, 0, W, H - Bar));
                double drop = Math.Round((1 - arrive) * 34 + leave * 34);
                Rect frame = new Rect(ox, oy + drop, fw, fh);
                dc.PushOpacity(window);
                for (int i = 8; i >= 1; i--)
                {
                    Rect shade = new Rect(frame.X - i * 2.5, frame.Y - i * 2.5 + 12, frame.Width + i * 5, frame.Height + i * 5);
                    dc.DrawRoundedRectangle(B("#000000", 0.045), null, shade, 12 + i * 2.5, 12 + i * 2.5);
                }
                dc.PushClip(new RectangleGeometry(frame, 11, 11));
                dc.DrawImage(shots.At(FootageOf(t)), frame);
                dc.Pop();
                dc.DrawRoundedRectangle(null, new Pen(B("#FFFFFF", 0.16), 1), new Rect(frame.X + 0.5, frame.Y + 0.5, frame.Width - 1, frame.Height - 1), 11, 11);
                dc.Pop();
                Pointer(dc, t, drop);
            }

            if (t < Opens) Caption(dc, 1, "Windows 11 as it comes: preinstalled apps, suggestions, a news feed", Math.Min(P(t, 0.15, 0.45), 1 - P(t, Opens - 0.3, Opens)));
            else if (t < closes + 0.3) Caption(dc, 2, "One button. Read the summary, confirm, and watch it work", Math.Min(P(t, Opens + 0.3, Opens + 0.6), 1 - P(t, closes, closes + 0.3)));
            else Caption(dc, 3, "Afterwards: the same PC, without the clutter", P(t, closes + 0.45, closes + 0.75));
        }

        // Where the news feed was, once the line has passed: what was done, in the
        // words the window used when it asked.
        void Receipt(DrawingContext dc, double t)
        {
            if (Summary.Length == 0) return;
            double from = WipeStarts + WipeTakes * 0.5;
            double shown = EaseOut(P(t, from, from + 0.4));
            if (shown <= 0) return;
            double height = 62 + Summary.Length * 30 + 44;
            Rect box = new Rect(BX, Math.Round(SY + (SH - height) / 2 + (1 - shown) * 10), BW, height);
            dc.PushOpacity(shown);
            dc.DrawRoundedRectangle(B("#101014", 0.92), new Pen(B("#FFFFFF", 0.16), 1), box, 12, 12);
            Text(dc, "WHAT CHANGED", 10.5, Bold, B(Coral), box.X + 20, box.Y + 18, 200, false);
            for (int i = 0; i < Summary.Length; i++)
            {
                double row = EaseOut(P(t, from + 0.25 + i * 0.13, from + 0.55 + i * 0.13));
                if (row <= 0) continue;
                double y = box.Y + 48 + i * 30 + (1 - row) * 6;
                dc.PushOpacity(row);
                Point mark = new Point(box.X + 30, y + 9);
                dc.DrawEllipse(B(Green, 0.18), new Pen(B(Green, 0.55), 1), mark, 9, 9);
                StreamGeometry tick = new StreamGeometry();
                using (StreamGeometryContext g = tick.Open())
                {
                    g.BeginFigure(new Point(mark.X - 4, mark.Y), false, false);
                    g.LineTo(new Point(mark.X - 1.2, mark.Y + 3), true, true);
                    g.LineTo(new Point(mark.X + 4.2, mark.Y - 3.2), true, true);
                }
                tick.Freeze();
                dc.DrawGeometry(null, new Pen(B(Green), 1.8), tick);
                Text(dc, Summary[i], 12, Regular, B("#FFFFFF"), box.X + 50, y, BW - 66, false);
                dc.Pop();
            }
            double foot = box.Bottom - 46;
            dc.DrawRectangle(B("#FFFFFF", 0.10), null, new Rect(box.X + 20, foot, BW - 40, 1));
            Text(dc, Total, 11, Regular, B("#B8B3B0"), box.X + 20, foot + 14, BW - 40, false);
            dc.Pop();
        }

        // The pointer goes from button to button, arriving as the real window shows the
        // button being hovered, and leaves a ring where it presses.
        void Pointer(DrawingContext dc, double t, double drop)
        {
            double h1 = FilmOf(hover1), c1 = FilmOf(click1), h2 = FilmOf(hover2), c2 = FilmOf(click2);
            double h3 = FilmOf(hover3), c3 = FilmOf(click3), closes = Closes;
            Point start = new Point(ox + fw * 0.40, oy + fh * 0.84);
            Point rest = new Point(ox + fw * 0.62, oy + fh * 0.90);
            Point at;
            if (t < h1) at = Mix(start, debloat, EaseInOut(P(t, h1 - 0.9, h1)));
            else if (t < c1 + 0.3) at = debloat;
            else if (t < h2) at = Mix(debloat, confirm, EaseInOut(P(t, Math.Max(c1 + 0.3, h2 - 0.8), h2)));
            else if (t < c2 + 0.35) at = confirm;
            else if (t < h3 - 0.9) at = Mix(confirm, rest, EaseInOut(P(t, c2 + 0.35, c2 + 1.05)));
            else if (t < h3) at = Mix(rest, done, EaseInOut(P(t, h3 - 0.9, h3)));
            else at = done;
            at = new Point(Math.Round(at.X), Math.Round(at.Y + drop));

            double alpha = P(t, Opens + 0.55, Opens + 0.8) * (1 - P(t, closes - 0.15, closes + 0.1));
            if (alpha <= 0) return;

            foreach (double click in new[] { c1, c2, c3 })
            {
                double ring = P(t, click, click + 0.45);
                if (ring <= 0 || ring >= 1) continue;
                double radius = 7 + 24 * EaseOut(ring);
                dc.DrawEllipse(null, new Pen(B(Coral, 0.85 * (1 - ring)), 2.5), at, radius, radius);
            }

            bool down = (t > c1 - 0.08 && t < c1 + 0.1) || (t > c2 - 0.08 && t < c2 + 0.1) || (t > c3 - 0.08 && t < c3 + 0.1);
            double size = down ? 0.9 : 1.0;
            StreamGeometry arrow = new StreamGeometry();
            using (StreamGeometryContext g = arrow.Open())
            {
                double[] shape = { 0, 0, 0, 17, 4.4, 13, 7.3, 19.6, 9.9, 18.5, 7, 12.1, 12.6, 12.1 };
                g.BeginFigure(new Point(at.X, at.Y), true, true);
                for (int i = 2; i < shape.Length; i += 2) g.LineTo(new Point(at.X + shape[i] * 1.25 * size, at.Y + shape[i + 1] * 1.25 * size), true, true);
            }
            arrow.Freeze();
            dc.PushOpacity(alpha);
            dc.DrawGeometry(B("#FFFFFF"), new Pen(B("#101014"), 1.4), arrow);
            dc.Pop();
        }

        void WipeLine(DrawingContext dc, double x)
        {
            dc.DrawRectangle(B(Coral), null, new Rect(x - 1.5, 0, 3, H));
            dc.DrawEllipse(B(Coral), new Pen(B("#FFFFFF", 0.9), 2), new Point(x, H * 0.5), 17, 17);
            Text(dc, Chevrons, 15, Bold, B(Ink), x, H * 0.5 - 12, 40, true);
            Label(dc, "AFTER", x - 76, 64, true);
            Label(dc, "BEFORE", x + 14, 64, false);
        }

        void Label(DrawingContext dc, string text, double x, double y, bool filled)
        {
            double width = text.Length * 7.4 + 20;
            if (filled) dc.DrawRoundedRectangle(B(Coral), null, new Rect(x, y, width, 22), 6, 6);
            else dc.DrawRoundedRectangle(B("#101014", 0.86), new Pen(B("#FFFFFF", 0.22), 1), new Rect(x, y, width, 22), 6, 6);
            Text(dc, text, 10.5, Bold, filled ? B(Ink) : B("#FFFFFF"), x + width / 2, y + 4, width, true);
        }

        void Caption(DrawingContext dc, int number, string text, double alpha)
        {
            if (alpha <= 0.01) return;
            FormattedText words = Words(text, 13.5, Semibold, B("#FFFFFF"));
            double y = Math.Round(11 - (1 - alpha) * 6);
            Rect box = new Rect(16, y, words.Width + 62, 38);
            dc.PushOpacity(alpha);
            dc.DrawRoundedRectangle(B("#101014", 0.9), new Pen(B("#FFFFFF", 0.2), 1), box, 19, 19);
            dc.DrawEllipse(B(Coral), null, new Point(box.X + 21, box.Y + 19), 12, 12);
            Text(dc, number.ToString(CultureInfo.InvariantCulture), 12.5, Bold, B(Ink), box.X + 21, box.Y + 10, 24, true);
            dc.DrawText(words, new Point(box.X + 42, box.Y + 10));
            dc.Pop();
        }

        // ------------------------------------------------------------ The desktop

        // Where things are. The Start panel, the widgets board and the toast.
        const double SX = 372, SY = 92, SW = 536, SH = 572;
        const double BX = 18, BY = 92, BW = 330, BH = 572;
        const double TX = 952, TY = 548, TW = 312, TH = 112;
        const double GridX = SX + 22, GridY = SY + 104, CellW = 82, CellH = 76;
        const double RowsY = SY + 374;

        // name, colour, and whether the recommended selection removes it.
        static readonly string[][] Tiles =
        {
            new[] { "Edge", "#1E88D9", "" },          new[] { "Clipchamp", "#7B5CF0", "x" },   new[] { "Store", "#3B78E7", "" },
            new[] { "Solitaire", "#2E9E5B", "x" },    new[] { "Photos", "#D9539A", "" },       new[] { "Candy Crush", "#F0613A", "x" },
            new[] { "Settings", "#7A7F87", "" },      new[] { "News", "#D93B3B", "x" },        new[] { "Weather", "#F2A81D", "x" },
            new[] { "Calculator", "#4A4F57", "" },    new[] { "To Do", "#3F6FE8", "x" },       new[] { "Maps", "#2FA36B", "x" },
            new[] { "Movies & TV", "#C2428F", "x" },  new[] { "Notepad", "#5FA8E8", "" },      new[] { "Tips", "#2D9CDB", "x" },
            new[] { "Get Help", "#2B88D8", "x" },     new[] { "File Explorer", "#F2C230", "" }, new[] { "Feedback Hub", "#5B6EE1", "x" }
        };

        static Rect Cell(int index) { return new Rect(GridX + (index % 6) * CellW, GridY + (index / 6) * CellH, CellW, CellH); }

        void Desktop(DrawingContext dc, bool clean, double flyouts)
        {
            // Three plain shapes, so the wallpaper needs three colours and never stripes.
            dc.DrawRectangle(B("#123B7C"), null, new Rect(0, 0, W, H));
            dc.DrawEllipse(B("#1A4F9E"), null, new Point(1010, 240), 470, 330);
            dc.DrawEllipse(B("#16458C"), null, new Point(330, 560), 400, 250);

            if (flyouts > 0.002)
            {
                dc.PushOpacity(flyouts);
                if (!clean) Widgets(dc);
                StartMenu(dc, clean);
                if (!clean) Toast(dc);
                dc.Pop();
            }
            Taskbar(dc, clean);
        }

        void Panel(DrawingContext dc, Rect box, string fill)
        {
            for (int i = 6; i >= 1; i--)
            {
                dc.DrawRoundedRectangle(B("#000000", 0.04), null, new Rect(box.X - i * 2, box.Y - i * 2 + 8, box.Width + i * 4, box.Height + i * 4), 12 + i * 2, 12 + i * 2);
            }
            dc.DrawRoundedRectangle(B(fill), new Pen(B("#FFFFFF", 0.12), 1), box, 12, 12);
        }

        void StartMenu(DrawingContext dc, bool clean)
        {
            Panel(dc, new Rect(SX, SY, SW, SH), "#26262B");

            // Search, which also looks on the web as it comes.
            Rect search = new Rect(SX + 24, SY + 22, SW - 48, 34);
            dc.DrawRoundedRectangle(B("#1B1B1F"), new Pen(B("#FFFFFF", 0.10), 1), search, 17, 17);
            dc.DrawEllipse(null, new Pen(B("#9A9AA2"), 1.5), new Point(search.X + 20, search.Y + 16), 5, 5);
            Text(dc, "Search for apps, settings, and documents", 11.5, Regular, B("#9A9AA2"), search.X + 36, search.Y + 9, 300, false);
            if (!clean)
            {
                Rect web = WebChip();
                dc.DrawRoundedRectangle(B("#2C3A57"), null, web, 6, 6);
                Text(dc, "+ web results", 10, Regular, B("#9CC2FF"), web.X + web.Width / 2, web.Y + 4, web.Width, true);
            }

            Text(dc, "Pinned", 12.5, Semibold, B("#FFFFFF"), SX + 34, SY + 74, 200, false);
            dc.DrawRoundedRectangle(B("#FFFFFF", 0.08), null, new Rect(SX + SW - 96, SY + 71, 62, 22), 6, 6);
            Text(dc, "All apps", 10.5, Regular, B("#E6E6EA"), SX + SW - 65, SY + 75, 62, true);

            int place = 0;
            for (int i = 0; i < Tiles.Length; i++)
            {
                bool removed = Tiles[i][2] == "x";
                if (clean && removed) continue;
                Rect cell = Cell(clean ? place : i);
                place++;
                Rect icon = new Rect(cell.X + (CellW - 34) / 2, cell.Y + 6, 34, 34);
                dc.DrawRoundedRectangle(B(Tiles[i][1]), null, icon, 8, 8);
                Text(dc, Tiles[i][0].Substring(0, 1), 15, Bold, B("#FFFFFF", 0.95), icon.X + 17, icon.Y + 7, 34, true);
                Text(dc, Tiles[i][0], 10, Regular, B("#E6E6EA"), cell.X + CellW / 2, cell.Y + 46, CellW - 6, true);
            }

            Text(dc, "Recommended", 12.5, Semibold, B("#FFFFFF"), SX + 34, SY + 346, 200, false);
            Row(dc, 0, 0, "#2E9E5B", "Holiday budget.xlsx", "Yesterday");
            Row(dc, 0, 1, "#5FA8E8", "Notes.txt", "2 hours ago");
            if (!clean)
            {
                Row(dc, 1, 0, "#E8703A", "Suggested app", "From the Store");
                Row(dc, 1, 1, "#3B78E7", "Back up your files", "Suggested");
            }

            dc.DrawRectangle(B("#FFFFFF", 0.08), null, new Rect(SX + 1, SY + SH - 58, SW - 2, 1));
            Point face = new Point(SX + 48, SY + SH - 29);
            dc.DrawEllipse(B("#5B6EE1"), null, face, 14, 14);
            if (clean)
            {
                Text(dc, "You", 11.5, Regular, B("#FFFFFF"), SX + 72, SY + SH - 37, 200, false);
            }
            else
            {
                dc.DrawEllipse(B("#E8B04A"), new Pen(B("#26262B"), 2), new Point(face.X + 11, face.Y - 10), 5, 5);
                Text(dc, "You", 11.5, Regular, B("#FFFFFF"), SX + 72, SY + SH - 45, 200, false);
                Text(dc, "Action needed: finish setting up", 10, Regular, B("#E8B04A"), SX + 72, SY + SH - 29, 240, false);
            }
            dc.DrawEllipse(null, new Pen(B("#E6E6EA"), 1.5), new Point(SX + SW - 46, SY + SH - 29), 7, 7);
        }

        static Rect WebChip() { return new Rect(SX + SW - 24 - 100, SY + 28, 90, 22); }
        static Rect RowBox(int column, int row) { return new Rect(SX + 22 + column * 246, RowsY + row * 50, 246, 46); }

        void Row(DrawingContext dc, int column, int row, string colour, string title, string note)
        {
            Rect box = RowBox(column, row);
            dc.DrawRoundedRectangle(B(colour), null, new Rect(box.X + 12, box.Y + 8, 30, 30), 7, 7);
            Text(dc, title, 11.5, Regular, B("#FFFFFF"), box.X + 52, box.Y + 7, 186, false);
            Text(dc, note, 10, Regular, B("#9A9AA2"), box.X + 52, box.Y + 24, 186, false);
        }

        void Widgets(DrawingContext dc)
        {
            Panel(dc, new Rect(BX, BY, BW, BH), "#202024");
            Text(dc, "Widgets", 12.5, Semibold, B("#FFFFFF"), BX + 18, BY + 15, 200, false);

            Rect weather = new Rect(BX + 14, BY + 44, BW - 28, 92);
            LinearGradientBrush sky = new LinearGradientBrush(C("#2D6CDF"), C("#4FA3F0"), new Point(0, 0), new Point(1, 1));
            sky.Freeze();
            dc.DrawRoundedRectangle(sky, null, weather, 10, 10);
            Text(dc, "21" + Degree, 30, Bold, B("#FFFFFF"), weather.X + 16, weather.Y + 12, 120, false);
            Text(dc, "Sunny", 11.5, Regular, B("#FFFFFF", 0.9), weather.X + 16, weather.Y + 58, 120, false);
            dc.DrawEllipse(B("#FFD15C"), null, new Point(weather.Right - 46, weather.Y + 44), 20, 20);

            string[] pictures = { "#B4553A", "#3A7CA5", "#6B8E4E" };
            for (int i = 0; i < 3; i++)
            {
                Rect card = new Rect(BX + 14, BY + 146 + i * 138, BW - 28, 128);
                dc.DrawRoundedRectangle(B("#2A2A2F"), null, card, 10, 10);
                dc.DrawRoundedRectangle(B(pictures[i]), null, new Rect(card.X + 10, card.Y + 10, 96, 108), 8, 8);
                double x = card.X + 118;
                dc.DrawRoundedRectangle(B("#D0D0D6", 0.9), null, new Rect(x, card.Y + 18, 164, 9), 4, 4);
                dc.DrawRoundedRectangle(B("#D0D0D6", 0.9), null, new Rect(x, card.Y + 36, 150, 9), 4, 4);
                dc.DrawRoundedRectangle(B("#D0D0D6", 0.9), null, new Rect(x, card.Y + 54, 104, 9), 4, 4);
                if (i == 1) Text(dc, "Sponsored", 9.5, Regular, B("#E8B04A"), x, card.Y + 96, 120, false);
                else dc.DrawRoundedRectangle(B("#7A7A84"), null, new Rect(x, card.Y + 100, 70, 7), 3, 3);
            }
        }

        void Toast(DrawingContext dc)
        {
            Panel(dc, new Rect(TX, TY, TW, TH), "#2B2B30");
            dc.DrawRoundedRectangle(B("#3B78E7"), null, new Rect(TX + 14, TY + 14, 28, 28), 7, 7);
            Text(dc, "Finish setting up your device", 11.5, Semibold, B("#FFFFFF"), TX + 52, TY + 12, 250, false);
            dc.DrawRoundedRectangle(B("#B8B8C0", 0.7), null, new Rect(TX + 52, TY + 36, 220, 7), 3, 3);
            dc.DrawRoundedRectangle(B("#B8B8C0", 0.7), null, new Rect(TX + 52, TY + 50, 160, 7), 3, 3);
            dc.DrawRoundedRectangle(B("#3B78E7"), null, new Rect(TX + 14, TY + 74, 138, 26), 5, 5);
            Text(dc, "Continue", 10.5, Semibold, B("#FFFFFF"), TX + 83, TY + 80, 138, true);
            dc.DrawRoundedRectangle(B("#FFFFFF", 0.10), null, new Rect(TX + 160, TY + 74, 138, 26), 5, 5);
            Text(dc, "Remind me later", 10.5, Regular, B("#E6E6EA"), TX + 229, TY + 80, 138, true);
        }

        static Rect WeatherButton() { return new Rect(10, H - Bar + 7, 112, 30); }

        void Taskbar(DrawingContext dc, bool clean)
        {
            double top = H - Bar;
            dc.DrawRectangle(B("#1B1B1F"), null, new Rect(0, top, W, Bar));
            dc.DrawRectangle(B("#FFFFFF", 0.08), null, new Rect(0, top, W, 1));

            if (!clean)
            {
                Rect button = WeatherButton();
                dc.DrawEllipse(B("#FFD15C"), null, new Point(button.X + 16, button.Y + 15), 9, 9);
                Text(dc, "21" + Degree + "C", 11, Semibold, B("#FFFFFF"), button.X + 34, button.Y + 1, 70, false);
                Text(dc, "Sunny", 9.5, Regular, B("#B0B0B8"), button.X + 34, button.Y + 15, 70, false);
            }

            double x = 506, mid = top + Bar / 2.0;
            for (int i = 0; i < 4; i++)
            {
                dc.DrawRectangle(B("#5CB8FF"), null, new Rect(x + (i % 2) * 9, mid - 8.5 + (i / 2) * 9, 8, 8));
            }
            dc.DrawRoundedRectangle(B("#2C2C31"), null, new Rect(x + 32, mid - 14, 150, 28), 14, 14);
            dc.DrawEllipse(null, new Pen(B("#9A9AA2"), 1.5), new Point(x + 50, mid - 1), 5, 5);
            Text(dc, "Search", 11, Regular, B("#9A9AA2"), x + 64, mid - 8, 80, false);
            string[] pinned = { "#F2C230", "#1E88D9", "#3B78E7" };
            for (int i = 0; i < pinned.Length; i++)
            {
                dc.DrawRoundedRectangle(B(pinned[i]), null, new Rect(x + 196 + i * 34, mid - 13, 26, 26), 6, 6);
            }

            Text(dc, "09:41", 11, Regular, B("#FFFFFF"), W - 96, top + 7, 80, false, true);
            Text(dc, "20/11/2026", 10, Regular, B("#D0D0D6"), W - 96, top + 22, 80, false, true);
        }

        // ------------------------------------------------------------ What gets pointed out

        // Before the window opens, each kind of clutter is ringed and named in turn.
        void Tags(DrawingContext dc, double t)
        {
            double fade = 1 - P(t, Opens - 0.35, Opens - 0.05);
            if (fade <= 0) return;
            dc.PushOpacity(fade);

            double at = 0.55, step = 0.4;
            Ring(dc, t, at, new Rect(BX, BY, BW, BH), 12, "NEWS FEED", BX + 14, BY - 11);
            Ring(dc, t, at, WeatherButton(), 8, null, 0, 0);

            at += step;
            bool named = false;
            for (int i = 0; i < Tiles.Length; i++)
            {
                if (Tiles[i][2] != "x") continue;
                Rect cell = Cell(i);
                Ring(dc, t, at + i * 0.018, new Rect(cell.X + 5, cell.Y + 1, CellW - 10, CellH - 12), 9, named ? null : "PREINSTALLED APPS", cell.X + 5, cell.Y - 12);
                named = true;
            }

            at += step + 0.2;
            Rect first = RowBox(1, 0);
            Ring(dc, t, at, new Rect(first.X + 4, first.Y, 238, 96), 9, "SUGGESTIONS", first.X + 12, first.Y - 11);

            at += step;
            Ring(dc, t, at, new Rect(SX + 24, SY + SH - 52, 262, 44), 9, "REMINDERS", SX + 34, SY + SH - 63);

            at += step;
            Rect web = WebChip();
            Ring(dc, t, at, new Rect(web.X - 4, web.Y - 4, web.Width + 8, web.Height + 8), 9, "WEB RESULTS", web.X - 96, web.Y + 1);

            at += step;
            Ring(dc, t, at, new Rect(TX, TY, TW, TH), 12, "SETUP NAGS", TX + 14, TY - 11);

            dc.Pop();
        }

        void Ring(DrawingContext dc, double t, double from, Rect box, double radius, string name, double nameX, double nameY)
        {
            double x = P(t, from, from + 0.28);
            if (x <= 0) return;
            double grow = (1 - EaseBack(x)) * 5;
            Rect ring = new Rect(box.X - 3 - grow, box.Y - 3 - grow, box.Width + 6 + grow * 2, box.Height + 6 + grow * 2);
            dc.PushOpacity(Math.Min(1, x * 1.6));
            dc.DrawRoundedRectangle(B(Coral, 0.10), new Pen(B(Coral), 2), ring, radius + 2, radius + 2);
            if (name != null) Label(dc, name, nameX, nameY - (1 - EaseOut(x)) * -5, true);
            dc.Pop();
        }

        // ------------------------------------------------------------ Drawing helpers

        static Typeface Face(FontWeight weight)
        {
            return new Typeface(new FontFamily("Segoe UI Variable Text, Segoe UI"), FontStyles.Normal, weight, FontStretches.Normal);
        }

        static Color C(string hex) { return (Color)ColorConverter.ConvertFromString(hex); }

        static SolidColorBrush B(string hex) { return B(hex, 1); }

        static SolidColorBrush B(string hex, double alpha)
        {
            string key = hex + "|" + alpha.ToString("0.###", CultureInfo.InvariantCulture);
            SolidColorBrush brush;
            if (brushes.TryGetValue(key, out brush)) return brush;
            Color colour = C(hex);
            colour.A = (byte)Math.Round(255 * Math.Max(0, Math.Min(1, alpha)));
            brush = new SolidColorBrush(colour);
            brush.Freeze();
            brushes[key] = brush;
            return brush;
        }

        static FormattedText Words(string text, double size, Typeface face, Brush brush)
        {
            return new FormattedText(text, CultureInfo.InvariantCulture, FlowDirection.LeftToRight, face, size, brush, null, TextFormattingMode.Display, 1.0);
        }

        void Text(DrawingContext dc, string text, double size, Typeface face, Brush brush, double x, double y, double width, bool centred)
        {
            Text(dc, text, size, face, brush, x, y, width, centred, false);
        }

        // One line of text. Centred text is centred on x; text to the right ends at x + width.
        void Text(DrawingContext dc, string text, double size, Typeface face, Brush brush, double x, double y, double width, bool centred, bool right)
        {
            FormattedText words = Words(text, size, face, brush);
            words.MaxTextWidth = width;
            words.MaxLineCount = 1;
            words.Trimming = TextTrimming.CharacterEllipsis;
            if (centred) { words.TextAlignment = TextAlignment.Center; x -= width / 2; }
            else if (right) words.TextAlignment = TextAlignment.Right;
            dc.DrawText(words, new Point(Math.Round(x), Math.Round(y)));
        }
    }

    // How much of the film each colour covers.
    public sealed class Histogram
    {
        public readonly Dictionary<int, int> Seen = new Dictionary<int, int>();

        public void Add(int[] pixels, int step)
        {
            for (int i = 0; i < pixels.Length; i += step)
            {
                int colour = pixels[i] & 0xFFFFFF, count;
                Seen.TryGetValue(colour, out count);
                Seen[colour] = count + 1;
            }
        }
    }

    // The 255 colours of the film. Exact says where a colour has a place of its own.
    public sealed class Palette
    {
        public int[] Colours;
        public Dictionary<int, int> Exact = new Dictionary<int, int>();

        static int Key(int rgb) { return ((rgb >> 9) & 0x7C00) | ((rgb >> 6) & 0x3E0) | ((rgb >> 3) & 0x1F); }
        static int Part(int key, int channel) { return channel == 0 ? (key >> 10) & 31 : channel == 1 ? (key >> 5) & 31 : key & 31; }

        static int Spread(List<int> box, int channel)
        {
            int low = 31, high = 0;
            foreach (int key in box) { int value = Part(key, channel); if (value < low) low = value; if (value > high) high = value; }
            return high - low;
        }

        // The colours that cover the most of the film each get a place of their own.
        // The window is mostly large areas of nearly the same dark, and letting two of
        // those share a place turns a soft gradient into stripes. What is left is put
        // into shades of 15 bits and divided by median cut.
        public static Palette Choose(Histogram film, int count)
        {
            Palette palette = new Palette();
            List<int> colours = new List<int>();
            foreach (KeyValuePair<int, int> entry in film.Seen.OrderByDescending(e => e.Value).Take(count * 2 / 5))
            {
                palette.Exact[entry.Key] = colours.Count;
                colours.Add(entry.Key);
            }

            int[] covered = new int[32768];
            long[] red = new long[32768], green = new long[32768], blue = new long[32768];
            foreach (KeyValuePair<int, int> entry in film.Seen)
            {
                if (palette.Exact.ContainsKey(entry.Key)) continue;
                int key = Key(entry.Key);
                covered[key] += entry.Value;
                red[key] += (long)entry.Value * ((entry.Key >> 16) & 255);
                green[key] += (long)entry.Value * ((entry.Key >> 8) & 255);
                blue[key] += (long)entry.Value * (entry.Key & 255);
            }
            List<int> rest = Enumerable.Range(0, 32768).Where(i => covered[i] > 0).ToList();
            if (rest.Count > 0)
            {
                List<List<int>> boxes = new List<List<int>> { rest };
                while (colours.Count + boxes.Count < count)
                {
                    List<int> box = null;
                    double best = -1;
                    foreach (List<int> candidate in boxes)
                    {
                        if (candidate.Count < 2) continue;
                        int range = Math.Max(Spread(candidate, 0), Math.Max(Spread(candidate, 1), Spread(candidate, 2)));
                        double weight = range * Math.Log(1 + candidate.Sum(i => (double)covered[i]));
                        if (weight > best) { best = weight; box = candidate; }
                    }
                    if (box == null) break;
                    int channel = 0, widest = -1;
                    for (int c = 0; c < 3; c++) { int range = Spread(box, c); if (range > widest) { widest = range; channel = c; } }
                    box.Sort((a, b) => Part(a, channel).CompareTo(Part(b, channel)));
                    long total = box.Sum(i => (long)covered[i]), running = 0;
                    int cut = 1;
                    for (int i = 0; i < box.Count - 1; i++)
                    {
                        running += covered[box[i]];
                        if (running >= total / 2) { cut = i + 1; break; }
                    }
                    boxes.Remove(box);
                    boxes.Add(box.GetRange(0, cut));
                    boxes.Add(box.GetRange(cut, box.Count - cut));
                }
                foreach (List<int> box in boxes)
                {
                    // The colour the pixels really had, not the middle of their shade.
                    long n = 0, r = 0, g = 0, b = 0;
                    foreach (int key in box) { n += covered[key]; r += red[key]; g += green[key]; b += blue[key]; }
                    colours.Add(((int)(r / n) << 16) | ((int)(g / n) << 8) | (int)(b / n));
                }
            }
            palette.Colours = colours.ToArray();
            return palette;
        }
    }

    // A small animated GIF writer, after the one in WinZones: one palette for the whole
    // film, only the part of a frame that changed is stored, and LZW.
    public sealed class Gif : IDisposable
    {
        readonly Stream stream;
        readonly int width, height;
        readonly Palette palette;
        readonly int[] nearest = Enumerable.Repeat(-1, 32768).ToArray();
        byte[] previous;
        byte[] pending;
        int pendingX, pendingY, pendingWidth, pendingHeight, pendingDelay = -1;
        const byte Transparent = 255;

        // A pattern of sixteen steps. A colour without a place of its own is nudged by it
        // before the closest colour is looked up, so a soft gradient becomes a fine
        // weave of two colours instead of stripes. It depends only on where the pixel
        // is, so what stands still stays exactly the same from frame to frame.
        static readonly int[] Weave = { 0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5 };

        public Gif(string path, int width, int height, Palette palette)
        {
            this.width = width;
            this.height = height;
            this.palette = palette;
            stream = File.Create(path);
            BinaryWriter writer = new BinaryWriter(stream);
            writer.Write(new[] { (byte)'G', (byte)'I', (byte)'F', (byte)'8', (byte)'9', (byte)'a' });
            writer.Write((short)width);
            writer.Write((short)height);
            writer.Write((byte)0xF7);
            writer.Write((byte)0);
            writer.Write((byte)0);
            for (int i = 0; i < 256; i++)
            {
                int colour = i < palette.Colours.Length ? palette.Colours[i] : 0;
                writer.Write((byte)((colour >> 16) & 255));
                writer.Write((byte)((colour >> 8) & 255));
                writer.Write((byte)(colour & 255));
            }
            // Play it over and over.
            writer.Write(new byte[] { 0x21, 0xFF, 0x0B });
            writer.Write(System.Text.Encoding.ASCII.GetBytes("NETSCAPE2.0"));
            writer.Write(new byte[] { 3, 1, 0, 0, 0 });
        }

        byte Map(int argb, int x, int y)
        {
            int rgb = argb & 0xFFFFFF, index;
            if (palette.Exact.TryGetValue(rgb, out index)) return (byte)index;

            int nudge = Weave[(y & 3) * 4 + (x & 3)] / 2 - 4;
            int r = Math.Max(0, Math.Min(255, ((rgb >> 16) & 255) + nudge)) >> 3;
            int g = Math.Max(0, Math.Min(255, ((rgb >> 8) & 255) + nudge)) >> 3;
            int b = Math.Max(0, Math.Min(255, (rgb & 255) + nudge)) >> 3;
            int key = (r << 10) | (g << 5) | b;
            int known = nearest[key];
            if (known >= 0) return (byte)known;

            // The closest colour to the middle of this shade.
            r = r * 8 + 4; g = g * 8 + 4; b = b * 8 + 4;
            int best = 0, least = int.MaxValue;
            for (int i = 0; i < palette.Colours.Length; i++)
            {
                int colour = palette.Colours[i];
                int dr = ((colour >> 16) & 255) - r, dg = ((colour >> 8) & 255) - g, db = (colour & 255) - b;
                int distance = dr * dr * 3 + dg * dg * 4 + db * db * 2;
                if (distance < least) { least = distance; best = i; }
            }
            nearest[key] = best;
            return (byte)best;
        }

        public void AddFrame(int[] pixels, int hundredths)
        {
            byte[] indexed = new byte[pixels.Length];
            for (int y = 0, o = 0; y < height; y++)
            {
                for (int x = 0; x < width; x++, o++) indexed[o] = Map(pixels[o], x, y);
            }

            int x0 = 0, y0 = 0, x1 = width - 1, y1 = height - 1;
            if (previous != null)
            {
                x0 = width; y0 = height; x1 = -1; y1 = -1;
                for (int y = 0; y < height; y++)
                {
                    for (int x = 0, o = y * width; x < width; x++, o++)
                    {
                        if (indexed[o] == previous[o]) continue;
                        if (x < x0) x0 = x;
                        if (x > x1) x1 = x;
                        if (y < y0) y0 = y;
                        if (y > y1) y1 = y;
                    }
                }
                // Nothing moved: the frame before simply stays up longer.
                if (x1 < 0) { pendingDelay += hundredths; return; }
            }
            int w = x1 - x0 + 1, h = y1 - y0 + 1;
            byte[] part = new byte[w * h];
            for (int y = 0; y < h; y++)
            {
                for (int x = 0; x < w; x++)
                {
                    int o = (y0 + y) * width + x0 + x;
                    part[y * w + x] = previous != null && indexed[o] == previous[o] ? Transparent : indexed[o];
                }
            }
            Flush();
            pending = part; pendingX = x0; pendingY = y0; pendingWidth = w; pendingHeight = h; pendingDelay = hundredths;
            previous = indexed;
        }

        void Flush()
        {
            if (pending == null) return;
            BinaryWriter writer = new BinaryWriter(stream);
            writer.Write(new byte[] { 0x21, 0xF9, 4, (byte)((1 << 2) | 1) });
            writer.Write((short)Math.Max(2, pendingDelay));
            writer.Write(Transparent);
            writer.Write((byte)0);
            writer.Write((byte)0x2C);
            writer.Write((short)pendingX);
            writer.Write((short)pendingY);
            writer.Write((short)pendingWidth);
            writer.Write((short)pendingHeight);
            writer.Write((byte)0);
            Lzw(pending);
            pending = null;
        }

        // LZW as in giflib: the code grows after a code is written, once the next one needs it.
        void Lzw(byte[] data)
        {
            stream.WriteByte(8);
            List<byte> output = new List<byte>(data.Length / 2 + 16);
            int bits = 0, held = 0, codeSize = 9, next = 258;
            Action<int> emit = code =>
            {
                bits |= code << held;
                held += codeSize;
                while (held >= 8) { output.Add((byte)(bits & 255)); bits >>= 8; held -= 8; }
                if (next >= (1 << codeSize) && codeSize < 12) codeSize++;
            };
            Dictionary<int, int> table = new Dictionary<int, int>();
            emit(256);
            int prefix = data[0];
            for (int i = 1; i < data.Length; i++)
            {
                int value = data[i];
                int key = (prefix << 8) | value;
                int code;
                if (table.TryGetValue(key, out code)) { prefix = code; continue; }
                emit(prefix);
                if (next >= 4095)
                {
                    emit(256);
                    table.Clear();
                    next = 258;
                    codeSize = 9;
                }
                else
                {
                    table[key] = next++;
                }
                prefix = value;
            }
            emit(prefix);
            emit(257);
            if (held > 0) output.Add((byte)(bits & 255));
            byte[] bytes = output.ToArray();
            for (int i = 0; i < bytes.Length; i += 255)
            {
                int count = Math.Min(255, bytes.Length - i);
                stream.WriteByte((byte)count);
                stream.Write(bytes, i, count);
            }
            stream.WriteByte(0);
        }

        public void Dispose()
        {
            Flush();
            stream.WriteByte(0x3B);
            stream.Dispose();
        }
    }
}
