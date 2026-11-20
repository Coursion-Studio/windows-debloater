// The installer's words. They are not written here: they come from the same language
// files the tool reads (src\lang\en.json and the others), which travel inside the
// installer with the rest of the program. The keys start with "setup.".

using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Text;
using System.Web.Script.Serialization;

namespace Debloater.Setup
{
    static class Texts
    {
        static Dictionary<string, string> chosen = new Dictionary<string, string>();
        static Dictionary<string, string> english = new Dictionary<string, string>();

        public static string Language = "en";

        // Picks the language: the one asked for, or the one the tool was last used in,
        // or the one Windows is shown in. English where there is no file for it.
        public static void Load(string asked)
        {
            var files = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            try
            {
                using (Stream packed = Assembly.GetExecutingAssembly().GetManifestResourceStream("payload.zip"))
                using (var zip = new ZipArchive(packed, ZipArchiveMode.Read))
                {
                    foreach (ZipArchiveEntry entry in zip.Entries)
                    {
                        string name = entry.FullName.Replace('/', '\\');
                        if (!name.StartsWith("src\\lang\\", StringComparison.OrdinalIgnoreCase) || !name.EndsWith(".json", StringComparison.OrdinalIgnoreCase)) continue;
                        using (var reader = new StreamReader(entry.Open(), Encoding.UTF8))
                            files[Path.GetFileNameWithoutExtension(name)] = reader.ReadToEnd();
                    }
                }
            }
            catch { }

            string code = asked;
            if (string.IsNullOrEmpty(code)) code = Remembered();
            if (string.IsNullOrEmpty(code)) code = CultureInfo.CurrentUICulture.TwoLetterISOLanguageName;
            if (!files.ContainsKey(code)) code = "en";
            Language = code;

            english = files.ContainsKey("en") ? Parse(files["en"]) : new Dictionary<string, string>();
            chosen = code == "en" ? english : Parse(files[code]);
        }

        // The language chosen on the tool's Settings page, if it has been used before.
        static string Remembered()
        {
            try
            {
                string file = Path.Combine(Installer.DataDir, "settings.json");
                if (!File.Exists(file)) return null;
                Dictionary<string, string> saved = Parse(File.ReadAllText(file, Encoding.UTF8));
                string code;
                return saved.TryGetValue("lang", out code) ? code : null;
            }
            catch { return null; }
        }

        static Dictionary<string, string> Parse(string json)
        {
            var result = new Dictionary<string, string>();
            try
            {
                var read = new JavaScriptSerializer().Deserialize<Dictionary<string, object>>(json);
                foreach (KeyValuePair<string, object> pair in read)
                    if (pair.Value != null) result[pair.Key] = Convert.ToString(pair.Value, CultureInfo.InvariantCulture);
            }
            catch { }
            return result;
        }

        public static string Get(string key, params object[] values)
        {
            string text;
            if (!chosen.TryGetValue(key, out text) && !english.TryGetValue(key, out text)) return key;
            return values.Length == 0 ? text : string.Format(text, values);
        }

        public static bool Has(string key)
        {
            return chosen.ContainsKey(key) || english.ContainsKey(key);
        }
    }
}
