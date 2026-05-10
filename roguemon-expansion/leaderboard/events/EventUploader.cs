// RogueMon Event Uploader: C# port of packages/event-uploader/src/*.ts
//
// Build with the stock .NET Framework compiler on Windows 11 (no SDK required):
//   C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe ^
//       /nologo /optimize /target:exe /out:event-uploader.exe ^
//       /reference:System.Net.Http.dll EventUploader.cs
//
// Or with MSBuild:
//   C:\Windows\Microsoft.NET\Framework64\v4.0.30319\MSBuild.exe EventUploader.csproj /p:Configuration=Release
//
// All runtime files (events.txt, heartbeat.txt, error.txt, uploader.lock) live
// alongside event-uploader.exe, exactly as the TypeScript version did.

using System;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Reflection;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

[assembly: AssemblyTitle("RogueMon Event Uploader")]
[assembly: AssemblyDescription("Watches events.txt and posts to the RogueMon event handler.")]
[assembly: AssemblyCompany("RogueMon")]
[assembly: AssemblyProduct("RogueMon Leaderboard")]
[assembly: AssemblyVersion("1.0.0.0")]
[assembly: AssemblyFileVersion("1.0.0.0")]

namespace RogueMon.EventUploader
{
    public static class Program
    {
        // Selectable at launch via -t / --target {prod|dev|local}. Defaults to
        // prod. Set in Main from ParseTarget; treated as immutable thereafter.
        const string HandlerUrlProd  = "https://roguemonevent-handler-production.up.railway.app";
        const string HandlerUrlDev   = "https://roguemonevent-handler-dev.up.railway.app";
        const string HandlerUrlLocal = "http://127.0.0.1:3000";
        static string HandlerUrl = HandlerUrlProd;

        const int DebounceMs = 100;
        const int HeartbeatIntervalMs = 1000;
        const double StaleHeartbeatSeconds = 5.0;

        static readonly HttpClient Http = new HttpClient();
        static readonly object SyncLock = new object();

        static string eventFilePath;
        static string errorFilePath;
        static string heartbeatFilePath;
        static string lockPath;

        static Timer debounceTimer;
        static Timer heartbeatTimer;
        static FileSystemWatcher watcher;
        static int cleanupCalled;

        public static int Main(string[] args)
        {
            Console.OutputEncoding = Encoding.UTF8;
            // Resize the console to 20 rows x 70 cols.
            Console.Write("\x1b[8;20;70t");

            // .NET Framework 4.6.x defaults SecurityProtocol to SSL3/TLS 1.0, which
            // modern HTTPS servers (Railway / Cloudflare) reject -> "Could not create
            // SSL/TLS secure channel." Force TLS 1.2+.
            ServicePointManager.SecurityProtocol |= SecurityProtocolType.Tls12;

            string targetError;
            if (!TryParseTarget(args, out HandlerUrl, out targetError))
            {
                Console.Error.WriteLine(targetError);
                Console.Error.WriteLine("Usage: event-uploader.exe [-t|--target prod|dev|local]");
                return 2;
            }
            Console.WriteLine("Target: " + HandlerUrl);

            string baseDir = Path.GetDirectoryName(Assembly.GetEntryAssembly().Location);
            eventFilePath = Path.Combine(baseDir, "events.txt");
            errorFilePath = Path.Combine(baseDir, "error.txt");
            heartbeatFilePath = Path.Combine(baseDir, "heartbeat.txt");
            lockPath = Path.Combine(baseDir, "uploader.lock");

            if (IsAlive())
            {
                Console.WriteLine("Uploader already running. Exiting.");
                return 0;
            }

            // Heartbeat is stale but lock file exists -> clean it up.
            if (File.Exists(lockPath))
            {
                try { File.Delete(lockPath); } catch { }
            }

            if (File.Exists(lockPath))
            {
                Console.WriteLine("Uploader already running (lock file). Exiting.");
                return 0;
            }

            try
            {
                File.WriteAllText(
                    lockPath,
                    Process.GetCurrentProcess().Id.ToString(CultureInfo.InvariantCulture));
            }
            catch (Exception ex)
            {
                Console.WriteLine("Unable to create lock file: " + ex.Message);
                return 1;
            }

            Console.WriteLine(
@" ______ _______ _______ _______ _______ _______ _______ _______
|   __ \       |     __|   |   |    ___|   |   |       |    |  |
|      <   -   |    |  |   |   |    ___|       |   -   |       |
|___|__|_______|_______|_______|_______|__|_|__|_______|__|____|
  _______ ______ _____   _______ _______ _____  _______ ______
 |   |   |   __ \     |_|       |   _   |     \|    ___|   __ \
 |   |   |    __/       |   -   |       |  --  |    ___|      <
 |_______|___|  |_______|_______|___|___|_____/|_______|___|__|
");

            Console.CancelKeyPress += OnCancelKey;
            AppDomain.CurrentDomain.ProcessExit += OnProcessExit;

            try
            {
                RunAsync().GetAwaiter().GetResult();
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine("Fatal: " + ex);
                Cleanup();
                return 1;
            }

            return 0;
        }

        static async Task RunAsync()
        {
            if (await PerformHandshakeAsync())
            {
                StartHeartbeat();
                StartWatcher();
            }

            Console.WriteLine();
            Console.WriteLine("Press any key to stop the uploader...");
            bool stdinRedirected = false;
            try
            {
                Console.ReadKey(true);
            }
            catch (InvalidOperationException)
            {
                stdinRedirected = true;
            }
            if (stdinRedirected || Console.IsInputRedirected || Console.IsOutputRedirected)
            {
                // stdin redirected -- block forever; SIGINT/SIGTERM still cleans up.
                await Task.Delay(Timeout.Infinite);
            }

            Cleanup();
            Environment.Exit(0);
        }

        // -------- Target selection --------

        static bool TryParseTarget(string[] args, out string handlerUrl, out string error)
        {
            handlerUrl = HandlerUrlProd;
            error = null;

            string target = null;
            for (int i = 0; i < args.Length; i++)
            {
                string a = args[i];
                if (a == "-t" || a == "--target")
                {
                    if (i + 1 >= args.Length)
                    {
                        error = "Missing value for " + a + " (expected prod|dev|local)";
                        return false;
                    }
                    target = args[++i];
                }
                else if (a.StartsWith("--target=", StringComparison.Ordinal))
                {
                    target = a.Substring("--target=".Length);
                }
                else
                {
                    error = "Unknown argument: " + a;
                    return false;
                }
            }

            if (target == null) return true; // default: prod

            switch (target.ToLowerInvariant())
            {
                case "prod":  handlerUrl = HandlerUrlProd;  return true;
                case "dev":   handlerUrl = HandlerUrlDev;   return true;
                case "local": handlerUrl = HandlerUrlLocal; return true;
                default:
                    error = "Unknown target '" + target + "' (expected prod|dev|local)";
                    return false;
            }
        }

        // -------- Single-instance heartbeat check --------

        static bool IsAlive()
        {
            try
            {
                string content = File.ReadAllText(heartbeatFilePath).Trim();
                double timestamp;
                if (!double.TryParse(content, NumberStyles.Float, CultureInfo.InvariantCulture, out timestamp))
                    return false;
                double nowSec = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds() / 1000.0;
                return (nowSec - timestamp) < StaleHeartbeatSeconds;
            }
            catch
            {
                return false;
            }
        }

        // -------- Lifecycle --------

        static void OnCancelKey(object sender, ConsoleCancelEventArgs e)
        {
            e.Cancel = true;
            Cleanup();
            Environment.Exit(0);
        }

        static void OnProcessExit(object sender, EventArgs e)
        {
            Cleanup();
        }

        static void Cleanup()
        {
            if (Interlocked.Exchange(ref cleanupCalled, 1) != 0) return;

            try { File.Delete(lockPath); } catch { }
            StopHeartbeat();
            StopWatcher();
        }

        // -------- Heartbeat --------

        static void StartHeartbeat()
        {
            // First write: ms since epoch.
            try
            {
                File.WriteAllText(
                    heartbeatFilePath,
                    DateTimeOffset.UtcNow.ToUnixTimeMilliseconds().ToString(CultureInfo.InvariantCulture));
            }
            catch (Exception ex)
            {
                Console.WriteLine("Unable to write heartbeat file: " + heartbeatFilePath + " " + ex.Message);
            }

            heartbeatTimer = new Timer(_ =>
            {
                try
                {
                    double sec = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds() / 1000.0;
                    File.WriteAllText(
                        heartbeatFilePath,
                        sec.ToString("0.000", CultureInfo.InvariantCulture));
                }
                catch (Exception ex)
                {
                    Console.WriteLine("Unable to write heartbeat file: " + heartbeatFilePath + " " + ex.Message);
                }
            }, null, HeartbeatIntervalMs, HeartbeatIntervalMs);
        }

        static void StopHeartbeat()
        {
            if (heartbeatTimer != null)
            {
                heartbeatTimer.Dispose();
                heartbeatTimer = null;
            }
            try { File.Delete(heartbeatFilePath); } catch { }
        }

        // -------- Watcher --------

        static void StartWatcher()
        {
            string fullPath = Path.GetFullPath(eventFilePath);
            string dir = Path.GetDirectoryName(fullPath);
            string fileName = Path.GetFileName(fullPath);

            if (!File.Exists(fullPath))
            {
                File.WriteAllText(fullPath, "");
            }

            Console.WriteLine("Watching " + fileName + " for changes...");

            watcher = new FileSystemWatcher(dir, fileName);
            watcher.NotifyFilter = NotifyFilters.LastWrite | NotifyFilters.Size | NotifyFilters.FileName | NotifyFilters.CreationTime;
            watcher.Changed += OnFileChanged;
            watcher.Created += OnFileChanged;
            watcher.Renamed += OnFileRenamed;
            watcher.EnableRaisingEvents = true;
        }

        static void OnFileChanged(object sender, FileSystemEventArgs e)
        {
            ScheduleDebouncedUpload();
        }

        static void OnFileRenamed(object sender, RenamedEventArgs e)
        {
            ScheduleDebouncedUpload();
        }

        static void ScheduleDebouncedUpload()
        {
            lock (SyncLock)
            {
                if (debounceTimer != null)
                {
                    debounceTimer.Dispose();
                }
                debounceTimer = new Timer(_ =>
                {
                    lock (SyncLock)
                    {
                        if (debounceTimer != null)
                        {
                            debounceTimer.Dispose();
                            debounceTimer = null;
                        }
                    }
                    try
                    {
                        string data = ReadFileShared(eventFilePath);
                        // Fire-and-forget; UploadEventAsync handles its own errors.
                        var _ignored = UploadEventAsync(data);
                    }
                    catch (Exception ex)
                    {
                        Console.Error.WriteLine("Error processing file change: " + ex.Message);
                    }
                }, null, DebounceMs, Timeout.Infinite);
            }
        }

        // FileShare.ReadWrite so we don't collide with whatever external process writes events.txt.
        static string ReadFileShared(string path)
        {
            using (var fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
            using (var sr = new StreamReader(fs, Encoding.UTF8))
            {
                return sr.ReadToEnd();
            }
        }

        static void StopWatcher()
        {
            lock (SyncLock)
            {
                if (debounceTimer != null)
                {
                    debounceTimer.Dispose();
                    debounceTimer = null;
                }
            }
            if (watcher != null)
            {
                try
                {
                    watcher.EnableRaisingEvents = false;
                    watcher.Dispose();
                }
                catch { }
                watcher = null;
            }
        }

        // -------- Handshake + Upload --------

        static async Task<bool> PerformHandshakeAsync()
        {
            try
            {
                var response = await Http.GetAsync(HandlerUrl + "/handshake");
                if (response.IsSuccessStatusCode)
                {
                    Console.WriteLine("Handshake successful!");
                    return true;
                }
                string errorMsg = "Handshake failed: " + ((int)response.StatusCode) + " " + response.ReasonPhrase;
                Console.Error.WriteLine(errorMsg);
                WriteError(errorMsg);
                return false;
            }
            catch (Exception ex)
            {
                string errorMsg = "Handshake error: " + ex.Message;
                Console.Error.WriteLine(errorMsg);
                WriteError(errorMsg);
                return false;
            }
        }

        static async Task UploadEventAsync(string queryString)
        {
            try
            {
                Console.WriteLine("Handler Url: " + HandlerUrl + "/run");
                Console.WriteLine("Uploading event:  " + queryString);
                var body = new StringContent(
                    "payload=" + Uri.EscapeDataString(queryString),
                    Encoding.UTF8,
                    "application/x-www-form-urlencoded");
                var response = await Http.PostAsync(HandlerUrl + "/run", body);
                if (response.IsSuccessStatusCode)
                {
                    Console.WriteLine("Event uploaded successfully");
                    ClearError();
                }
                else
                {
                    string errorMsg = "Upload failed: " + ((int)response.StatusCode) + " " + response.ReasonPhrase;
                    Console.Error.WriteLine(errorMsg);
                    WriteError(errorMsg);
                }
            }
            catch (Exception ex)
            {
                string errorMsg = "Upload error: " + ex.Message;
                Console.Error.WriteLine(errorMsg);
                WriteError(errorMsg);
            }
        }

        // -------- Error file --------

        static void WriteError(string error)
        {
            if (string.IsNullOrEmpty(errorFilePath)) return;
            try { File.WriteAllText(errorFilePath, error); } catch { }
        }

        static void ClearError()
        {
            if (string.IsNullOrEmpty(errorFilePath)) return;
            try { File.Delete(errorFilePath); } catch { }
        }
    }
}
