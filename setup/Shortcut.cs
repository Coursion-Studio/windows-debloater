// Writes and reads shortcut files (.lnk).
//
// A shortcut made here carries the same application id the window gives itself, so
// Windows knows the Start menu entry and the open window are one program: the window
// groups under it in the taskbar, and pinning either pins the same thing.

using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;
using System.Text;
using System.Threading;

namespace Debloater.Setup
{
    static class Shortcut
    {
        [ComImport, Guid("00021401-0000-0000-C000-000000000046")]
        class ShellLink { }

        [ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown), Guid("000214F9-0000-0000-C000-000000000046")]
        interface IShellLinkW
        {
            void GetPath([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder file, int length, IntPtr findData, uint flags);
            void GetIDList(out IntPtr list);
            void SetIDList(IntPtr list);
            void GetDescription([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder name, int length);
            void SetDescription([MarshalAs(UnmanagedType.LPWStr)] string name);
            void GetWorkingDirectory([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder folder, int length);
            void SetWorkingDirectory([MarshalAs(UnmanagedType.LPWStr)] string folder);
            void GetArguments([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder arguments, int length);
            void SetArguments([MarshalAs(UnmanagedType.LPWStr)] string arguments);
            void GetHotkey(out short hotkey);
            void SetHotkey(short hotkey);
            void GetShowCmd(out int show);
            void SetShowCmd(int show);
            void GetIconLocation([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder path, int length, out int index);
            void SetIconLocation([MarshalAs(UnmanagedType.LPWStr)] string path, int index);
            void SetRelativePath([MarshalAs(UnmanagedType.LPWStr)] string path, uint reserved);
            void Resolve(IntPtr window, uint flags);
            void SetPath([MarshalAs(UnmanagedType.LPWStr)] string file);
        }

        [ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown), Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99")]
        interface IPropertyStore
        {
            void GetCount(out uint count);
            void GetAt(uint index, out PropertyKey key);
            void GetValue(ref PropertyKey key, out PropVariant value);
            void SetValue(ref PropertyKey key, ref PropVariant value);
            void Commit();
        }

        [StructLayout(LayoutKind.Sequential, Pack = 4)]
        struct PropertyKey
        {
            public Guid Id;
            public uint Number;
        }

        // Only the string kind is used here. The size is that of the whole Windows
        // structure, so Windows never writes past the end of it.
        [StructLayout(LayoutKind.Explicit, Size = 24)]
        struct PropVariant
        {
            [FieldOffset(0)] public ushort Kind;
            [FieldOffset(8)] public IntPtr Pointer;
        }

        [DllImport("ole32.dll")]
        static extern int PropVariantClear(ref PropVariant value);

        const ushort StringKind = 31;

        // System.AppUserModel.ID
        static PropertyKey AppIdKey()
        {
            var key = new PropertyKey();
            key.Id = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3");
            key.Number = 5;
            return key;
        }

        public static void Create(string file, string target, string folder, string description, string appId)
        {
            OnItsOwnThread(delegate ()
            {
                var link = (IShellLinkW)new ShellLink();
                try
                {
                    link.SetPath(target);
                    link.SetWorkingDirectory(folder);
                    link.SetDescription(description);
                    link.SetIconLocation(target, 0);
                    if (!string.IsNullOrEmpty(appId))
                    {
                        var store = (IPropertyStore)link;
                        PropertyKey key = AppIdKey();
                        var value = new PropVariant();
                        value.Kind = StringKind;
                        value.Pointer = Marshal.StringToCoTaskMemUni(appId);
                        try
                        {
                            store.SetValue(ref key, ref value);
                            store.Commit();
                        }
                        finally { PropVariantClear(ref value); }
                    }
                    Directory.CreateDirectory(Path.GetDirectoryName(file));
                    ((IPersistFile)link).Save(file, true);
                }
                finally { Marshal.ReleaseComObject(link); }
            });
        }

        // What a shortcut starts and which application id it carries. Null where a
        // value is missing or the file is not a shortcut that can be read.
        public static void Read(string file, out string target, out string appId)
        {
            string foundTarget = null;
            string foundId = null;
            try
            {
                OnItsOwnThread(delegate ()
                {
                    var link = (IShellLinkW)new ShellLink();
                    try
                    {
                        ((IPersistFile)link).Load(file, 0);
                        var path = new StringBuilder(1024);
                        link.GetPath(path, path.Capacity, IntPtr.Zero, 0);
                        if (path.Length > 0) foundTarget = path.ToString();

                        var store = (IPropertyStore)link;
                        PropertyKey key = AppIdKey();
                        PropVariant value;
                        store.GetValue(ref key, out value);
                        try
                        {
                            if (value.Kind == StringKind && value.Pointer != IntPtr.Zero)
                                foundId = Marshal.PtrToStringUni(value.Pointer);
                        }
                        finally { PropVariantClear(ref value); }
                    }
                    finally { Marshal.ReleaseComObject(link); }
                });
            }
            catch { }
            target = foundTarget;
            appId = foundId;
        }

        // The part of Windows that handles shortcuts wants a thread of the kind a
        // window has. The installer may be working on another kind, so each call gets
        // a thread of its own.
        static void OnItsOwnThread(ThreadStart work)
        {
            Exception problem = null;
            var thread = new Thread(delegate ()
            {
                try { work(); }
                catch (Exception caught) { problem = caught; }
            });
            thread.SetApartmentState(ApartmentState.STA);
            thread.Start();
            thread.Join();
            if (problem != null) throw new InvalidOperationException(problem.Message, problem);
        }
    }
}
