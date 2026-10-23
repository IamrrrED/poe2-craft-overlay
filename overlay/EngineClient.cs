using System.Diagnostics;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Poe2CraftOverlay;

/// Talks to the Lua engine, which owns every number the overlay shows.
///
/// The engine runs in serving mode: it stays alive and answers requests written as small Lua
/// files, exactly the protocol mcp/engine.js uses. The overlay therefore needs no calculator of
/// its own, and the one engine that already passed 590 tests keeps being the only source of truth.
internal sealed class EngineClient : IDisposable
{
    private readonly string _root;
    private readonly string _src;
    private readonly string _host;
    private Process? _hostProcess;

    public EngineClient()
    {
        _root = FindProjectRoot();
        _src = Path.Combine(_root, "src");
        // Headless: the calculations run on plain LuaJIT with no host at all, so the process has no
        // windows - nothing to flash. The SimpleGraphic host is still used by the Lua panel and stays
        // available as a fallback.
        _host = Path.Combine(_root, "headless", "bin", "Release", "net8.0", "PoE2 Craft Engine.exe");
    }

    public string Root => _root;

    /// Walks up from the executable until the engine's source folder is found, so the overlay can
    /// be started from anywhere - the build output folder, a shortcut, or the project itself.
    private static string FindProjectRoot()
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        while (directory is not null)
        {
            if (File.Exists(Path.Combine(directory.FullName, "src", "Mcp", "api.lua")))
            {
                return directory.FullName;
            }
            directory = directory.Parent;
        }
        return AppContext.BaseDirectory;
    }

    private string FlagPath => Path.Combine(_src, "mcp_serve.flag");
    private string RequestPath => Path.Combine(_src, "mcp_serve_request.lua");
    private string ResponsePath => Path.Combine(_src, "mcp_serve_response.json");

    private void EnsureHost()
    {
        if (_hostProcess is { HasExited: false })
        {
            return;
        }
        if (!File.Exists(_host))
        {
            Log.Write("engine: host executable not found at " + _host);
            return;
        }
        File.WriteAllText(FlagPath, "serving\n", new UTF8Encoding(false));
        _hostProcess = Process.Start(new ProcessStartInfo
        {
            FileName = _host,
            WorkingDirectory = _src,          // headless.lua working dir
            UseShellExecute = false,
            CreateNoWindow = true,
        });
        Log.Write("engine: serving host started (one process for every question)");
    }

    /// Asks one question and waits for the answer. Returns null when the engine does not reply,
    /// so the caller can say so instead of showing invented numbers.
    public async Task<JsonNode?> CallAsync(string tool, IDictionary<string, object?>? args = null, int timeoutMs = 20000)
    {
        EnsureHost();
        var nonce = DateTime.UtcNow.Ticks.ToString("x");
        var request = new StringBuilder();
        request.Append("-- ").Append(nonce).Append('\n');
        request.Append("return { tool = ").Append(LuaString(tool)).Append(", args = ");
        request.Append(LuaTable(args)).Append(" }\n");
        try
        {
            if (File.Exists(ResponsePath))
            {
                File.Delete(ResponsePath);
            }
            File.WriteAllText(RequestPath, request.ToString(), new UTF8Encoding(false));
        }
        catch (Exception error)
        {
            Log.Write("engine: could not write the request: " + error.Message);
            return null;
        }

        var deadline = DateTime.UtcNow.AddMilliseconds(timeoutMs);
        while (DateTime.UtcNow < deadline)
        {
            if (File.Exists(ResponsePath))
            {
                try
                {
                    var text = File.ReadAllText(ResponsePath);
                    File.Delete(ResponsePath);
                    var payload = JsonNode.Parse(text);
                    if (payload?["ok"]?.GetValue<bool>() == true)
                    {
                        Log.Write($"engine: {tool} answered");
                        return payload["result"];
                    }
                    Log.Write($"engine: {tool} refused: " + payload?["error"]);
                    return null;
                }
                catch (JsonException)
                {
                    // the file is still being written
                }
                catch (IOException)
                {
                    // the engine is between writes
                }
            }
            await Task.Delay(25);
        }
        Log.Write($"engine: no answer for {tool} within {timeoutMs} ms");
        return null;
    }

    private static string LuaString(string value)
    {
        var builder = new StringBuilder("\"");
        foreach (var character in value)
        {
            builder.Append(character switch
            {
                '\\' => "\\\\",
                '"' => "\\\"",
                '\n' => "\\n",
                '\r' => "\\r",
                _ => character.ToString(),
            });
        }
        return builder.Append('"').ToString();
    }

    private static string LuaTable(IDictionary<string, object?>? values)
    {
        if (values is null || values.Count == 0)
        {
            return "{ }";
        }
        var parts = new List<string>();
        foreach (var pair in values)
        {
            var encoded = pair.Value switch
            {
                null => "nil",
                string text => LuaString(text),
                bool flag => flag ? "true" : "false",
                int number => number.ToString(),
                long number => number.ToString(),
                double number => number.ToString(System.Globalization.CultureInfo.InvariantCulture),
                _ => LuaString(pair.Value.ToString() ?? ""),
            };
            parts.Add($"[{LuaString(pair.Key)}] = {encoded}");
        }
        return "{ " + string.Join(", ", parts) + " }";
    }

    public void Dispose()
    {
        if (_hostProcess is { HasExited: false })
        {
            try
            {
                _hostProcess.Kill();
            }
            catch
            {
                // already gone
            }
        }
        _hostProcess = null;
        // The flag must not outlive the process that asked for it, or the next engine started for
        // the panel would believe it is a server and hide its own window.
        try
        {
            if (File.Exists(FlagPath))
            {
                File.Delete(FlagPath);
            }
        }
        catch
        {
            // nothing to clean
        }
    }
}