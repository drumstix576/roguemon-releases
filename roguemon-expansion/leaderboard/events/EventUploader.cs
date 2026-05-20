// RogueMon Event Uploader (in-process library).
//
// Replaces the former standalone event-uploader.exe + events.txt watcher.
// The tracker loads this assembly's bytes and calls UploadEvent via NLua
// reflection (see FileIOManager.initUploader). There is no lock file,
// heartbeat, events.txt cache, FileSystemWatcher, debounce, or process.
//
// Compiled on the player's machine (see FileIOManager.compileEventUploader)
// with the stock .NET Framework compiler, NOT bundled prebuilt, so the
// release ships only source -- no binary artifact and no Mark-of-the-Web-
// tagged DLL in a downloaded .zip. initUploader loads it in-memory via
// Assembly.Load(byte[]), which also sidesteps the mapped-drive codebase
// bind that Assembly.LoadFrom(path) cannot resolve.
//   Windows: csc.exe /target:library /out:RoguemonEventUploader.dll \
//                    /reference:System.Net.Http.dll EventUploader.cs
//   Linux:   mcs -target:library -out:RoguemonEventUploader.dll \
//                 -r:System.Net.Http.dll EventUploader.cs
// Kept C# 5-compatible (no string interpolation / ?. / nameof) so the
// legacy v4.0.30319 csc.exe can build it.
//
// Threading contract: UploadEvent returns immediately. The POST runs on a
// thread-pool thread and MUST NOT call back into the Lua state (NLua is
// single-threaded and non-reentrant). All result/error reporting therefore
// goes to a per-run log file written from the CLR side only.

using System;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace RogueMon.EventUploader
{
    public static class Uploader
    {
        // URL constants stay here as the single source of truth (Lua passes a
        // target token, not a URL, exactly as the old --target arg did).
        const string HandlerUrlProd  = "https://roguemonevent-handler-production.up.railway.app";
        const string HandlerUrlDev   = "https://roguemonevent-handler-dev.up.railway.app";
        const string HandlerUrlLocal = "http://127.0.0.1:3000";

        // Static state lives in the assembly, which is loaded into the BizHawk
        // host AppDomain once and survives tracker/Lua reloads. Configure() may
        // be called again on reload with the same values; that is harmless.
        static readonly HttpClient Http;
        static readonly SemaphoreSlim Gate = new SemaphoreSlim(1, 1);
        static readonly object LogLock = new object();

        static string handlerUrl = HandlerUrlProd;
        static string logPath;

        static Uploader()
        {
            // .NET Framework / Mono default to SSL3/TLS1.0, which Railway /
            // Cloudflare reject. Harmless no-op on modern .NET (OS negotiates).
            try { ServicePointManager.SecurityProtocol |= SecurityProtocolType.Tls12; }
            catch (NotSupportedException) { }
            Http = new HttpClient();
        }

        // target: "prod" | "dev" | "local" (unknown -> prod, matching the old
        // TryParseTarget default). logFilePath: absolute path to this run's log
        // file; the directory is created if missing. Not truncated, so a
        // mid-run tracker reload appends to the same run's log.
        public static void Configure(string target, string logFilePath)
        {
            switch ((target ?? "").ToLowerInvariant())
            {
                case "dev":   handlerUrl = HandlerUrlDev;   break;
                case "local": handlerUrl = HandlerUrlDev; break;
                default:      handlerUrl = HandlerUrlProd;  break;
            }

            logPath = logFilePath;
            if (!string.IsNullOrEmpty(logPath))
            {
                string dir = Path.GetDirectoryName(logPath);
                if (!string.IsNullOrEmpty(dir))
                {
                    Directory.CreateDirectory(dir);
                }
            }
            Log("CONFIG", "target=" + handlerUrl);
        }

        // Diagnostic reachability probe. Fire-and-forget; logs only. Unlike the
        // old process this does NOT gate uploads -- there is no way to feed an
        // async result back to Lua, and event POSTs report their own failures.
        public static void Handshake()
        {
            string url = handlerUrl + "/handshake";
            Task.Run(async () =>
            {
                try
                {
                    var resp = await Http.GetAsync(url);
                    Log(resp.IsSuccessStatusCode ? "HANDSHAKE_OK" : "HANDSHAKE_FAIL",
                        ((int)resp.StatusCode) + " " + resp.ReasonPhrase);
                }
                catch (Exception ex)
                {
                    Log("HANDSHAKE_ERROR", ex.Message);
                }
            });
        }

        // Fire-and-forget event upload. Returns immediately. POSTs are
        // serialized through Gate so they reach the backend in submission
        // order (the old debounce coalescing is gone with events.txt). The
        // request line is logged on the caller thread; the result/error is
        // logged from the continuation.
        public static void UploadEvent(string payload)
        {
            Log("REQUEST", payload);
            string url = handlerUrl + "/run";
            Task.Run(async () =>
            {
                await Gate.WaitAsync();
                try
                {
                    var body = new StringContent(
                        "payload=" + Uri.EscapeDataString(payload ?? ""),
                        Encoding.UTF8,
                        "application/x-www-form-urlencoded");
                    var resp = await Http.PostAsync(url, body);
                    if (resp.IsSuccessStatusCode)
                    {
                        Log("OK", ((int)resp.StatusCode).ToString(CultureInfo.InvariantCulture));
                    }
                    else
                    {
                        Log("FAIL", ((int)resp.StatusCode) + " " + resp.ReasonPhrase);
                    }
                }
                catch (Exception ex)
                {
                    Log("ERROR", ex.Message);
                }
                finally
                {
                    Gate.Release();
                }
            });
        }

        static void Log(string kind, string detail)
        {
            if (string.IsNullOrEmpty(logPath)) return;
            string line = DateTime.UtcNow.ToString("o", CultureInfo.InvariantCulture)
                + " [" + kind + "] " + detail + Environment.NewLine;
            try
            {
                lock (LogLock)
                {
                    File.AppendAllText(logPath, line, Encoding.UTF8);
                }
            }
            catch (Exception ex)
            {
                // The log is the only sink; if it is unwritable surface to the
                // debugger/Trace rather than silently dropping or recursing.
                Debug.WriteLine("[RoguemonEventUploader] log write failed: " + ex.Message);
            }
        }
    }
}
