using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Windows.Forms;

namespace Poe2CraftOverlay;

/// The language the panel speaks, and the place that choice is remembered.
///
/// Three states, because the honest default is "whatever the game speaks": the engine reads the game
/// client's language out of the copied item text, so a Russian client already produces Russian data
/// names. "auto" follows that, and the player can pin ru or en from the panel's header when he prefers
/// one regardless of the client.
///
/// The choice lives next to panel-position.ini (user's local application data plus a copy beside the
/// exe), for the same reason: the build output directory is rebuilt, and a setting stored there is lost
/// by the next build.
internal static class PanelLanguage
{
    public const string Auto = "auto";
    public const string Russian = "ru";
    public const string English = "en";

    private static string DurablePath => System.IO.Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "Poe2CraftOverlay", "panel-language.ini");

    private static string LegacyPath => System.IO.Path.Combine(AppContext.BaseDirectory, "panel-language.ini");

    private static IEnumerable<string> CandidatePaths()
    {
        yield return DurablePath;
        yield return LegacyPath;
    }

    /// The saved setting: "ru", "en" or "auto" (the default when nothing was ever chosen).
    //
    // The NEWEST of the two copies wins, not the first one found. The durable copy is written first and
    // lives in the user's own folder; when the panel runs elevated, a later non-elevated run cannot
    // overwrite that file ("access denied", which the log records), so the durable copy goes stale while
    // the copy beside the exe is fresh. Reading the first copy made a fresh choice look ignored on the
    // next start - the same trap the position file has.
    public static string Load()
    {
        var best = Auto;
        var bestWritten = DateTime.MinValue;
        foreach (var path in CandidatePaths())
        {
            try
            {
                if (!File.Exists(path))
                {
                    continue;
                }
                var written = File.GetLastWriteTimeUtc(path);
                var value = File.ReadAllText(path).Trim().ToLowerInvariant();
                if (value != Russian && value != English && value != Auto)
                {
                    Log.Write($"language: '{value}' in {path} is not a language, ignoring it");
                    continue;
                }
                if (written >= bestWritten)
                {
                    best = value;
                    bestWritten = written;
                    Log.Write($"language: {value} read from {path} (written {written:u})");
                }
            }
            catch (Exception error)
            {
                Log.Write($"language: could not read {path}: {error.Message}");
            }
        }
        return best;
    }

    public static void Save(string setting)
    {
        foreach (var path in CandidatePaths())
        {
            try
            {
                var folder = System.IO.Path.GetDirectoryName(path);
                if (!string.IsNullOrEmpty(folder))
                {
                    Directory.CreateDirectory(folder);
                }
                File.WriteAllText(path, setting);
                Log.Write($"language: {setting} saved to {path}");
            }
            catch (Exception error)
            {
                Log.Write($"language: could not save to {path}: {error.Message}");
            }
        }
    }

    /// The language to actually use: the pinned one, or the best guess for "auto".
    /// @param setting what the player chose
    /// @param clientLanguage "ru"/"en" as the engine read it from the last item, null when unknown
    public static string Resolve(string setting, string? clientLanguage)
    {
        if (setting == Russian || setting == English)
        {
            return setting;
        }
        if (clientLanguage == Russian || clientLanguage == English)
        {
            return clientLanguage;
        }
        return FromSystem();
    }

    /// Windows' own interface language, which is the only hint available before the first capture.
    public static string FromSystem()
    {
        try
        {
            var culture = CultureInfo.CurrentUICulture;
            while (!string.IsNullOrEmpty(culture.Name))
            {
                if (culture.TwoLetterISOLanguageName == "ru")
                {
                    return Russian;
                }
                // "en-GB" and the like are still English; anything else ends up English too, because
                // the panel has exactly two languages and English is the one the data is written in.
                break;
            }
        }
        catch (Exception error)
        {
            Log.Write("language: could not read the system language: " + error.Message);
        }
        return English;
    }

    /// The client language of a copied item, judged the way the engine judges it: Cyrillic means Russian.
    public static string? FromItemText(string? itemText)
    {
        if (string.IsNullOrEmpty(itemText))
        {
            return null;
        }
        foreach (var character in itemText)
        {
            if (character >= '\u0400' && character <= '\u04FF')
            {
                return Russian;
            }
        }
        return English;
    }
}

/// The few sentences the panel host itself says.
///
/// The engine owns everything about crafting and answers in the requested language; these are the
/// host's own words - clipboard trouble, the market helper, the trade-site budget - so they cannot come
/// from the engine and have to be carried here. Both languages sit in one file so a missing translation
/// is visible at a glance, and the Russian table is the fallback.
internal static class Messages
{
    private static readonly Dictionary<string, string> Ru = new()
    {
        ["clipboardEmpty"] = "буфер пуст: наведите предмет в игре и нажмите Ctrl+Q",
        ["captureRefused"] = "игра не приняла автоматическое копирование. Наведите предмет, нажмите Ctrl+C, "
            + "затем Ctrl+Q — дальше всё пойдёт по шагам.",
        ["marketScriptMissing"] = "Скрипт рынка не найден рядом с программой.",
        ["marketQueryFailed"] = "Движок не смог составить запрос к рынку.",
        ["marketNoNode"] = "Цену узнать не вышло: нужен Node.js в PATH или переменная POE2CRAFT_NODE.",
        ["marketUnreadable"] = "Рынок вернул нечитаемый ответ.",
        ["marketCooldown"] = "Трейд на паузе ещё {0} с (лимит запросов). Можно подождать или ввести цену вручную.",
        ["marketRefused"] = "Цену взять не удалось: {0}",
        ["marketNoReason"] = "без причины",
        ["marketSuggestions"] = " Похожие базы: {0}.",
        ["marketMedian"] = "Цена рынка: медиана по {0} лотам из {1} найденных.",
        ["marketMatch"] = " Совпадение: {0}.",
        ["marketCached"] = " Ответ трейда кэшируется на {0} с: повторный запрос по этому же предмету может "
            + "быть бесплатным.",
        ["marketQuota"] = " Осталось {0} запросов к трейду в этот час.",
        ["marketNoMedian"] = "Рынок ответил без медианной цены.",
        ["noEngineAnswer"] = "нет ответа analyze_item",
        ["trayShow"] = "Показать панель (Ctrl+Q — захват)",
        ["trayCapture"] = "Захват из буфера",
        ["trayLanguage"] = "Язык",
        ["trayLanguageAuto"] = "Как в игре",
        ["trayLanguageRu"] = "Русский",
        ["trayLanguageEn"] = "English",
        ["trayQuit"] = "Выход",
        ["trayStartTitle"] = "PoE2 Craft Overlay запущен",
        ["trayStartText"] = "Ctrl+Q — захват предмета и следующий шаг крафта.",
    };

    private static readonly Dictionary<string, string> En = new()
    {
        ["clipboardEmpty"] = "the clipboard is empty: hover an item in game and press Ctrl+Q",
        ["captureRefused"] = "the game did not accept the automatic copy. Hover an item, press Ctrl+C, then "
            + "Ctrl+Q - the helper takes over from there.",
        ["marketScriptMissing"] = "The market script was not found next to the program.",
        ["marketQueryFailed"] = "The engine could not build the market query.",
        ["marketNoNode"] = "The price could not be looked up: Node.js has to be in PATH, or set POE2CRAFT_NODE.",
        ["marketUnreadable"] = "The trade site answered with something unreadable.",
        ["marketCooldown"] = "Trade is paused for another {0} s (request limit). Wait, or type the price in yourself.",
        ["marketRefused"] = "The price could not be taken: {0}",
        ["marketNoReason"] = "no reason given",
        ["marketSuggestions"] = " Near matches: {0}.",
        ["marketMedian"] = "Market price: median over {0} listings of {1} found.",
        ["marketMatch"] = " Match: {0}.",
        ["marketCached"] = " The trade answer is cached for {0} s, so asking again about the same item may be free.",
        ["marketQuota"] = " {0} trade requests are left for this hour.",
        ["marketNoMedian"] = "The trade site answered without a median price.",
        ["noEngineAnswer"] = "no answer from analyze_item",
        ["trayShow"] = "Show the panel (Ctrl+Q captures)",
        ["trayCapture"] = "Capture from the clipboard",
        ["trayLanguage"] = "Language",
        ["trayLanguageAuto"] = "Follow the game",
        ["trayLanguageRu"] = "Russian",
        ["trayLanguageEn"] = "English",
        ["trayQuit"] = "Quit",
        ["trayStartTitle"] = "PoE2 Craft Overlay is running",
        ["trayStartText"] = "Ctrl+Q copies the item and shows the next crafting step.",
    };

    /// The trade site's refusals, in Russian.
    //
    // The market helper is a Node script and it says WHY it refused in English ("base not found on the
    // trade site"), which then sat inside a Russian sentence. Those exact phrases are the script's own,
    // so they are translated here by whole sentence; anything the script says that is not in this table
    // is shown as it came - an invented explanation would be worse than an English one.
    private static readonly Dictionary<string, string> ReasonsRu = new(StringComparer.OrdinalIgnoreCase)
    {
        ["trade site is on cooldown"] = "трейд на паузе",
        ["the hourly request budget is spent"] = "часовой лимит запросов исчерпан",
        ["spec is not valid JSON"] = "запрос к рынку собран с ошибкой",
        ["no base name to search"] = "в запросе нет названия базы",
        ["no modifiers to match"] = "в запросе нет модов для поиска",
        ["base not found on the trade site"] = "база не найдена на сайте трейда",
        ["no league available from the trade site"] = "сайт трейда не отдал список лиг",
        ["none of the modifiers resolved to a trade stat"] = "ни один мод не сопоставился со статом трейда",
        ["no listing on this base matches even the loosest filter"] =
            "по этой базе нет ни одного лота даже по самому мягкому фильтру",
        ["listings were found but none could be converted to chaos"] =
            "лоты нашлись, но ни один не удалось перевести в хаос",
    };

    /// A refusal from the market helper in the panel's language.
    public static string MarketReason(string language, string reason)
    {
        if (language != PanelLanguage.Russian || string.IsNullOrEmpty(reason))
        {
            return reason;
        }
        return ReasonsRu.TryGetValue(reason.Trim(), out var translated) ? translated : reason;
    }

    /// One host sentence. Unknown keys come back as the key, which is loud enough to be noticed.
    public static string Get(string language, string key, params object[] args)
    {
        var table = language == PanelLanguage.English ? En : Ru;
        if (!table.TryGetValue(key, out var text) && !Ru.TryGetValue(key, out text))
        {
            return key;
        }
        if (args.Length == 0)
        {
            return text;
        }
        try
        {
            return string.Format(CultureInfo.InvariantCulture, text, args);
        }
        catch (FormatException)
        {
            // A message with the wrong number of holes must not take the panel down.
            return text;
        }
    }
}
