-- ====================================================================

-- Auto Word Chain / Finish The Word Solver with GUI

-- V5.0 Smart Learning + AFK Prevention Edition:

--   - PASSIVE WORD LEARNING:

--       * Hooks 'correct' events to build a per-session learned word bank

--       * Learned words are prioritized highest (confirmed server-accepted)

--       * Rejected words auto-blacklisted so they're never retried

--   - AFK PREVENTION:

--       * Random periodic jump + camera wiggle while idle in lobby/game

--       * Configurable interval, enabled/disabled via GUI toggle

--   - ULTRA-FAST RETRY ON REJECTED WORDS (V4 carry-over)

--   - SMART CACHED BACKSPACE + REAL-TIME SPEED SLIDERS (V3 carry-over)

-- ====================================================================

if _G.WordChainGuiCleanup then

    pcall(_G.WordChainGuiCleanup)

end

local Players = game:GetService("Players")

local CoreGui = game:GetService("CoreGui")

local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer

-- Obtain game internal event module from GC
local event = nil

local gcOk, gcObjects = pcall(function()
    return getgc(true)
end)

if gcOk and type(gcObjects) == "table" then
    for _, v in ipairs(gcObjects) do
        if type(v) == "table" and rawget(v, "remoteConnect") and rawget(v, "remoteFire") then
            event = v
            break
        end
    end
end

if not event then
    if gcOk then
        warn("[WordChain] Event module not found!")
    else
        warn("[WordChain] getgc(true) failed or is unavailable in this executor.")
    end
    return
end

-- Configuration

local Config = {

    AutoAnswer = true,

    TypingDelay = 0.08,     -- Normal keystroke delay (seconds)

    TypingJitter = 0.00,    -- Keystroke jitter variation (+/- seconds)

    AnswerDelay = 0.50,     -- Normal human reaction time before typing

    DeletePace = 0.025,     -- Deletion speed/delay per backspace when word is invalid (seconds)


    AfkPrevention = true,  -- Jump randomly to avoid AFK kick

    AfkInterval = 180,     -- Seconds between AFK prevention actions (120–240)

}

_G.WordChainConfig = Config

-- -----------------------------------------------------------------------
-- WordChainSolver workspace folder + automatic legacy-file migration
-- -----------------------------------------------------------------------
local WORDCHAIN_FOLDER = "WordChainSolver"
local SCRIPT_FILE = "WordChainSolver_FTW_GitHub_rejoin_safe.lua"
local LEGACY_SCRIPT_FILES = {
    "WordChainSolver_FTW_GitHub_rejoin_safe.lua",
    "WordChainSolver_FTW_GitHub_rejoin_safe_already_used_fixed.lua",
    "WordChainSolver_FTW_GitHub_rejoin_safe_already_used_fixed_folder_migration.lua",
    "WordChainSolver_FTW_GitHub_final_blacklist_restored.lua",
    "WordChainSolver_FTW_GitHub_combined_all_dicts_used_guard_fixed.lua",
    "WordChainSolver_FTW_GitHub_combined_all_dicts.lua",
    "WordChainSolver_FTW_GitHub_final.lua",
}

local function ensureFolder(path)
    if type(isfolder) == "function" then
        local ok, exists = pcall(isfolder, path)
        if ok and exists then return true end
    end

    if type(makefolder) == "function" then
        local ok = pcall(makefolder, path)
        if ok then return true end
    end

    return false
end

local function ensureWordChainFolder()
    if ensureFolder(WORDCHAIN_FOLDER) then
        return true
    end

    -- Some executors do not expose isfolder; if makefolder is unavailable we
    -- cannot safely migrate into a subfolder. Keep the legacy-path fallback.
    return type(writefile) == "function" and type(readfile) == "function"
end

local function wordChainPath(name)
    return WORDCHAIN_FOLDER .. "/" .. name
end

local function fileExists(path)
    if type(isfile) ~= "function" then
        return false
    end

    local ok, result = pcall(isfile, path)
    return ok and result == true
end

local function copyThenDelete(oldPath, newPath)
    if type(readfile) ~= "function" or type(writefile) ~= "function" then
        return false
    end

    if fileExists(newPath) then
        return true
    end

    if not fileExists(oldPath) then
        return false
    end

    local okRead, data = pcall(readfile, oldPath)
    if not okRead or type(data) ~= "string" then
        return false
    end

    local okWrite = pcall(writefile, newPath, data)
    if not okWrite then
        return false
    end

    -- Only remove the old copy after the new one was successfully written.
    if type(delfile) == "function" then
        pcall(delfile, oldPath)
    end

    return true
end

local function migrateDataFile(name)
    return copyThenDelete(name, wordChainPath(name))
end

local function migrateScriptToCanonical()
    local target = wordChainPath(SCRIPT_FILE)
    if fileExists(target) then
        return true
    end

    for _, legacyName in ipairs(LEGACY_SCRIPT_FILES) do
        if fileExists(legacyName) then
            if copyThenDelete(legacyName, target) then
                return true
            end
        end
    end

    return false
end

local function archiveLegacyUnusedFile(name)
    local legacyFolder = wordChainPath("Legacy")
    if not ensureFolder(legacyFolder) then
        return false
    end

    local oldPath = name
    local newPath = legacyFolder .. "/" .. name
    return copyThenDelete(oldPath, newPath)
end

local function migrateWordChainFiles()
    if not ensureWordChainFolder() then
        warn("[WordChain] Could not create workspace/" .. WORDCHAIN_FOLDER .. "; using legacy paths.")
        return false
    end

    -- Persistent data: existing files in the folder are always preferred;
    -- root-level files are only moved when the destination does not exist.
    migrateDataFile("WordChainSettings.txt")
    migrateDataFile("WordChainLearned.txt")
    migrateDataFile("WordChainRejected.txt")

    -- Canonical script used by rejoin auto-execute.
    migrateScriptToCanonical()

    -- Old local dictionary/blacklist artifacts are no longer runtime inputs.
    -- Archive them instead of deleting so no user data is lost.
    archiveLegacyUnusedFile("WordChainBlacklist.txt")
    archiveLegacyUnusedFile("WordChainFTW.txt")

    -- Archive older solver copies so the workspace root keeps only the
    -- currently canonical launcher when an executor permits file deletion.
    for _, legacyName in ipairs(LEGACY_SCRIPT_FILES) do
        if legacyName ~= SCRIPT_FILE then
            archiveLegacyUnusedFile(legacyName)
        end
    end

    return true
end

local WordChainStorageReady = migrateWordChainFiles()

-- -----------------------------------------------------------------------

-- Settings Persistence: save/load Config across sessions
-- -----------------------------------------------------------------------
local SETTINGS_FILE = WordChainStorageReady and wordChainPath("WordChainSettings.txt") or "WordChainSettings.txt"

local function saveSettings()
    pcall(function()
        if not writefile then return end

        local lines = {
            "AutoAnswer=" .. tostring(Config.AutoAnswer),
            "TypingDelay=" .. tostring(Config.TypingDelay),
            "TypingJitter=" .. tostring(Config.TypingJitter),
            "AnswerDelay=" .. tostring(Config.AnswerDelay),
            "DeletePace=" .. tostring(Config.DeletePace),
            "AfkPrevention=" .. tostring(Config.AfkPrevention),
            "AfkInterval=" .. tostring(Config.AfkInterval),
        }

        writefile(SETTINGS_FILE, table.concat(lines, "\n"))
    end)
end

pcall(function()
    if not (readfile and isfile) then return end
    if not isfile(SETTINGS_FILE) then return end

    local data = readfile(SETTINGS_FILE)

    for key, val in data:gmatch("([%w]+)=([^\n]+)") do
        if key == "AutoAnswer" then
            Config.AutoAnswer = (val == "true")
        elseif key == "TypingDelay" then
            local n = tonumber(val)
            if n then Config.TypingDelay = n end
        elseif key == "TypingJitter" then
            local n = tonumber(val)
            if n then Config.TypingJitter = n end
        elseif key == "AnswerDelay" then
            local n = tonumber(val)
            if n then Config.AnswerDelay = n end
        elseif key == "DeletePace" then
            local n = tonumber(val)
            if n then Config.DeletePace = n end
        elseif key == "AfkPrevention" then
            Config.AfkPrevention = (val == "true")
        elseif key == "AfkInterval" then
            local n = tonumber(val)
            if n then Config.AfkInterval = n end
        end
    end
end)

-- Validate loaded values before the UI/runtime consumes them.
Config.TypingDelay = math.clamp(tonumber(Config.TypingDelay) or 0.08, 0.01, 0.50)
Config.TypingJitter = math.clamp(tonumber(Config.TypingJitter) or 0.00, 0.00, 0.50)
Config.AnswerDelay = math.clamp(tonumber(Config.AnswerDelay) or 0.50, 0.05, 3.00)
Config.DeletePace = math.clamp(tonumber(Config.DeletePace) or 0.025, 0.005, 0.200)
Config.AfkInterval = math.clamp(tonumber(Config.AfkInterval) or 180, 30, 600)

local SettingsSaveThread = nil

local function requestSaveSettings()
    if SettingsSaveThread then
        pcall(task.cancel, SettingsSaveThread)
        SettingsSaveThread = nil
    end

    SettingsSaveThread = task.delay(0.35, function()
        SettingsSaveThread = nil
        saveSettings()
    end)
end

-- Dictionaries

local FullDictionary = {}

local ValidDictionarySet = {}

local CommonWords = {}

local WordsByPrefix = {}

local CommonWordsByPrefix = {}

local UsedWordsInMatch = {}
local BlacklistedWords = {} -- Match-scoped strike/ban blacklist; reset at endGame
local PendingWordsInMatch = {} -- Words currently being submitted; prevents delayed correct-event reuse
local PersistentRejectedWords = {} -- Explicit server-invalid words; persisted across matches
_G.WordChainBlacklisted = BlacklistedWords
_G.WordChainRejected = PersistentRejectedWords
local LearnedWords = {}        -- Server-confirmed evidence with metadata
local LearnedWordsByPrefix = {}-- Same, indexed by prefix for fast lookup
local DictionaryLoaded = false
local DictionaryReady = false
local FullDictionaryLoadSucceeded = false
local CommonSourcesCompleted = 0
local CommonSourcesSucceeded = 0
local ExtendedDictionary = {}
local ExtendedDictionarySet = {}
local ExtendedWordsByPrefix = {}
local ExtendedDictionaryLoadSucceeded = false
local FTWDictionarySet = {}
local FTWWordsByPrefix = {}
local FTWDictionaryLoadSucceeded = false
local FTWUniqueDictionaryCount = 0
local DictionaryContext = nil

-- Effective dictionary count = union of the canonical dictionary, Extended, and FTW.
-- FullDictionary and ExtendedDictionary are already disjoint by construction; FTW
-- is counted only when a word exists in neither source.
local function getCombinedDictionaryCount()
    return #FullDictionary + #ExtendedDictionary + FTWUniqueDictionaryCount
end

local function recountFTWUniqueDictionary()
    FTWUniqueDictionaryCount = 0
    for word in pairs(FTWDictionarySet) do
        if not ValidDictionarySet[word] and not ExtendedDictionarySet[word] then
            FTWUniqueDictionaryCount = FTWUniqueDictionaryCount + 1
        end
    end
end

-- Persistent Learning: save/load learned words across sessions

-- File is written to the executor's workspace folder (e.g. Synapse/KRNL)

-- -----------------------------------------------------------------------

local REJECTED_FILE = WordChainStorageReady and wordChainPath("WordChainRejected.txt") or "WordChainRejected.txt"

local function saveRejectedWords()
    pcall(function()
        if not writefile then return end

        local lines = {}
        for word in pairs(PersistentRejectedWords) do
            table.insert(lines, word)
        end

        table.sort(lines)
        writefile(REJECTED_FILE, table.concat(lines, "\n"))
    end)
end

local loadedRejectedFromFile = 0

pcall(function()
    if not (readfile and isfile) then return end
    if not isfile(REJECTED_FILE) then return end

    local data = readfile(REJECTED_FILE)
    for word in data:gmatch("[A-Za-z]+") do
        word = string.upper(word)
        if #word >= 3 and not PersistentRejectedWords[word] then
            PersistentRejectedWords[word] = true
            loadedRejectedFromFile = loadedRejectedFromFile + 1
        end
    end
end)

local LEARNED_FILE = WordChainStorageReady and wordChainPath("WordChainLearned.txt") or "WordChainLearned.txt"

local LearnedNewSinceLastSave = 0  -- debounce: save every 5 newly introduced words

local function indexLearnedWord(word)
    for len = 1, math.min(6, #word) do
        local p = string.sub(word, 1, len)

        if not LearnedWordsByPrefix[p] then
            LearnedWordsByPrefix[p] = {}
        end

        local exists = false
        for _, existing in ipairs(LearnedWordsByPrefix[p]) do
            if existing == word then
                exists = true
                break
            end
        end

        if not exists then
            table.insert(LearnedWordsByPrefix[p], word)
        end
    end
end

local function saveLearnedWords()
    pcall(function()
        if not writefile then return end

        local lines = {}
        for w, meta in pairs(LearnedWords) do
            meta = meta or {}
            local count = math.max(1, tonumber(meta.ConfirmedCount) or 1)
            local lastConfirmed = math.max(0, math.floor(tonumber(meta.LastConfirmedAt) or 0))
            local context = tostring(meta.DictionaryContext or "")
            context = context:gsub("[\r\n\t]", "")

            table.insert(lines, string.format("%s\t%d\t%d\t%s", w, count, lastConfirmed, context))
        end

        table.sort(lines)
        writefile(LEARNED_FILE, table.concat(lines, "\n"))
    end)
end

-- Load current metadata format and legacy plain-word files.
local loadedFromFile = 0

pcall(function()
    if not (readfile and isfile) then return end
    if not isfile(LEARNED_FILE) then return end

    local data = readfile(LEARNED_FILE)

    for line in data:gmatch("[^\r\n]+") do
        local word, count, lastConfirmed, context = line:match("^([A-Za-z]+)\t(%d+)\t(%d+)\t(.*)$")

        if not word then
            word = line:match("^([A-Za-z]+)$")
            count = 1
            lastConfirmed = 0
            context = "LEGACY"
        end

        if word then
            word = string.upper(word)

            if #word >= 3 and not LearnedWords[word] then
                LearnedWords[word] = {
                    ConfirmedCount = math.max(1, tonumber(count) or 1),
                    LastConfirmedAt = math.max(0, tonumber(lastConfirmed) or 0),
                    DictionaryContext = tostring(context or ""),
                }

                indexLearnedWord(word)
                loadedFromFile = loadedFromFile + 1
            end
        end
    end
end)

-- Remote FTW dictionary source.
-- Loaded directly from GitHub so no extra local dictionary file is required.
local FTW_DICTIONARY_URL = "https://raw.githubusercontent.com/jakky-bot/server/refs/heads/main/ftw-words.txt"

pcall(function()
    local ok, data = pcall(function()
        return game:HttpGet(FTW_DICTIONARY_URL)
    end)

    if not ok or not data then return end

    for word in data:gmatch("[A-Za-z]+") do
        word = string.upper(word)

        if #word >= 3 and #word <= 15 and not FTWDictionarySet[word] then
            FTWDictionarySet[word] = true

            local p = string.sub(word, 1, math.min(3, #word))
            if not FTWWordsByPrefix[p] then
                FTWWordsByPrefix[p] = {}
            end

            table.insert(FTWWordsByPrefix[p], word)
        end
    end

    FTWDictionaryLoadSucceeded = next(FTWDictionarySet) ~= nil
end)

-- Ingest dictionaries

task.spawn(function()
    local s1, rawFull = pcall(function()
        return game:HttpGet("https://raw.githubusercontent.com/redbo/scrabble/master/dictionary.txt")
    end)

    if s1 and rawFull then
        for word in string.gmatch(rawFull, "[%a]+") do
            word = string.upper(word)

            if #word >= 3 and #word <= 15 then
                ValidDictionarySet[word] = true
                table.insert(FullDictionary, word)

                for len = 1, math.min(6, #word) do
                    local p = string.sub(word, 1, len)
                    if not WordsByPrefix[p] then WordsByPrefix[p] = {} end
                    table.insert(WordsByPrefix[p], word)
                end
            end
        end

        FullDictionaryLoadSucceeded = #FullDictionary > 0
    end

    local hash = 2166136261
    local modulo = 4294967296

    if FullDictionaryLoadSucceeded then
        for _, word in ipairs(FullDictionary) do
            for i = 1, #word do
                hash = (hash * 16777619 + string.byte(word, i)) % modulo
            end
            hash = (hash + 31) % modulo
        end

        -- Count FTW words provisionally. Extended is still loading asynchronously;
        -- it will be re-counted against ExtendedDictionary when that source finishes.
        recountFTWUniqueDictionary()

        DictionaryContext = string.format("scrabble-v1:%08X:%d", hash, #FullDictionary)

        for _, meta in pairs(LearnedWords) do
            if meta and meta.DictionaryContext == "PENDING" then
                meta.DictionaryContext = DictionaryContext
            end
        end
    end

    local function ingestCommon(url)
        local ok, data = pcall(function()
            return game:HttpGet(url)
        end)

        if not ok or not data then
            return false
        end

        local parsed = true

        for word in string.gmatch(data, "[%a]+") do
            word = string.upper(word)

            if ValidDictionarySet[word] and #word >= 3 and not CommonWords[word] then
                CommonWords[word] = true
                parsed = true

                for len = 1, math.min(6, #word) do
                    local p = string.sub(word, 1, len)
                    if not CommonWordsByPrefix[p] then CommonWordsByPrefix[p] = {} end
                    table.insert(CommonWordsByPrefix[p], word)
                end
            end
        end

        return parsed
    end

    -- Optional broad English-word enrichment. Kept separate from the canonical
    -- Scrabble dictionary so learned-word context remains stable.
    task.spawn(function()
        local ok, data = pcall(function()
            return game:HttpGet("https://raw.githubusercontent.com/dwyl/english-words/master/words_alpha.txt")
        end)

        if not ok or not data then
            return
        end

        for word in string.gmatch(data, "[%a]+") do
            word = string.upper(word)

            if #word >= 3 and #word <= 15
                and not ValidDictionarySet[word]
                and not ExtendedDictionarySet[word]
            then
                ExtendedDictionarySet[word] = true
                table.insert(ExtendedDictionary, word)

                -- Index 1-3 chars only to limit memory overhead. Longer prefixes
                -- are filtered from their 3-character bucket during selection.
                for len = 1, math.min(3, #word) do
                    local p = string.sub(word, 1, len)
                    if not ExtendedWordsByPrefix[p] then
                        ExtendedWordsByPrefix[p] = {}
                    end
                    table.insert(ExtendedWordsByPrefix[p], word)
                end
            end
        end

        ExtendedDictionaryLoadSucceeded = #ExtendedDictionary > 0

        -- Finalize the effective dictionary count now that Extended is available.
        recountFTWUniqueDictionary()

        if _G.WordChainStatusLabel and DictionaryReady then
            local learnedCount = 0
            for _ in pairs(LearnedWords) do learnedCount = learnedCount + 1 end
            local rejectedCount = 0
            for _ in pairs(PersistentRejectedWords) do rejectedCount = rejectedCount + 1 end

            _G.WordChainStatusLabel.Text = string.format(
                "Dict ready: %d Total | 🧠 %d Learned | ✖ %d Rejected",
                getCombinedDictionaryCount(),
                learnedCount,
                rejectedCount
            )
        end
    end)

    local commonSources = {
        "https://raw.githubusercontent.com/first20hours/google-10000-english/master/20k.txt",
        "https://raw.githubusercontent.com/tabatkins/wordle-list/main/words",
        "https://raw.githubusercontent.com/hugsy/stuff/master/random-word/english-nouns.txt",
    }

    local commonPending = #commonSources

    local function finishDictionaryLoading()
        if commonPending ~= 0 then return end

        DictionaryReady = FullDictionaryLoadSucceeded
        DictionaryLoaded = DictionaryReady

        local commonCount = 0
        for _ in pairs(CommonWords) do
            commonCount = commonCount + 1
        end

        if _G.WordChainStatusLabel then
            local learnedCount = 0
            for _ in pairs(LearnedWords) do
                learnedCount = learnedCount + 1
            end

            if DictionaryReady then
                _G.WordChainStatusLabel.Text = string.format(
                    "Dict ready: %d Common | %d Total | 🧠 %d Learned | Common sources %d/%d",
                    commonCount,
                    getCombinedDictionaryCount(),
                    learnedCount,
                    CommonSourcesSucceeded,
                    #commonSources
                )
                _G.WordChainStatusLabel.TextColor3 = Color3.fromRGB(80, 220, 100)
            else
                _G.WordChainStatusLabel.Text = "Dictionary unavailable — Auto Answer paused"
                _G.WordChainStatusLabel.TextColor3 = Color3.fromRGB(255, 180, 80)
            end
        end
    end

    for _, url in ipairs(commonSources) do
        task.spawn(function()
            local success, result = pcall(ingestCommon, url)
            if success and result == true then
                CommonSourcesSucceeded = CommonSourcesSucceeded + 1
            end

            CommonSourcesCompleted = CommonSourcesCompleted + 1
            commonPending = commonPending - 1
            finishDictionaryLoading()
        end)
    end
end)

-- UI Setup

local ScreenGui = Instance.new("ScreenGui")

ScreenGui.Name = "WordChainAssistantGUI"

ScreenGui.ResetOnSpawn = false

local targetParent = LocalPlayer:FindFirstChild("PlayerGui") or CoreGui

ScreenGui.Parent = targetParent

local MainFrame = Instance.new("Frame")

MainFrame.Name = "MainFrame"

MainFrame.Size = UDim2.new(0, 320, 0, 515)

MainFrame.Position = UDim2.new(0.04, 0, 0.18, 0)

MainFrame.BackgroundColor3 = Color3.fromRGB(18, 20, 26)

MainFrame.BorderSizePixel = 0

MainFrame.ClipsDescendants = true

MainFrame.Parent = ScreenGui

local UICorner = Instance.new("UICorner")

UICorner.CornerRadius = UDim.new(0, 12)

UICorner.Parent = MainFrame

local UIStroke = Instance.new("UIStroke")

UIStroke.Color = Color3.fromRGB(55, 62, 85)

UIStroke.Thickness = 1.5

UIStroke.Parent = MainFrame

-- Draggable Title Bar

local TitleBar = Instance.new("Frame")

TitleBar.Name = "TitleBar"

TitleBar.Size = UDim2.new(1, 0, 0, 38)

TitleBar.BackgroundColor3 = Color3.fromRGB(26, 29, 38)

TitleBar.BorderSizePixel = 0

TitleBar.Parent = MainFrame

local TitleCorner = Instance.new("UICorner")

TitleCorner.CornerRadius = UDim.new(0, 12)

TitleCorner.Parent = TitleBar

local TitleLabel = Instance.new("TextLabel")

TitleLabel.Name = "TitleLabel"

TitleLabel.Text = "  ⚡ Word Chain Solver"

TitleLabel.Font = Enum.Font.GothamBold

TitleLabel.TextSize = 14

TitleLabel.TextColor3 = Color3.fromRGB(240, 240, 255)

TitleLabel.TextXAlignment = Enum.TextXAlignment.Left

TitleLabel.Size = UDim2.new(1, -70, 1, 0)

TitleLabel.BackgroundTransparency = 1

TitleLabel.Parent = TitleBar

local CloseBtn = Instance.new("TextButton")

CloseBtn.Text = "✕"

CloseBtn.Font = Enum.Font.GothamBold

CloseBtn.TextSize = 14

CloseBtn.TextColor3 = Color3.fromRGB(180, 180, 190)

CloseBtn.BackgroundTransparency = 1

CloseBtn.Size = UDim2.new(0, 30, 0, 30)

CloseBtn.Position = UDim2.new(1, -34, 0, 4)

CloseBtn.Parent = TitleBar

-- Dragging Logic

local dragging, dragInput, dragStart, startPos

TitleBar.InputBegan:Connect(function(input)

    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then

        dragging = true

        dragStart = input.Position

        startPos = MainFrame.Position

        input.Changed:Connect(function()

            if input.UserInputState == Enum.UserInputState.End then

                dragging = false

            end

        end)

    end

end)

TitleBar.InputChanged:Connect(function(input)

    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then

        dragInput = input

    end

end)

UserInputService.InputChanged:Connect(function(input)

    if input == dragInput and dragging then

        local delta = input.Position - dragStart

        MainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)

    end

end)

-- Content Container

local Content = Instance.new("Frame")

Content.Size = UDim2.new(1, -20, 1, -48)

Content.Position = UDim2.new(0, 10, 0, 44)

Content.BackgroundTransparency = 1

Content.Parent = MainFrame

local ContentList = Instance.new("UIListLayout")

ContentList.SortOrder = Enum.SortOrder.LayoutOrder

ContentList.Padding = UDim.new(0, 6)

ContentList.Parent = Content

-- Status Label

local StatusLabel = Instance.new("TextLabel")

StatusLabel.Name = "StatusLabel"

StatusLabel.LayoutOrder = 1

StatusLabel.Size = UDim2.new(1, 0, 0, 18)

StatusLabel.Font = Enum.Font.GothamMedium

StatusLabel.TextSize = 11

StatusLabel.TextColor3 = Color3.fromRGB(80, 220, 100)

StatusLabel.Text = "Loading verified dictionary..."

StatusLabel.BackgroundTransparency = 1

StatusLabel.TextXAlignment = Enum.TextXAlignment.Left

StatusLabel.Parent = Content

_G.WordChainStatusLabel = StatusLabel

if DictionaryReady then
    local learnedCount = 0
    for _ in pairs(LearnedWords) do
        learnedCount = learnedCount + 1
    end

    local commonCount = 0
    for _ in pairs(CommonWords) do
        commonCount = commonCount + 1
    end

    local savedTag = loadedFromFile > 0 and string.format(" (+%d saved)", loadedFromFile) or ""
    StatusLabel.Text = string.format(
        "Dict: %d Common | %d Total | 🧠 %d Learned%s",
        commonCount,
        getCombinedDictionaryCount(),
        learnedCount,
        savedTag
    )
    StatusLabel.TextColor3 = Color3.fromRGB(80, 220, 100)
end

-- Info Card

local InfoCard = Instance.new("Frame")

InfoCard.LayoutOrder = 2

InfoCard.Size = UDim2.new(1, 0, 0, 64)

InfoCard.BackgroundColor3 = Color3.fromRGB(26, 30, 40)

InfoCard.Parent = Content

local InfoCorner = Instance.new("UICorner")

InfoCorner.CornerRadius = UDim.new(0, 8)

InfoCorner.Parent = InfoCard

local PromptDisplay = Instance.new("TextLabel")

PromptDisplay.Size = UDim2.new(1, -12, 0, 22)

PromptDisplay.Position = UDim2.new(0, 8, 0, 5)

PromptDisplay.Font = Enum.Font.GothamMedium

PromptDisplay.TextSize = 12

PromptDisplay.TextColor3 = Color3.fromRGB(160, 170, 190)

PromptDisplay.Text = "Prefix: Waiting for turn..."

PromptDisplay.TextXAlignment = Enum.TextXAlignment.Left

PromptDisplay.BackgroundTransparency = 1

PromptDisplay.Parent = InfoCard

local TargetWordDisplay = Instance.new("TextLabel")

TargetWordDisplay.Size = UDim2.new(1, -12, 0, 28)

TargetWordDisplay.Position = UDim2.new(0, 8, 0, 29)

TargetWordDisplay.Font = Enum.Font.GothamBold

TargetWordDisplay.TextSize = 17

TargetWordDisplay.TextColor3 = Color3.fromRGB(100, 220, 255)

TargetWordDisplay.Text = "WORD: -"

TargetWordDisplay.TextXAlignment = Enum.TextXAlignment.Left

TargetWordDisplay.BackgroundTransparency = 1

TargetWordDisplay.Parent = InfoCard

-- Auto Answer Toggle

local ToggleFrame = Instance.new("Frame")

ToggleFrame.LayoutOrder = 3

ToggleFrame.Size = UDim2.new(1, 0, 0, 32)

ToggleFrame.BackgroundColor3 = Color3.fromRGB(26, 30, 40)

ToggleFrame.Parent = Content

local ToggleCorner = Instance.new("UICorner")

ToggleCorner.CornerRadius = UDim.new(0, 8)

ToggleCorner.Parent = ToggleFrame

local ToggleLabel = Instance.new("TextLabel")

ToggleLabel.Text = "Auto Answer"

ToggleLabel.Font = Enum.Font.GothamSemibold

ToggleLabel.TextSize = 12

ToggleLabel.TextColor3 = Color3.fromRGB(230, 230, 240)

ToggleLabel.TextXAlignment = Enum.TextXAlignment.Left

ToggleLabel.Size = UDim2.new(0.65, 0, 1, 0)

ToggleLabel.Position = UDim2.new(0, 10, 0, 0)

ToggleLabel.BackgroundTransparency = 1

ToggleLabel.Parent = ToggleFrame

local ToggleBtn = Instance.new("TextButton")

ToggleBtn.Size = UDim2.new(0, 50, 0, 22)

ToggleBtn.Position = UDim2.new(1, -60, 0.5, -11)

ToggleBtn.BackgroundColor3 = Config.AutoAnswer and Color3.fromRGB(45, 180, 110) or Color3.fromRGB(150, 50, 50)

ToggleBtn.Text = Config.AutoAnswer and "ON" or "OFF"

ToggleBtn.Font = Enum.Font.GothamBold

ToggleBtn.TextSize = 11

ToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)

ToggleBtn.Parent = ToggleFrame

local ToggleBtnCorner = Instance.new("UICorner")

ToggleBtnCorner.CornerRadius = UDim.new(0, 11)

ToggleBtnCorner.Parent = ToggleBtn

ToggleBtn.MouseButton1Click:Connect(function()

    Config.AutoAnswer = not Config.AutoAnswer

    if Config.AutoAnswer then

        ToggleBtn.BackgroundColor3 = Color3.fromRGB(45, 180, 110)

        ToggleBtn.Text = "ON"

    else

        ToggleBtn.BackgroundColor3 = Color3.fromRGB(150, 50, 50)

        ToggleBtn.Text = "OFF"

    end

    requestSaveSettings()

end)

-- SPEED & DELAY CONTROLS


local SpeedControlFrame = Instance.new("Frame")

SpeedControlFrame.LayoutOrder = 5

SpeedControlFrame.Size = UDim2.new(1, 0, 0, 82)

SpeedControlFrame.BackgroundColor3 = Color3.fromRGB(26, 30, 40)

SpeedControlFrame.Parent = Content

local SpeedCorner = Instance.new("UICorner")

SpeedCorner.CornerRadius = UDim.new(0, 8)

SpeedCorner.Parent = SpeedControlFrame

-- Row 1: Typing Speed

local TypeDelayLabel = Instance.new("TextLabel")

TypeDelayLabel.Text = string.format("Typing Speed: %d ms/key", math.floor(Config.TypingDelay * 1000 + 0.5))

TypeDelayLabel.Font = Enum.Font.GothamMedium

TypeDelayLabel.TextSize = 11

TypeDelayLabel.TextColor3 = Color3.fromRGB(210, 215, 230)

TypeDelayLabel.TextXAlignment = Enum.TextXAlignment.Left

TypeDelayLabel.Size = UDim2.new(0.65, 0, 0, 24)

TypeDelayLabel.Position = UDim2.new(0, 10, 0, 2)

TypeDelayLabel.BackgroundTransparency = 1

TypeDelayLabel.Parent = SpeedControlFrame

local MinusTypeBtn = Instance.new("TextButton")

MinusTypeBtn.Size = UDim2.new(0, 22, 0, 18)

MinusTypeBtn.Position = UDim2.new(1, -56, 0, 5)

MinusTypeBtn.BackgroundColor3 = Color3.fromRGB(45, 52, 70)

MinusTypeBtn.Text = "-"

MinusTypeBtn.Font = Enum.Font.GothamBold

MinusTypeBtn.TextSize = 13

MinusTypeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)

MinusTypeBtn.Parent = SpeedControlFrame

local MinusTypeCorner = Instance.new("UICorner")

MinusTypeCorner.CornerRadius = UDim.new(0, 4)

MinusTypeCorner.Parent = MinusTypeBtn

local PlusTypeBtn = Instance.new("TextButton")

PlusTypeBtn.Size = UDim2.new(0, 22, 0, 18)

PlusTypeBtn.Position = UDim2.new(1, -28, 0, 5)

PlusTypeBtn.BackgroundColor3 = Color3.fromRGB(45, 52, 70)

PlusTypeBtn.Text = "+"

PlusTypeBtn.Font = Enum.Font.GothamBold

PlusTypeBtn.TextSize = 13

PlusTypeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)

PlusTypeBtn.Parent = SpeedControlFrame

local PlusTypeCorner = Instance.new("UICorner")

PlusTypeCorner.CornerRadius = UDim.new(0, 4)

PlusTypeCorner.Parent = PlusTypeBtn

MinusTypeBtn.MouseButton1Click:Connect(function()

    Config.TypingDelay = math.clamp(math.floor((Config.TypingDelay - 0.01) * 1000 + 0.5) / 1000, 0.01, 0.50)

    TypeDelayLabel.Text = string.format("Typing Speed: %d ms/key", math.floor(Config.TypingDelay * 1000 + 0.5))

    requestSaveSettings()

end)

PlusTypeBtn.MouseButton1Click:Connect(function()

    Config.TypingDelay = math.clamp(math.floor((Config.TypingDelay + 0.01) * 1000 + 0.5) / 1000, 0.01, 0.50)

    TypeDelayLabel.Text = string.format("Typing Speed: %d ms/key", math.floor(Config.TypingDelay * 1000 + 0.5))

    requestSaveSettings()

end)

-- Row 2: Reaction Delay

local ReactDelayLabel = Instance.new("TextLabel")

ReactDelayLabel.Text = string.format("Reaction Delay: %.2fs", Config.AnswerDelay)

ReactDelayLabel.Font = Enum.Font.GothamMedium

ReactDelayLabel.TextSize = 11

ReactDelayLabel.TextColor3 = Color3.fromRGB(210, 215, 230)

ReactDelayLabel.TextXAlignment = Enum.TextXAlignment.Left

ReactDelayLabel.Size = UDim2.new(0.65, 0, 0, 24)

ReactDelayLabel.Position = UDim2.new(0, 10, 0, 28)

ReactDelayLabel.BackgroundTransparency = 1

ReactDelayLabel.Parent = SpeedControlFrame

local MinusReactBtn = Instance.new("TextButton")

MinusReactBtn.Size = UDim2.new(0, 22, 0, 18)

MinusReactBtn.Position = UDim2.new(1, -56, 0, 31)

MinusReactBtn.BackgroundColor3 = Color3.fromRGB(45, 52, 70)

MinusReactBtn.Text = "-"

MinusReactBtn.Font = Enum.Font.GothamBold

MinusReactBtn.TextSize = 13

MinusReactBtn.TextColor3 = Color3.fromRGB(255, 255, 255)

MinusReactBtn.Parent = SpeedControlFrame

local MinusReactCorner = Instance.new("UICorner")

MinusReactCorner.CornerRadius = UDim.new(0, 4)

MinusReactCorner.Parent = MinusReactBtn

local PlusReactBtn = Instance.new("TextButton")

PlusReactBtn.Size = UDim2.new(0, 22, 0, 18)

PlusReactBtn.Position = UDim2.new(1, -28, 0, 31)

PlusReactBtn.BackgroundColor3 = Color3.fromRGB(45, 52, 70)

PlusReactBtn.Text = "+"

PlusReactBtn.Font = Enum.Font.GothamBold

PlusReactBtn.TextSize = 13

PlusReactBtn.TextColor3 = Color3.fromRGB(255, 255, 255)

PlusReactBtn.Parent = SpeedControlFrame

local PlusReactCorner = Instance.new("UICorner")

PlusReactCorner.CornerRadius = UDim.new(0, 4)

PlusReactCorner.Parent = PlusReactBtn

MinusReactBtn.MouseButton1Click:Connect(function()

    Config.AnswerDelay = math.clamp(math.floor((Config.AnswerDelay - 0.05) * 100 + 0.5) / 100, 0.05, 3.0)

    ReactDelayLabel.Text = string.format("Reaction Delay: %.2fs", Config.AnswerDelay)

    requestSaveSettings()

end)

PlusReactBtn.MouseButton1Click:Connect(function()

    Config.AnswerDelay = math.clamp(math.floor((Config.AnswerDelay + 0.05) * 100 + 0.5) / 100, 0.05, 3.0)

    ReactDelayLabel.Text = string.format("Reaction Delay: %.2fs", Config.AnswerDelay)

    requestSaveSettings()

end)

-- Row 3: Delete Speed (Invalid Word Backspace Pace)

local DeleteDelayLabel = Instance.new("TextLabel")

DeleteDelayLabel.Text = string.format("Delete Speed: %d ms/key", math.floor(Config.DeletePace * 1000 + 0.5))

DeleteDelayLabel.Font = Enum.Font.GothamMedium

DeleteDelayLabel.TextSize = 11

DeleteDelayLabel.TextColor3 = Color3.fromRGB(210, 215, 230)

DeleteDelayLabel.TextXAlignment = Enum.TextXAlignment.Left

DeleteDelayLabel.Size = UDim2.new(0.65, 0, 0, 24)

DeleteDelayLabel.Position = UDim2.new(0, 10, 0, 54)

DeleteDelayLabel.BackgroundTransparency = 1

DeleteDelayLabel.Parent = SpeedControlFrame

local MinusDeleteBtn = Instance.new("TextButton")

MinusDeleteBtn.Size = UDim2.new(0, 22, 0, 18)

MinusDeleteBtn.Position = UDim2.new(1, -56, 0, 57)

MinusDeleteBtn.BackgroundColor3 = Color3.fromRGB(45, 52, 70)

MinusDeleteBtn.Text = "-"

MinusDeleteBtn.Font = Enum.Font.GothamBold

MinusDeleteBtn.TextSize = 13

MinusDeleteBtn.TextColor3 = Color3.fromRGB(255, 255, 255)

MinusDeleteBtn.Parent = SpeedControlFrame

local MinusDeleteCorner = Instance.new("UICorner")

MinusDeleteCorner.CornerRadius = UDim.new(0, 4)

MinusDeleteCorner.Parent = MinusDeleteBtn

local PlusDeleteBtn = Instance.new("TextButton")

PlusDeleteBtn.Size = UDim2.new(0, 22, 0, 18)

PlusDeleteBtn.Position = UDim2.new(1, -28, 0, 57)

PlusDeleteBtn.BackgroundColor3 = Color3.fromRGB(45, 52, 70)

PlusDeleteBtn.Text = "+"

PlusDeleteBtn.Font = Enum.Font.GothamBold

PlusDeleteBtn.TextSize = 13

PlusDeleteBtn.TextColor3 = Color3.fromRGB(255, 255, 255)

PlusDeleteBtn.Parent = SpeedControlFrame

local PlusDeleteCorner = Instance.new("UICorner")

PlusDeleteCorner.CornerRadius = UDim.new(0, 4)

PlusDeleteCorner.Parent = PlusDeleteBtn

MinusDeleteBtn.MouseButton1Click:Connect(function()

    Config.DeletePace = math.clamp(math.floor((Config.DeletePace - 0.005) * 1000 + 0.5) / 1000, 0.005, 0.200)

    DeleteDelayLabel.Text = string.format("Delete Speed: %d ms/key", math.floor(Config.DeletePace * 1000 + 0.5))

    requestSaveSettings()

end)

PlusDeleteBtn.MouseButton1Click:Connect(function()

    Config.DeletePace = math.clamp(math.floor((Config.DeletePace + 0.005) * 1000 + 0.5) / 1000, 0.005, 0.200)

    DeleteDelayLabel.Text = string.format("Delete Speed: %d ms/key", math.floor(Config.DeletePace * 1000 + 0.5))

    requestSaveSettings()

end)

-- AFK Prevention Row
-- Manual Submit / New Word / Ban controls are intentionally omitted because
-- Auto Answer handles the normal selection, typing, retry, and submission flow.

local AfkRow = Instance.new("Frame")

AfkRow.LayoutOrder = 6

AfkRow.Size = UDim2.new(1, 0, 0, 26)

AfkRow.BackgroundTransparency = 1

AfkRow.Parent = Content

local AfkToggleBtn = Instance.new("TextButton")

AfkToggleBtn.Size = UDim2.new(0.52, -2, 1, 0)

AfkToggleBtn.Position = UDim2.new(0, 0, 0, 0)

AfkToggleBtn.BackgroundColor3 = Config.AfkPrevention and Color3.fromRGB(30, 120, 60) or Color3.fromRGB(80, 40, 40)

AfkToggleBtn.Text = Config.AfkPrevention and "🛡 AFK: ON" or "💤 AFK: OFF"

AfkToggleBtn.Font = Enum.Font.GothamBold

AfkToggleBtn.TextSize = 11

AfkToggleBtn.TextColor3 = Config.AfkPrevention and Color3.fromRGB(200, 255, 210) or Color3.fromRGB(200, 160, 160)

AfkToggleBtn.Parent = AfkRow

local AfkToggleCorner = Instance.new("UICorner")

AfkToggleCorner.CornerRadius = UDim.new(0, 8)

AfkToggleCorner.Parent = AfkToggleBtn

local AfkInfoLabel = Instance.new("TextLabel")

AfkInfoLabel.Size = UDim2.new(0.48, -2, 1, 0)

AfkInfoLabel.Position = UDim2.new(0.52, 2, 0, 0)

AfkInfoLabel.BackgroundTransparency = 1

AfkInfoLabel.Text = string.format("Every ~%ds", Config.AfkInterval)

AfkInfoLabel.Font = Enum.Font.Gotham

AfkInfoLabel.TextSize = 10

AfkInfoLabel.TextColor3 = Color3.fromRGB(130, 150, 170)

AfkInfoLabel.TextXAlignment = Enum.TextXAlignment.Left

AfkInfoLabel.Parent = AfkRow

AfkToggleBtn.MouseButton1Click:Connect(function()

    Config.AfkPrevention = not Config.AfkPrevention

    if Config.AfkPrevention then

        AfkToggleBtn.Text = "🛡 AFK: ON"

        AfkToggleBtn.BackgroundColor3 = Color3.fromRGB(30, 120, 60)

        AfkToggleBtn.TextColor3 = Color3.fromRGB(200, 255, 210)

    else

        AfkToggleBtn.Text = "💤 AFK: OFF"

        AfkToggleBtn.BackgroundColor3 = Color3.fromRGB(80, 40, 40)

        AfkToggleBtn.TextColor3 = Color3.fromRGB(200, 160, 160)

    end

    requestSaveSettings()

end)

-- Suggested Words List Frame

local SuggestionLabel = Instance.new("TextLabel")

SuggestionLabel.LayoutOrder = 7

SuggestionLabel.Size = UDim2.new(1, 0, 0, 16)

SuggestionLabel.Text = "Alternative Suggestions:"

SuggestionLabel.Font = Enum.Font.GothamMedium

SuggestionLabel.TextSize = 11

SuggestionLabel.TextColor3 = Color3.fromRGB(150, 160, 180)

SuggestionLabel.TextXAlignment = Enum.TextXAlignment.Left

SuggestionLabel.BackgroundTransparency = 1

SuggestionLabel.Parent = Content

local SuggestionsScroll = Instance.new("ScrollingFrame")

SuggestionsScroll.LayoutOrder = 8

SuggestionsScroll.Size = UDim2.new(1, 0, 0, 85)

SuggestionsScroll.BackgroundColor3 = Color3.fromRGB(14, 16, 20)

SuggestionsScroll.BorderSizePixel = 0

SuggestionsScroll.CanvasSize = UDim2.new(0, 0, 0, 0)

SuggestionsScroll.ScrollBarThickness = 4

SuggestionsScroll.Parent = Content

local SuggestionsCorner = Instance.new("UICorner")

SuggestionsCorner.CornerRadius = UDim.new(0, 8)

SuggestionsCorner.Parent = SuggestionsScroll

local SuggestionsList = Instance.new("UIGridLayout")

SuggestionsList.CellSize = UDim2.new(0.47, 0, 0, 23)

SuggestionsList.CellPadding = UDim2.new(0.04, 0, 0, 4)

SuggestionsList.Parent = SuggestionsScroll
SuggestionsList:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    SuggestionsScroll.CanvasSize = UDim2.new(0, 0, 0, SuggestionsList.AbsoluteContentSize.Y + 8)
end)

-- Current Round State Tracking

local CurrentPrefix = ""
local CurrentChosenWord = ""
local CurrentTypingThread = nil
local CurrentClearThread = nil
local LastAttemptedWord = nil
local TypedCharactersCount = 0
local TypedCharactersActionGeneration = 0
local IsMyTurnActive = false
local ActionGeneration = 0
local RoundGeneration = 0
local LastKnownTurn = nil
local LastTurnSource = "Unknown"
local TurnConfidence = "Unknown" -- Explicit / AttributeConfirmed / Uncertain / Unknown
local LastTurnRoundGeneration = 0
local LastTurnPrefix = ""
local LastAttemptedRoundGeneration = 0

local function invalidateActions()
    ActionGeneration = ActionGeneration + 1
    return ActionGeneration
end

local function isCurrentTurnContextValid(expectedRoundGeneration, expectedPrefix)
    local roundGeneration = expectedRoundGeneration or RoundGeneration
    local prefix = string.upper(tostring(expectedPrefix or CurrentPrefix or ""))

    return IsMyTurnActive
        and LastTurnRoundGeneration == roundGeneration
        and LastTurnPrefix == prefix
        and (LastTurnSource == "Explicit" or LastTurnSource == "Attribute")
end

-- Ultra-fast backspace clearing
local function clearTypedCharacters(isEmergency, doneCallback, expectedRoundGeneration)
    local thisRoundGeneration = expectedRoundGeneration or RoundGeneration

    if thisRoundGeneration ~= RoundGeneration then
        return
    end

    -- Snapshot before invalidating/cancelling so the count still represents
    -- the characters actually sent by the active typing action.
    local typedCountSnapshot = TypedCharactersCount
    TypedCharactersCount = 0
    TypedCharactersActionGeneration = 0

    local thisActionGeneration = invalidateActions()

    if CurrentTypingThread then
        task.cancel(CurrentTypingThread)
        CurrentTypingThread = nil
    end

    if CurrentClearThread then
        task.cancel(CurrentClearThread)
        CurrentClearThread = nil
    end

    CurrentClearThread = task.spawn(function()
        -- Delete exactly the characters sent by the active typing action.
        -- Do not add a fixed safety margin: that would delete characters that
        -- were never typed by this script.
        local backspacesToSend = typedCountSnapshot

        for _ = 1, backspacesToSend do
            if thisActionGeneration ~= ActionGeneration or thisRoundGeneration ~= RoundGeneration then
                return
            end

            event.fire("keyStroke", -1)
            event.remoteFire("keyStroke", -1)

            -- DeletePace is the source of truth for every backspace.
            local pace = Config.DeletePace or 0.025

            if pace > 0 then
                task.wait(pace)
            end
        end

        if thisActionGeneration ~= ActionGeneration or thisRoundGeneration ~= RoundGeneration then
            return
        end

        CurrentClearThread = nil

        if doneCallback then
            doneCallback()
        end
    end)
end

-- Word Selection Logic
-- Priority: WordChainLearned first, then all dictionary words.
local function selectWord(prefix, excludeWord)
    if not prefix or prefix == "" then
        return ""
    end

    prefix = string.upper(prefix)
    excludeWord = excludeWord and string.upper(tostring(excludeWord)) or nil

    local function isWordAllowed(w)
        return not UsedWordsInMatch[w]
            and not PendingWordsInMatch[w]
            and not BlacklistedWords[w]
            and not PersistentRejectedWords[w]
            and w ~= excludeWord
    end

    -- Priority 1: WordChainLearned
    local learnedPool = {}
    local learnedMatches = LearnedWordsByPrefix[prefix] or {}

    for _, w in ipairs(learnedMatches) do
        if isWordAllowed(w) then
            table.insert(learnedPool, w)
        end
    end

    if #learnedPool > 0 then
        return learnedPool[math.random(1, #learnedPool)]
    end

    -- Priority 2: all loaded dictionary words
    local pool = {}
    local seen = {}

    local fullMatches = WordsByPrefix[prefix] or {}
    for _, w in ipairs(fullMatches) do
        if not seen[w] and isWordAllowed(w) then
            seen[w] = true
            table.insert(pool, w)
        end
    end

    local extendedKey = string.sub(prefix, 1, math.min(3, #prefix))
    local extendedMatches = ExtendedWordsByPrefix[extendedKey] or {}

    for _, w in ipairs(extendedMatches) do
        if not seen[w]
            and string.sub(w, 1, #prefix) == prefix
            and isWordAllowed(w)
        then
            seen[w] = true
            table.insert(pool, w)
        end
    end

    -- FTW dictionary source, deduplicated against all other dictionary sources.
    local ftwMatches = FTWWordsByPrefix[extendedKey] or {}

    for _, w in ipairs(ftwMatches) do
        if not seen[w]
            and string.sub(w, 1, #prefix) == prefix
            and isWordAllowed(w)
        then
            seen[w] = true
            table.insert(pool, w)
        end
    end

    if #pool == 0 then
        return ""
    end

    return pool[math.random(1, #pool)]
end

-- Typing Simulation with Emergency Speed Support for Retries

local function typeAndSubmitWord(word, prefix, isEmergencyRetry, expectedRoundGeneration)
    local thisRoundGeneration = expectedRoundGeneration or RoundGeneration
    prefix = string.upper(tostring(prefix or ""))
    word = string.upper(tostring(word or ""))

    if thisRoundGeneration ~= RoundGeneration or prefix == "" or word == "" then
        return
    end

    if not isCurrentTurnContextValid(thisRoundGeneration, prefix) then
        return
    end

    local thisActionGeneration = invalidateActions()

    if CurrentTypingThread then
        task.cancel(CurrentTypingThread)
        CurrentTypingThread = nil
    end

    LastAttemptedWord = word
    LastAttemptedRoundGeneration = thisRoundGeneration
    _G.WordChainLastAttempted = word
    TypedCharactersCount = 0
    TypedCharactersActionGeneration = thisActionGeneration

    CurrentTypingThread = task.spawn(function()
        -- ReactionDelay source of truth:
        -- every typing attempt, including retry, waits this configured amount
        -- before sending the first character.
        local jitter = Config.TypingJitter or 0
        local reactionVariation = jitter > 0 and (((math.random() * 2) - 1) * jitter) or 0
        local reactionDelay = math.max(0.01, (Config.AnswerDelay or 0.50) + reactionVariation)
        task.wait(reactionDelay)

        if thisActionGeneration ~= ActionGeneration or thisRoundGeneration ~= RoundGeneration then
            return
        end

        local prefixLen = #prefix
        local suffix = string.sub(word, prefixLen + 1)

        for i = 1, #suffix do
            if thisActionGeneration ~= ActionGeneration or thisRoundGeneration ~= RoundGeneration then
                return
            end

            local ch = string.sub(suffix, i, i)

            event.fire("keyStroke", ch)
            event.remoteFire("keyStroke", ch)
            if thisActionGeneration == ActionGeneration and thisRoundGeneration == RoundGeneration then
                TypedCharactersCount = TypedCharactersCount + 1
            end

            -- TypingDelay is the source of truth for every keystroke.
            -- Emergency retries no longer override/cap this setting.
            local currentTypingDelay = Config.TypingDelay or 0.08
            local jitter = (Config.TypingJitter or 0) > 0
                and (((math.random() * 2) - 1) * Config.TypingJitter)
                or 0
            local letterDelay = math.max(0.005, currentTypingDelay + jitter)

            task.wait(letterDelay)
        end

        if thisActionGeneration ~= ActionGeneration or thisRoundGeneration ~= RoundGeneration then
            return
        end

        -- No hidden fixed submit delay: the three user-facing timing settings
        -- fully control reaction, typing, and deletion timing.
        if thisActionGeneration ~= ActionGeneration or thisRoundGeneration ~= RoundGeneration then
            return
        end

        -- Reserve the submitted word immediately so a delayed "correct" event
        -- cannot allow the same word to be selected again in this match.
        PendingWordsInMatch[word] = true

        event.remoteFire("tryAnswer")

        if thisActionGeneration == ActionGeneration and thisRoundGeneration == RoundGeneration then
            CurrentTypingThread = nil
        end
    end)
end

-- Turn attribute listener: connect once before updateRound can fire.
-- IsTurn=true after an updateRound with no explicit turnPlayer is treated as
-- fresh evidence only when the attribute actually changes for the current context.
local turnAttributeConn = LocalPlayer:GetAttributeChangedSignal("IsTurn"):Connect(function()
    if TurnConfidence ~= "Uncertain" then return end
    if LastTurnRoundGeneration ~= RoundGeneration then return end
    if LastTurnPrefix ~= CurrentPrefix then return end
    if LocalPlayer:GetAttribute("IsTurn") ~= true then return end
    if CurrentPrefix == "" then return end

    TurnConfidence = "AttributeConfirmed"
    IsMyTurnActive = true

    -- Revalidate all context immediately before starting a new action.
    local thisRoundGeneration = RoundGeneration
    local thisPrefix = string.upper(CurrentPrefix)

    if TurnConfidence ~= "AttributeConfirmed"
        or thisRoundGeneration ~= RoundGeneration
        or thisPrefix ~= string.upper(CurrentPrefix)
        or not IsMyTurnActive
        or LastTurnRoundGeneration ~= thisRoundGeneration
        or LastTurnPrefix ~= thisPrefix
    then
        return
    end

    local word = selectWord(thisPrefix, CurrentChosenWord)
    CurrentChosenWord = word

    if word == "" then
        TargetWordDisplay.Text = "NO MATCH FOUND"
        TargetWordDisplay.TextColor3 = Color3.fromRGB(255, 100, 100)
        return
    end

    TargetWordDisplay.Text = "WORD: " .. word
    TargetWordDisplay.TextColor3 = Color3.fromRGB(100, 220, 255)

    if Config.AutoAnswer and isCurrentTurnContextValid(thisRoundGeneration, thisPrefix) then
        typeAndSubmitWord(word, thisPrefix, false, thisRoundGeneration)
    end
end)

local function populateSuggestions(prefix)
    for _, child in ipairs(SuggestionsScroll:GetChildren()) do
        if child:IsA("TextButton") then
            child:Destroy()
        end
    end

    if not prefix or prefix == "" then
        SuggestionsScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
        return
    end

    prefix = string.upper(prefix)

    local MAX_SUGGESTIONS = 16
    local candidates = {}
    local seen = {}

    local function isSuggestionAllowed(w)
        return not seen[w]
            and not UsedWordsInMatch[w]
            and not PendingWordsInMatch[w]
            and not BlacklistedWords[w]
            and not PersistentRejectedWords[w]
    end

    -- Priority 1: Learned words ALWAYS occupy the first suggestion slots.
    -- Do not require DictionaryContext here: learned evidence may come from
    -- an older dictionary version and is still valid learned evidence.
    local learnedCandidates = {}
    for _, w in ipairs(LearnedWordsByPrefix[prefix] or {}) do
        if isSuggestionAllowed(w) then
            local meta = LearnedWords[w] or {}
            table.insert(learnedCandidates, {
                word = w,
                common = false,
                learned = true,
                confirmedCount = tonumber(meta.ConfirmedCount) or 1,
                lastConfirmedAt = tonumber(meta.LastConfirmedAt) or 0,
            })
        end
    end

    -- Prefer stronger learned evidence, then more recently confirmed words.
    table.sort(learnedCandidates, function(a, b)
        if a.confirmedCount ~= b.confirmedCount then
            return a.confirmedCount > b.confirmedCount
        end
        if a.lastConfirmedAt ~= b.lastConfirmedAt then
            return a.lastConfirmedAt > b.lastConfirmedAt
        end
        return a.word < b.word
    end)

    for _, item in ipairs(learnedCandidates) do
        if #candidates >= MAX_SUGGESTIONS then break end
        seen[item.word] = true
        table.insert(candidates, item)
    end

    -- Priority 2: Common words fill remaining slots only after Learned.
    if #candidates < MAX_SUGGESTIONS then
        for _, w in ipairs(CommonWordsByPrefix[prefix] or {}) do
            if isSuggestionAllowed(w) then
                seen[w] = true
                table.insert(candidates, {word = w, common = true, learned = false})
            end
            if #candidates >= MAX_SUGGESTIONS then break end
        end
    end

    -- Priority 3: Full dictionary fills whatever slots remain.
    if #candidates < MAX_SUGGESTIONS then
        for _, w in ipairs(WordsByPrefix[prefix] or {}) do
            if isSuggestionAllowed(w) then
                seen[w] = true
                table.insert(candidates, {
                    word = w,
                    common = CommonWords[w] == true,
                    learned = false,
                })
            end
            if #candidates >= MAX_SUGGESTIONS then break end
        end
    end

    -- Priority 4: Extended / FTW dictionaries.
    local extendedKey = string.sub(prefix, 1, math.min(3, #prefix))
    if #candidates < MAX_SUGGESTIONS then
        for _, w in ipairs(ExtendedWordsByPrefix[extendedKey] or {}) do
            if string.sub(w, 1, #prefix) == prefix and isSuggestionAllowed(w) then
                seen[w] = true
                table.insert(candidates, {word = w, common = false, learned = false})
            end
            if #candidates >= MAX_SUGGESTIONS then break end
        end
    end

    if #candidates < MAX_SUGGESTIONS then
        for _, w in ipairs(FTWWordsByPrefix[extendedKey] or {}) do
            if string.sub(w, 1, #prefix) == prefix and isSuggestionAllowed(w) then
                seen[w] = true
                table.insert(candidates, {word = w, common = false, learned = false})
            end
            if #candidates >= MAX_SUGGESTIONS then break end
        end
    end

    for _, item in ipairs(candidates) do
        local word = item.word
        local btn = Instance.new("TextButton")
        btn.Name = "Suggestion_" .. word
        btn.Size = UDim2.new(1, 0, 1, 0)
        btn.Font = Enum.Font.GothamMedium
        btn.TextSize = 10
        btn.AutoButtonColor = true
        btn.Parent = SuggestionsScroll

        -- Match the original Pasted markdown(3).md suggestion styling exactly.
        if item.learned then
            btn:SetAttribute("Source", "Learned")
            btn.BackgroundColor3 = Color3.fromRGB(24, 42, 60)
            btn.Text = "🧠 " .. word
            btn.TextColor3 = Color3.fromRGB(140, 220, 255)
        elseif item.common then
            btn:SetAttribute("Source", "Common")
            btn.BackgroundColor3 = Color3.fromRGB(24, 42, 60)
            btn.Text = "★ " .. word
            btn.TextColor3 = Color3.fromRGB(140, 220, 255)
        else
            btn:SetAttribute("Source", "Dictionary")
            btn.BackgroundColor3 = Color3.fromRGB(30, 34, 45)
            btn.Text = word
            btn.TextColor3 = Color3.fromRGB(200, 210, 230)
        end

        local bc = Instance.new("UICorner")
        bc.CornerRadius = UDim.new(0, 4)
        bc.Parent = btn

        btn.MouseButton1Click:Connect(function()
            if IsMyTurnActive and CurrentPrefix == prefix then
                typeAndSubmitWord(word, prefix, false, RoundGeneration)
            end
        end)
    end

    SuggestionsScroll.CanvasSize = UDim2.new(0, 0, 0, math.ceil(#candidates / 2) * 28)
end

local function checkIsMyTurn(turnPlayer, prompt)
    local requiredLetter = string.upper(tostring(prompt and prompt.RequiredLetter or ""))
    local hasCurrentPrompt = requiredLetter ~= ""

    if turnPlayer ~= nil then
        local result = false

        if turnPlayer == LocalPlayer then
            result = true
        elseif typeof(turnPlayer) == "Instance" and turnPlayer:IsA("Player") then
            result = (turnPlayer.UserId == LocalPlayer.UserId) or (turnPlayer.Name == LocalPlayer.Name)
        elseif type(turnPlayer) == "number" then
            result = (turnPlayer == LocalPlayer.UserId)
        elseif type(turnPlayer) == "string" then
            result = (turnPlayer == LocalPlayer.Name) or (turnPlayer == tostring(LocalPlayer.UserId))
        end

        LastKnownTurn = result
        LastTurnSource = "Explicit"
        TurnConfidence = result and "Explicit" or "ExplicitOther"
        LastTurnRoundGeneration = RoundGeneration
        LastTurnPrefix = requiredLetter
        return result
    end

    -- No explicit player was supplied. An existing IsTurn=true may be stale from
    -- the previous turn, so it is only a candidate until the attribute changes for
    -- the current round context. Never auto-answer from this snapshot alone.
    if hasCurrentPrompt and LocalPlayer:GetAttribute("IsTurn") == true then
        LastKnownTurn = nil
        LastTurnSource = "Attribute"
        TurnConfidence = "Uncertain"
        LastTurnRoundGeneration = RoundGeneration
        LastTurnPrefix = requiredLetter
        return false
    end

    LastKnownTurn = false
    LastTurnSource = "Unknown"
    TurnConfidence = "Unknown"
    LastTurnRoundGeneration = RoundGeneration
    LastTurnPrefix = requiredLetter
    return false
end

-- Event hookups

local updateRoundConn = event.remoteConnect("updateRound", function(prompt, p2, turnPlayer)
    RoundGeneration = RoundGeneration + 1
    local thisRoundGeneration = RoundGeneration

    -- Every updateRound establishes a new current-turn context. Invalidate all actions
    -- from the previous context before mutating prefix/counter state.
    invalidateActions()

    if CurrentTypingThread then
        task.cancel(CurrentTypingThread)
        CurrentTypingThread = nil
    end

    if CurrentClearThread then
        task.cancel(CurrentClearThread)
        CurrentClearThread = nil
    end

    TypedCharactersCount = 0
    TypedCharactersActionGeneration = 0
    LastAttemptedWord = nil
    LastAttemptedRoundGeneration = 0
    _G.WordChainLastAttempted = nil

    local isTurn = checkIsMyTurn(turnPlayer, prompt)

    IsMyTurnActive = isTurn

    local req = prompt and prompt.RequiredLetter or ""

    CurrentPrefix = req

    TypedCharactersCount = 0

    local opponentName = "Opponent"

    if typeof(turnPlayer) == "Instance" and turnPlayer:IsA("Player") then

        opponentName = turnPlayer.DisplayName or turnPlayer.Name

    elseif type(turnPlayer) == "string" and turnPlayer ~= "" then

        opponentName = turnPlayer

    end

    if req ~= "" then

        local turnLabel = isTurn and "YOU" or (TurnConfidence == "Uncertain" and "WAIT" or opponentName)
        PromptDisplay.Text = string.format("Prefix: [%s]  Turn: %s", req, turnLabel)

        PromptDisplay.TextColor3 = isTurn and Color3.fromRGB(100, 255, 140) or Color3.fromRGB(220, 180, 80)

        local word = selectWord(req)

        CurrentChosenWord = word

        if word ~= "" then

            TargetWordDisplay.Text = "WORD: " .. word

            TargetWordDisplay.TextColor3 = Color3.fromRGB(100, 220, 255)

        else

            TargetWordDisplay.Text = "NO MATCH FOUND"

            TargetWordDisplay.TextColor3 = Color3.fromRGB(255, 100, 100)

        end

        populateSuggestions(req)

        if isTurn and Config.AutoAnswer and word ~= "" and isCurrentTurnContextValid(thisRoundGeneration, req) then

            typeAndSubmitWord(word, req, false, thisRoundGeneration)

        end

    else

        PromptDisplay.Text = "Waiting for word prompt..."

        TargetWordDisplay.Text = "WORD: -"

    end

end)

-- ULTRA-FAST Strike Detection & Instant Auto-Recovery

local strikeConn = event.remoteConnect("strike", function(playerUserId, strikeNum, isAlreadyUsed)
    local isMyStrike = false

    if playerUserId ~= nil then
        if playerUserId == LocalPlayer.UserId then
            isMyStrike = true
        elseif typeof(playerUserId) == "Instance" and playerUserId == LocalPlayer then
            isMyStrike = true
        elseif type(playerUserId) == "string"
            and (playerUserId == LocalPlayer.Name or playerUserId == tostring(LocalPlayer.UserId))
        then
            isMyStrike = true
        end
    else
        isMyStrike = isCurrentTurnContextValid(RoundGeneration, CurrentPrefix)
    end

    if isMyStrike
        and LastAttemptedWord
        and LastAttemptedRoundGeneration == RoundGeneration
        and CurrentPrefix ~= ""
    then
        local failedWord = LastAttemptedWord
        local thisRoundGeneration = RoundGeneration
        local thisPrefix = CurrentPrefix

        -- Match-scoped behavior from the original solver: every struck word is
        -- blacklisted for the rest of this match, then cleared on endGame.
        BlacklistedWords[failedWord] = true
        _G.WordChainBlacklisted = BlacklistedWords
        PendingWordsInMatch[failedWord] = nil

        if isAlreadyUsed == true then
            -- Server says this word was already used in the current match.
            -- Keep it out of selectWord() until endGame resets the match-scoped set.
            UsedWordsInMatch[failedWord] = true
        else
            -- Only a server rejection becomes persistent across matches.
            PersistentRejectedWords[failedWord] = true
            _G.WordChainRejected = PersistentRejectedWords
            saveRejectedWords()
        end

        if Config.AutoAnswer then
            -- Immediately pick alternative word
            local retryWord = selectWord(thisPrefix, failedWord)
            if retryWord ~= "" then
                CurrentChosenWord = retryWord
                TargetWordDisplay.Text = "RETRYING: " .. retryWord
                TargetWordDisplay.TextColor3 = Color3.fromRGB(255, 150, 40)

                -- Fast flush backspaces and immediately type the new word with ZERO reaction delay
                clearTypedCharacters(true, function()
                    if thisRoundGeneration ~= RoundGeneration or thisPrefix ~= CurrentPrefix then
                        return
                    end

                    if isCurrentTurnContextValid(thisRoundGeneration, thisPrefix) then
                        typeAndSubmitWord(retryWord, thisPrefix, true, thisRoundGeneration)
                    end
                end, thisRoundGeneration)
            end
        end
    end
end)

local correctConn = event.remoteConnect("correct", function(ans)

    if ans and type(ans) == "string" then

        local w = string.upper(ans)

        PendingWordsInMatch[w] = nil
        UsedWordsInMatch[w] = true

        -- Server-confirmed evidence: keep confidence and dictionary context.
        local meta = LearnedWords[w]
        local isNewLearnedWord = meta == nil

        if not meta then
            meta = {
                ConfirmedCount = 0,
                LastConfirmedAt = 0,
                DictionaryContext = DictionaryContext or "PENDING",
            }
            LearnedWords[w] = meta
            indexLearnedWord(w)
        end

        meta.ConfirmedCount = math.max(0, tonumber(meta.ConfirmedCount) or 0) + 1
        meta.LastConfirmedAt = os.time()
        if DictionaryContext then
            meta.DictionaryContext = DictionaryContext
        end

        if isNewLearnedWord then
            LearnedNewSinceLastSave = LearnedNewSinceLastSave + 1
        end

        local learnedCount = 0
        for _ in pairs(LearnedWords) do learnedCount = learnedCount + 1 end
        if _G.WordChainStatusLabel then
            _G.WordChainStatusLabel.Text = string.format(
                "🧠 Learned: %d (+%d file) | Dict: %d",
                learnedCount,
                loadedFromFile,
                getCombinedDictionaryCount()
            )
            _G.WordChainStatusLabel.TextColor3 = Color3.fromRGB(120, 220, 255)
        end

        if LearnedNewSinceLastSave >= 5 then
            LearnedNewSinceLastSave = 0
            task.spawn(saveLearnedWords)
        end

    end

    -- Only the word belonging to our current typing action may reset the count.
    -- A correct event for another player's word must not mutate our input state.
    if ans and type(ans) == "string" then
        local w = string.upper(ans)
        if LastAttemptedRoundGeneration == RoundGeneration and LastAttemptedWord == w then
            TypedCharactersCount = 0
            TypedCharactersActionGeneration = 0
            LastAttemptedWord = nil
            LastAttemptedRoundGeneration = 0
        end
    end

end)

local endConn = event.remoteConnect("endGame", function()
    invalidateActions()
    RoundGeneration = RoundGeneration + 1

    if CurrentTypingThread then
        task.cancel(CurrentTypingThread)
        CurrentTypingThread = nil
    end

    if CurrentClearThread then
        task.cancel(CurrentClearThread)
        CurrentClearThread = nil
    end

    UsedWordsInMatch = {}
    BlacklistedWords = {}
    PendingWordsInMatch = {}
    _G.WordChainBlacklisted = BlacklistedWords
    LastKnownTurn = nil
    LastTurnSource = "Unknown"
    TurnConfidence = "Unknown"
    LastTurnRoundGeneration = 0
    LastTurnPrefix = ""

    CurrentPrefix = ""

    CurrentChosenWord = ""

    LastAttemptedWord = nil
    LastAttemptedRoundGeneration = 0
    _G.WordChainLastAttempted = nil

    IsMyTurnActive = false

    TypedCharactersCount = 0
    TypedCharactersActionGeneration = 0

    PromptDisplay.Text = "Game ended. Waiting..."

    TargetWordDisplay.Text = "WORD: -"

    -- Save learned words at end of every match so nothing is lost

    task.spawn(saveLearnedWords)

    -- LearnedWords intentionally persists across matches

end)

-- =====================================================================

-- AFK Prevention (Bypasses Roblox 20-minute Idled disconnect)

-- =====================================================================

local AfkConn = nil

local AfkThread = nil

local function startAfkPrevention()

    if AfkConn then AfkConn:Disconnect() AfkConn = nil end

    if AfkThread then task.cancel(AfkThread) AfkThread = nil end

    -- Method 1: Intercept standard Roblox Idled event via VirtualUser / VirtualInputManager

    local vu = nil

    pcall(function() vu = game:GetService("VirtualUser") end)

    AfkConn = LocalPlayer.Idled:Connect(function()

        if not Config.AfkPrevention then return end

        pcall(function()

            if vu then

                vu:CaptureController()

                vu:ClickButton2(Vector2.new(0, 0))

            end

        end)

    end)

    -- Method 2: Active periodic simulation so Roblox engine never enters idle state

    AfkThread = task.spawn(function()

        local vim = nil

        pcall(function() vim = game:GetService("VirtualInputManager") end)

        while true do

            local waitTime = Config.AfkInterval + (math.random(-20, 20))

            task.wait(math.max(30, waitTime))

            if Config.AfkPrevention then

                pcall(function()

                    if vu then

                        vu:CaptureController()

                        vu:ClickButton2(Vector2.new(0, 0))

                    end

                end)

                pcall(function()

                    if vim then

                        vim:SendKeyEvent(true, Enum.KeyCode.RightShift, false, game)

                        task.wait(0.05)

                        vim:SendKeyEvent(false, Enum.KeyCode.RightShift, false, game)

                    end

                end)

                -- Keep game-specific action as well

                pcall(function()

                    event.remoteFire("jumpRequest")

                end)

            end

        end

    end)

end

startAfkPrevention()

-- Rejoin Auto-Execute
-- This does not execute on the initial game/map entry. While this script is already
-- running, it queues the same local script for a later same-place teleport/rejoin.
-- The current script file must exist in the executor workspace under this filename.
local REJOIN_SCRIPT_FILE = WordChainStorageReady and wordChainPath(SCRIPT_FILE) or SCRIPT_FILE
local TeleportConn = nil

local function installRejoinAutoExecute()
    local queueTeleport = queue_on_teleport or queueonteleport

    if not queueTeleport and syn and syn.queue_on_teleport then
        queueTeleport = syn.queue_on_teleport
    end

    if type(queueTeleport) ~= "function" or type(readfile) ~= "function" then
        return
    end

    TeleportConn = LocalPlayer.OnTeleport:Connect(function(teleportState, placeId)
        if teleportState ~= Enum.TeleportState.Started then
            return
        end

        -- Only queue same-place transitions/rejoins. Initial entry cannot reach this
        -- callback because the solver has not been started yet.
        if tonumber(placeId) ~= tonumber(game.PlaceId) then
            return
        end

        local ok, source = pcall(readfile, REJOIN_SCRIPT_FILE)
        if not ok or type(source) ~= "string" or source == "" then
            warn("[WordChain] Rejoin auto-execute skipped: script file not found: " .. REJOIN_SCRIPT_FILE)
            return
        end

        pcall(queueTeleport, source)
    end)
end

installRejoinAutoExecute()

local function cleanup()
    -- Final save flush — captures settings and any words not yet saved by the debounce
    if SettingsSaveThread then
        pcall(task.cancel, SettingsSaveThread)
        SettingsSaveThread = nil
    end

    saveSettings()
    saveLearnedWords()
    saveRejectedWords()

    pcall(function()

        if AfkConn then AfkConn:Disconnect() AfkConn = nil end

        if TeleportConn then TeleportConn:Disconnect() TeleportConn = nil end

        if AfkThread then task.cancel(AfkThread) AfkThread = nil end

        if updateRoundConn then event.disconnect(updateRoundConn) end

        if strikeConn then event.disconnect(strikeConn) end

        if correctConn then event.disconnect(correctConn) end

        if endConn then event.disconnect(endConn) end

        if CurrentTypingThread then task.cancel(CurrentTypingThread) end

        if CurrentClearThread then task.cancel(CurrentClearThread) end

        ScreenGui:Destroy()

    end)

end

_G.WordChainGuiCleanup = cleanup

CloseBtn.MouseButton1Click:Connect(cleanup)
