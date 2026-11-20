// The setup window: what to choose, a bar while it works, and how it went.
//
// The layout and every colour are in SetupWindow.xaml. This file fills in the words
// and moves from one page to the next. What is actually done to the PC is in
// Installer.cs.

using System;
using System.IO;
using System.Reflection;
using System.Text;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Markup;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

namespace Debloater.Setup
{
    class SetupWindow
    {
        enum Kind { Install, Update, Reinstall, Uninstall }

        readonly Window window;
        readonly bool straightAway;
        Kind kind;
        string installedVersion;
        bool motion;
        bool busy;
        bool launched;
        // True while the pages are only being drawn into pictures: nothing takes the
        // keyboard then, so a key pressed elsewhere cannot turn a page.
        bool drawing;
        int result;

        readonly FrameworkElement panel, bar, pageStart, pageLicence, pageWork, pageDone, pageFail, optSecondRow, startFine, doneMedal, workTrack, workFill;
        readonly StackPanel licenceBody;
        readonly Image startHero;
        readonly TextBlock barTitle, startHeading, startVersion, startSay, optFirstTitle, optFirstSub, optSecondTitle, optSecondSub,
            startFineText, startAgree, licenceHeading, goGlyph, goText, workHeading, workStatus, doneHeading, doneSay, failHeading, failDetail;
        readonly ToggleButton optFirst, optSecond;
        readonly Button btnClose, btnCancel, btnGo, btnLicenceBack, btnDoneClose, btnDoneOpen, btnFailClose;

        // straightAway is how the tool updates itself: no questions, the bar, and the
        // tool opens again.
        public SetupWindow(bool uninstall, bool straightAway)
        {
            this.straightAway = straightAway && !uninstall;
            installedVersion = Installer.IsInstalled ? Installer.InstalledVersion : null;
            if (uninstall) kind = Kind.Uninstall;
            else if (!Installer.IsInstalled) kind = Kind.Install;
            else kind = installedVersion == Installer.Version ? Kind.Reinstall : Kind.Update;
            // No movement when Windows is set to show none, as in the tool itself.
            motion = SystemParameters.ClientAreaAnimation && Environment.GetEnvironmentVariable("DEBLOATER_MOTION") != "0";

            using (Stream layout = Assembly.GetExecutingAssembly().GetManifestResourceStream("SetupWindow.xaml"))
                window = (Window)XamlReader.Load(layout);

            panel = Find<FrameworkElement>("Panel");
            bar = Find<FrameworkElement>("Bar");
            pageStart = Find<FrameworkElement>("PageStart");
            pageLicence = Find<FrameworkElement>("PageLicence");
            licenceBody = Find<StackPanel>("LicenceBody");
            licenceHeading = Find<TextBlock>("LicenceHeading");
            startAgree = Find<TextBlock>("StartAgree");
            btnLicenceBack = Find<Button>("BtnLicenceBack");
            pageWork = Find<FrameworkElement>("PageWork");
            pageDone = Find<FrameworkElement>("PageDone");
            pageFail = Find<FrameworkElement>("PageFail");
            optSecondRow = Find<FrameworkElement>("OptSecondRow");
            startFine = Find<FrameworkElement>("StartFine");
            doneMedal = Find<FrameworkElement>("DoneMedal");
            workTrack = Find<FrameworkElement>("WorkTrack");
            workFill = Find<FrameworkElement>("WorkFill");
            startHero = Find<Image>("StartHero");
            barTitle = Find<TextBlock>("BarTitle");
            startHeading = Find<TextBlock>("StartHeading");
            startVersion = Find<TextBlock>("StartVersion");
            startSay = Find<TextBlock>("StartSay");
            optFirstTitle = Find<TextBlock>("OptFirstTitle");
            optFirstSub = Find<TextBlock>("OptFirstSub");
            optSecondTitle = Find<TextBlock>("OptSecondTitle");
            optSecondSub = Find<TextBlock>("OptSecondSub");
            startFineText = Find<TextBlock>("StartFineText");
            goGlyph = Find<TextBlock>("BtnGoGlyph");
            goText = Find<TextBlock>("BtnGoText");
            workHeading = Find<TextBlock>("WorkHeading");
            workStatus = Find<TextBlock>("WorkStatus");
            doneHeading = Find<TextBlock>("DoneHeading");
            doneSay = Find<TextBlock>("DoneSay");
            failHeading = Find<TextBlock>("FailHeading");
            failDetail = Find<TextBlock>("FailDetail");
            optFirst = Find<ToggleButton>("OptFirst");
            optSecond = Find<ToggleButton>("OptSecond");
            btnClose = Find<Button>("BtnClose");
            btnCancel = Find<Button>("BtnCancel");
            btnGo = Find<Button>("BtnGo");
            btnDoneClose = Find<Button>("BtnDoneClose");
            btnDoneOpen = Find<Button>("BtnDoneOpen");
            btnFailClose = Find<Button>("BtnFailClose");

            ImageSource icon = LoadIcon();
            window.Icon = icon;
            Find<Image>("BarIcon").Source = icon;
            startHero.Source = icon;
            Find<Image>("WorkHero").Source = icon;

            bar.MouseLeftButtonDown += delegate (object sender, MouseButtonEventArgs e)
            {
                if (e.ButtonState == MouseButtonState.Pressed) window.DragMove();
            };
            window.Closing += delegate (object sender, System.ComponentModel.CancelEventArgs e) { if (busy) e.Cancel = true; };
            window.PreviewKeyDown += delegate (object sender, KeyEventArgs e)
            {
                if (e.Key != Key.Escape || busy) return;
                e.Handled = true;
                // Esc on the licence goes back to where it was opened from.
                if (pageLicence.Visibility == Visibility.Visible) Show(pageStart, btnGo);
                else window.Close();
            };
            btnLicenceBack.Click += delegate { Show(pageStart, btnGo); };
            btnClose.Click += delegate { window.Close(); };
            btnCancel.Click += delegate { window.Close(); };
            btnFailClose.Click += delegate { window.Close(); };
            btnDoneClose.Click += delegate { window.Close(); };
            btnDoneOpen.Click += delegate
            {
                if (!launched && kind != Kind.Uninstall)
                {
                    try { Installer.Launch(); } catch (Exception problem) { Program.Log(problem); }
                }
                window.Close();
            };
            btnGo.Click += delegate { Begin(); };

            SetTitle();
            if (this.straightAway)
            {
                ShowWork();
                window.Loaded += delegate { Begin(); };
            }
            else ShowStart();

            window.Loaded += delegate
            {
                if (!motion) return;
                window.BeginAnimation(UIElement.OpacityProperty, new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(220)));
                var slide = (TranslateTransform)panel.RenderTransform;
                slide.BeginAnimation(TranslateTransform.YProperty, Ease(8, 0, 320));
            };
        }

        public int Run()
        {
            var app = new Application();
            app.ShutdownMode = ShutdownMode.OnMainWindowClose;
            app.Run(window);
            return result;
        }

        T Find<T>(string name) where T : class
        {
            var found = window.FindName(name) as T;
            if (found == null) throw new InvalidOperationException("The setup window has no element named " + name + ".");
            return found;
        }

        static ImageSource LoadIcon()
        {
            using (Stream picture = Assembly.GetExecutingAssembly().GetManifestResourceStream("icon.png"))
            {
                var image = new BitmapImage();
                image.BeginInit();
                image.StreamSource = picture;
                image.CacheOption = BitmapCacheOption.OnLoad;
                image.EndInit();
                image.Freeze();
                return image;
            }
        }

        static string T(string key, params object[] values) { return Texts.Get(key, values); }

        static DoubleAnimation Ease(double from, double to, int milliseconds)
        {
            var move = new DoubleAnimation(from, to, TimeSpan.FromMilliseconds(milliseconds));
            move.EasingFunction = new QuinticEase { EasingMode = EasingMode.EaseOut };
            return move;
        }

        // ------------------------------------------------------------ pages

        void SetTitle()
        {
            string title = T(kind == Kind.Uninstall ? "setup.title.uninstall" : "setup.title");
            window.Title = title;
            barTitle.Text = title;
        }

        void Show(FrameworkElement page, Button main)
        {
            foreach (FrameworkElement each in new[] { pageStart, pageLicence, pageWork, pageDone, pageFail })
                each.Visibility = each == page ? Visibility.Visible : Visibility.Collapsed;
            foreach (Button each in new[] { btnGo, btnLicenceBack, btnDoneOpen, btnFailClose }) each.IsDefault = each == main;
            if (main != null && !drawing) main.Focus();
            if (!motion || !window.IsLoaded) return;
            page.BeginAnimation(UIElement.OpacityProperty, new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(220)));
            ((TranslateTransform)page.RenderTransform).BeginAnimation(TranslateTransform.YProperty, Ease(10, 0, 320));
        }

        void ShowStart()
        {
            bool removing = kind == Kind.Uninstall;
            startHero.Width = startHero.Height = removing ? 72 : 84;
            optFirst.IsChecked = !removing;
            if (removing)
            {
                startHeading.Text = T("setup.uninstall.heading");
                startVersion.Text = T("setup.version", installedVersion ?? Installer.Version);
                startSay.Text = T("setup.uninstall.say");
                optFirstTitle.Text = T("setup.opt.purge");
                optFirstSub.Text = T("setup.opt.purge.sub");
                optFirstSub.Visibility = Visibility.Visible;
                optSecondRow.Visibility = Visibility.Collapsed;
                startFine.Visibility = Visibility.Collapsed;
                startAgree.Visibility = Visibility.Collapsed;
                btnGo.Style = (Style)window.FindResource("DangerButton");
                goGlyph.Text = "\uE74D";
                goText.Text = T("setup.btn.uninstall");
            }
            else
            {
                string word = kind == Kind.Update ? "update" : kind == Kind.Reinstall ? "reinstall" : "install";
                startHeading.Text = T("setup." + word + ".heading");
                startVersion.Text = kind == Kind.Update && !string.IsNullOrEmpty(installedVersion)
                    ? T("setup.version.update", installedVersion, Installer.Version)
                    : T("setup.version", Installer.Version);
                startSay.Text = T("setup.say");
                optFirstTitle.Text = T("setup.opt.open");
                optFirstSub.Visibility = Visibility.Collapsed;
                optSecondRow.Visibility = Visibility.Visible;
                optSecondTitle.Text = T("setup.opt.desktop");
                optSecondSub.Text = T("setup.opt.desktop.sub");
                // An update keeps a desktop shortcut that is already there.
                optSecond.IsChecked = kind != Kind.Install && Installer.HasDesktopShortcut;
                startFine.Visibility = Visibility.Visible;
                startFineText.Text = T("setup.fine");
                SetAgreement();
                btnGo.Style = (Style)window.FindResource("PrimaryButton");
                goGlyph.Text = "\uE896";
                goText.Text = T("setup.btn." + word);
            }
            btnCancel.Content = T("setup.btn.cancel");
            Show(pageStart, btnGo);
        }

        // "By installing you agree to the licence", with the licence as a link to read it.
        void SetAgreement()
        {
            string[] around = T("setup.agree", "|").Split('|');
            var link = new Hyperlink(new Run(T("setup.agree.link")));
            link.Foreground = (Brush)window.FindResource("AccentText");
            link.TextDecorations = null;
            link.Cursor = Cursors.Hand;
            link.Click += delegate { ShowLicence(); };
            startAgree.Inlines.Clear();
            startAgree.Inlines.Add(new Run(around[0]));
            startAgree.Inlines.Add(link);
            if (around.Length > 1) startAgree.Inlines.Add(new Run(around[1]));
            startAgree.Visibility = Visibility.Visible;
        }

        // The licence that travels with the program, laid out plainly: its headings in
        // bold, its lists with dots, everything else as paragraphs.
        void ShowLicence()
        {
            if (licenceBody.Children.Count == 0)
            {
                string text = Installer.ReadPacked("LICENSE.md") ?? "";
                var paragraph = new StringBuilder();
                Action flush = delegate
                {
                    if (paragraph.Length == 0) return;
                    licenceBody.Children.Add(Paragraph(paragraph.ToString(), false));
                    paragraph.Length = 0;
                };
                foreach (string raw in text.Replace("\r", "").Split('\n'))
                {
                    string line = raw.Trim();
                    if (line.Length == 0) { flush(); continue; }
                    // The title is the heading of the page already.
                    if (line.StartsWith("# ", StringComparison.Ordinal)) { flush(); continue; }
                    if (line.StartsWith("## ", StringComparison.Ordinal)) { flush(); licenceBody.Children.Add(Paragraph(line.Substring(3), true)); continue; }
                    if (line.StartsWith("- ", StringComparison.Ordinal)) { flush(); licenceBody.Children.Add(Paragraph((char)0x2022 + "  " + line.Substring(2), false)); continue; }
                    if (paragraph.Length > 0) paragraph.Append(' ');
                    paragraph.Append(line);
                }
                flush();
            }
            licenceHeading.Text = T("setup.licence.heading");
            btnLicenceBack.Content = T("setup.btn.back");
            Show(pageLicence, btnLicenceBack);
        }

        TextBlock Paragraph(string text, bool heading)
        {
            var block = new TextBlock();
            block.Text = text;
            block.TextWrapping = TextWrapping.Wrap;
            block.FontSize = heading ? 12.5 : 12;
            block.LineHeight = 18;
            block.FontWeight = heading ? FontWeights.SemiBold : FontWeights.Normal;
            block.Foreground = (Brush)window.FindResource(heading ? "Text" : "Text2");
            block.Margin = new Thickness(0, licenceBody.Children.Count == 0 ? 0 : (heading ? 14 : 6), 0, 0);
            return block;
        }

        void ShowWork()
        {
            string word = kind == Kind.Uninstall ? "uninstall" : kind == Kind.Install ? "install" : "update";
            workHeading.Text = T("setup.work." + word);
            workStatus.Text = T("setup.step.start");
            workFill.BeginAnimation(FrameworkElement.WidthProperty, null);
            workFill.Width = 0;
            Show(pageWork, null);
        }

        void SetProgress(double done, string step)
        {
            string key = "setup.step." + step;
            if (kind == Kind.Uninstall && step == "shortcut") key = "setup.step.unlink";
            workStatus.Text = T(key);
            double width = Math.Max(0, workTrack.ActualWidth * Math.Min(1, done));
            if (motion) workFill.BeginAnimation(FrameworkElement.WidthProperty, Ease(workFill.ActualWidth, width, 260));
            else workFill.Width = width;
        }

        void ShowDone(bool opened, bool purged)
        {
            launched = opened;
            if (kind == Kind.Uninstall)
            {
                doneHeading.Text = T("setup.removed.heading");
                doneSay.Text = T(purged ? "setup.removed.say" : "setup.removed.say.kept");
                btnDoneClose.Visibility = Visibility.Collapsed;
                btnDoneOpen.Content = T("setup.btn.close");
            }
            else
            {
                doneHeading.Text = T(kind == Kind.Install ? "setup.done.heading" : "setup.done.heading.update");
                doneSay.Text = T("setup.done.say");
                // It is open already when the switch was on, so there is only Done to press.
                btnDoneClose.Visibility = opened ? Visibility.Collapsed : Visibility.Visible;
                btnDoneClose.Content = T("setup.btn.close");
                btnDoneOpen.Content = T(opened ? "setup.btn.done" : "setup.btn.open");
            }
            Show(pageDone, btnDoneOpen);
            if (motion && window.IsLoaded)
            {
                var pop = new DoubleAnimation(0.6, 1, TimeSpan.FromMilliseconds(420));
                pop.EasingFunction = new BackEase { EasingMode = EasingMode.EaseOut, Amplitude = 0.5 };
                var scale = (ScaleTransform)doneMedal.RenderTransform;
                scale.BeginAnimation(ScaleTransform.ScaleXProperty, pop);
                scale.BeginAnimation(ScaleTransform.ScaleYProperty, pop);
            }
        }

        void ShowFail(Exception problem)
        {
            failHeading.Text = T(kind == Kind.Uninstall ? "setup.fail.uninstall" : "setup.fail.install");
            failDetail.Text = problem is SetupProblem ? T(problem.Message) : problem.Message;
            btnFailClose.Content = T("setup.btn.close");
            Show(pageFail, btnFailClose);
        }

        // ------------------------------------------------------------ doing it

        async void Begin()
        {
            if (busy) return;
            bool first = optFirst.IsChecked == true;
            bool second = optSecond.IsChecked == true;
            bool removing = kind == Kind.Uninstall;
            bool openAfter = !removing && (straightAway || first);
            // The tool updating itself changes nothing about the desktop shortcut.
            bool desktop = straightAway ? false : second;

            busy = true;
            btnClose.IsEnabled = false;
            if (!straightAway) ShowWork();
            Action<double, string> report = delegate (double done, string step)
            {
                window.Dispatcher.BeginInvoke(new Action(delegate { SetProgress(done, step); }));
            };

            Exception problem = null;
            try
            {
                if (removing) await Task.Run(delegate { Installer.Uninstall(first, report); });
                else await Task.Run(delegate { Installer.Install(desktop, report); });
                // Long enough to see the bar reach the end.
                await Task.Delay(motion ? 450 : 0);
                if (openAfter) Installer.Launch();
            }
            catch (Exception caught)
            {
                problem = caught;
                result = 1;
                Program.Log(caught);
            }
            busy = false;
            btnClose.IsEnabled = true;

            if (problem != null) ShowFail(problem);
            else if (straightAway) window.Close();
            else ShowDone(openAfter, removing && first);
        }

        // ------------------------------------------------------------ pictures of itself

        // Draws every page into PNG files, off screen and without touching the PC. The
        // README's pictures come from here, and it is how the look is checked.
        public void SaveShots(string folder)
        {
            motion = false;
            drawing = true;
            window.Focusable = false;
            Directory.CreateDirectory(folder);
            window.WindowStartupLocation = WindowStartupLocation.Manual;
            window.Left = -20000;
            window.Top = -20000;
            window.ShowInTaskbar = false;
            window.ShowActivated = false;
            window.Show();

            kind = Kind.Install; installedVersion = null; SetTitle(); ShowStart();
            Shot(folder, "install");
            optSecond.IsChecked = true; optFirst.IsChecked = false;
            Shot(folder, "install-options");
            ShowLicence();
            Shot(folder, "licence");
            Show(pageStart, btnGo);
            ShowWork(); Settle(); SetProgress(0.7, "shortcut");
            Shot(folder, "working");
            ShowDone(true, false);
            Shot(folder, "done");
            ShowDone(false, false);
            Shot(folder, "done-not-opened");
            kind = Kind.Update; installedVersion = "0.3.0"; ShowStart();
            Shot(folder, "update");
            ShowDone(true, false);
            Shot(folder, "updated");
            kind = Kind.Uninstall; installedVersion = Installer.Version; SetTitle(); ShowStart();
            Shot(folder, "uninstall");
            ShowDone(false, false);
            Shot(folder, "removed");
            ShowFail(new SetupProblem("setup.problem.open"));
            Shot(folder, "failed");
            window.Close();
        }

        // Waits until the page has been laid out and a switch has finished sliding.
        void Settle()
        {
            DateTime until = DateTime.UtcNow.AddMilliseconds(320);
            do
            {
                window.Dispatcher.Invoke(DispatcherPriority.ApplicationIdle, new Action(delegate { }));
                System.Threading.Thread.Sleep(15);
            }
            while (DateTime.UtcNow < until);
            window.UpdateLayout();
            window.Dispatcher.Invoke(DispatcherPriority.Render, new Action(delegate { }));
        }

        void Shot(string folder, string name)
        {
            Settle();
            const double scale = 2;
            var picture = new RenderTargetBitmap((int)Math.Ceiling(window.ActualWidth * scale), (int)Math.Ceiling(window.ActualHeight * scale),
                96 * scale, 96 * scale, PixelFormats.Pbgra32);
            picture.Render(panel);
            var encoder = new PngBitmapEncoder();
            encoder.Frames.Add(BitmapFrame.Create(picture));
            using (FileStream file = File.Create(Path.Combine(folder, "setup-" + name + ".png"))) encoder.Save(file);
        }
    }
}
