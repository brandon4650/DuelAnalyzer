-- Duel Analyzer for World of Warcraft 5.4.8 (Mists of Pandaria)
-- This addon analyzes potential duel opponents and predicts your chances of winning

local addonName, addon = ...
DuelAnalyzer = CreateFrame("Frame", "DuelAnalyzerFrame")

-- Tooltip cache to improve performance
DuelAnalyzer.tooltipCache = {}
DuelAnalyzer.tooltipCacheTime = {}

local SCOUTER_TEXTURE = "Interface\\AddOns\\DuelAnalyzer\\scouter.tga"
local FALLBACK_TEXTURE = "Interface\\DialogFrame\\UI-DialogBox-Gold-Dragon"
local BEEP_SOUND = "Sound\\Interface\\MapPing.ogg"
local LEVEL_UP_SOUND = "Sound\\Interface\\LevelUp.ogg"

-- Database of class matchups (these values would be fine-tuned with actual data)
-- Format: [yourClass][theirClass] = win chance percentage
local matchupData = {
    ["WARRIOR"] = {
        ["WARRIOR"] = 50,
        ["PALADIN"] = 45,
        ["HUNTER"] = 40,
        ["ROGUE"] = 55,
        ["PRIEST"] = 60,
        ["DEATHKNIGHT"] = 40,
        ["SHAMAN"] = 50,
        ["MAGE"] = 35,
        ["WARLOCK"] = 40,
        ["MONK"] = 45,
        ["DRUID"] = 50
    },
    ["PALADIN"] = {
        ["WARRIOR"] = 55,
        ["PALADIN"] = 50,
        ["HUNTER"] = 45,
        ["ROGUE"] = 60,
        ["PRIEST"] = 55,
        ["DEATHKNIGHT"] = 55,
        ["SHAMAN"] = 50,
        ["MAGE"] = 40,
        ["WARLOCK"] = 45,
        ["MONK"] = 50,
        ["DRUID"] = 45
    },
    ["HUNTER"] = {
        ["WARRIOR"] = 60,
        ["PALADIN"] = 55,
        ["HUNTER"] = 50,
        ["ROGUE"] = 55,
        ["PRIEST"] = 65,
        ["DEATHKNIGHT"] = 50,
        ["SHAMAN"] = 60,
        ["MAGE"] = 55,
        ["WARLOCK"] = 60,
        ["MONK"] = 55,
        ["DRUID"] = 50
    },
    ["ROGUE"] = {
        ["WARRIOR"] = 45,
        ["PALADIN"] = 40,
        ["HUNTER"] = 45,
        ["ROGUE"] = 50,
        ["PRIEST"] = 70,
        ["DEATHKNIGHT"] = 40,
        ["SHAMAN"] = 55,
        ["MAGE"] = 50,
        ["WARLOCK"] = 55,
        ["MONK"] = 50,
        ["DRUID"] = 45
    },
    ["PRIEST"] = {
        ["WARRIOR"] = 40,
        ["PALADIN"] = 45,
        ["HUNTER"] = 35,
        ["ROGUE"] = 30,
        ["PRIEST"] = 50,
        ["DEATHKNIGHT"] = 45,
        ["SHAMAN"] = 45,
        ["MAGE"] = 40,
        ["WARLOCK"] = 45,
        ["MONK"] = 40,
        ["DRUID"] = 45
    },
    ["DEATHKNIGHT"] = {
        ["WARRIOR"] = 60,
        ["PALADIN"] = 45,
        ["HUNTER"] = 50,
        ["ROGUE"] = 60,
        ["PRIEST"] = 55,
        ["DEATHKNIGHT"] = 50,
        ["SHAMAN"] = 55,
        ["MAGE"] = 45,
        ["WARLOCK"] = 50,
        ["MONK"] = 55,
        ["DRUID"] = 50
    },
    ["SHAMAN"] = {
        ["WARRIOR"] = 50,
        ["PALADIN"] = 50,
        ["HUNTER"] = 40,
        ["ROGUE"] = 45,
        ["PRIEST"] = 55,
        ["DEATHKNIGHT"] = 45,
        ["SHAMAN"] = 50,
        ["MAGE"] = 45,
        ["WARLOCK"] = 50,
        ["MONK"] = 50,
        ["DRUID"] = 50
    },
    ["MAGE"] = {
        ["WARRIOR"] = 65,
        ["PALADIN"] = 60,
        ["HUNTER"] = 45,
        ["ROGUE"] = 50,
        ["PRIEST"] = 60,
        ["DEATHKNIGHT"] = 55,
        ["SHAMAN"] = 55,
        ["MAGE"] = 50,
        ["WARLOCK"] = 45,
        ["MONK"] = 55,
        ["DRUID"] = 50
    },
    ["WARLOCK"] = {
        ["WARRIOR"] = 60,
        ["PALADIN"] = 55,
        ["HUNTER"] = 40,
        ["ROGUE"] = 45,
        ["PRIEST"] = 55,
        ["DEATHKNIGHT"] = 50,
        ["SHAMAN"] = 50,
        ["MAGE"] = 55,
        ["WARLOCK"] = 50,
        ["MONK"] = 55,
        ["DRUID"] = 55
    },
    ["MONK"] = {
        ["WARRIOR"] = 55,
        ["PALADIN"] = 50,
        ["HUNTER"] = 45,
        ["ROGUE"] = 50,
        ["PRIEST"] = 60,
        ["DEATHKNIGHT"] = 45,
        ["SHAMAN"] = 50,
        ["MAGE"] = 45,
        ["WARLOCK"] = 45,
        ["MONK"] = 50,
        ["DRUID"] = 50
    },
    ["DRUID"] = {
        ["WARRIOR"] = 50,
        ["PALADIN"] = 55,
        ["HUNTER"] = 50,
        ["ROGUE"] = 55,
        ["PRIEST"] = 55,
        ["DEATHKNIGHT"] = 50,
        ["SHAMAN"] = 50,
        ["MAGE"] = 50,
        ["WARLOCK"] = 45,
        ["MONK"] = 50,
        ["DRUID"] = 50
    }
}

-- Gear score modifier parameters
local gearModifiers = {
    minDifference = 10, -- Minimum iLvl difference to affect win chance
    maxModifier = 20,   -- Maximum percentage to modify win chance
    scaleFactor = 0.5   -- How quickly the modifier scales with gear difference
}

-- Combat history storage
local duelHistory = {}

-- Initialize the addon
function DuelAnalyzer:OnLoad()
    -- Register events
    self:RegisterEvent("DUEL_REQUESTED")
    self:RegisterEvent("DUEL_OUTOFBOUNDS")
    self:RegisterEvent("DUEL_FINISHED")
    self:RegisterEvent("PLAYER_LOGIN")
    self:RegisterEvent("ADDON_LOADED")
    
    self:SetScript("OnEvent", self.OnEvent)
    
    -- Create UI frame
    self:CreateAnalyzerUI()
    
    -- Initialize tooltip functionality
    self.tooltipCache = {}
    self.tooltipCacheTime = {}
    
    -- Create the scouter frame on load
    self:CreateScouterFrame()
    
    -- Create a timer to clear the tooltip cache
    local cacheClearTimer = CreateFrame("Frame")
    cacheClearTimer:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = (self.elapsed or 0) + elapsed
        if self.elapsed > 60 then -- Clear cache every minute
            if DuelAnalyzer.ClearTooltipCache then
                DuelAnalyzer:ClearTooltipCache()
            end
            self.elapsed = 0
        end
    end)
    

end

function DuelAnalyzer:ClearTooltipCache()
    local currentTime = GetTime()
    local expireTime = 30 -- Cache expires after 30 seconds
    
    for name, time in pairs(self.tooltipCacheTime) do
        if currentTime - time > expireTime then
            self.tooltipCache[name] = nil
            self.tooltipCacheTime[name] = nil
        end
    end
end

-- Event handler
function DuelAnalyzer:OnEvent(event, arg1, arg2, arg3)
    if event == "ADDON_LOADED" and arg1 == addonName then
        -- Load saved variables
        if DuelAnalyzerDB == nil then
            DuelAnalyzerDB = {
                history = {},
                settings = {
                    showWindow = true,
                    showChatMessage = true,
                    trackHistory = true,
                    showTooltip = true,
                    scouterStyle = true  -- Add this line
                }
            }
        end
        duelHistory = DuelAnalyzerDB.history or {}
        print("|cFF00FF00[Duel Analyzer]|r Loaded. Type /danalyzer for options.")
    elseif event == "PLAYER_LOGIN" then
        -- Initialize UI on login
        self:CreateAnalyzerUI()
    elseif event == "DUEL_REQUESTED" then
        local challenger = arg1
        if challenger and DuelAnalyzerDB and DuelAnalyzerDB.settings and DuelAnalyzerDB.settings.showWindow then
            -- For duel requests, the best approach is to save the name and tell the user how to target
            print("|cFF00FF00[Duel Analyzer]|r " .. challenger .. " has challenged you to a duel!")
            print("|cFF00FF00[Duel Analyzer]|r Target them with /tar " .. challenger .. " then type /danalyzer analyze")
            
            -- Store the name for the analyze command to use
            self.lastDuelRequest = challenger
        end
    elseif event == "DUEL_FINISHED" then
        -- Record the duel result if tracking is enabled
        if DuelAnalyzerDB and DuelAnalyzerDB.settings and DuelAnalyzerDB.settings.trackHistory then
            local winner = arg1
            if winner then
                local wasWin = (winner == UnitName("player"))
                local opponent = self.lastOpponent
                if opponent then
                    self:RecordDuelResult(opponent, wasWin)
                    
                    -- Print result
                    if wasWin then
                        print("|cFF00FF00[Duel Analyzer]|r Victory against " .. opponent .. " recorded.")
                    else
                        print("|cFFFF0000[Duel Analyzer]|r Defeat against " .. opponent .. " recorded.")
                    end
                end
            end
        end
    end
end

-- Create the main UI frame
function DuelAnalyzer:CreateAnalyzerUI()
    -- Main frame
    local frame = CreateFrame("Frame", "DuelAnalyzerDisplay", UIParent)
    frame:SetSize(300, 200)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetFrameStrata("HIGH")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()
    
    -- Background
    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetAllPoints(true)
    frame.bg:SetTexture(0, 0, 0, 0.7)
    
    -- Border
    frame.border = CreateFrame("Frame", nil, frame)
    frame.border:SetPoint("TOPLEFT", -1, 1)
    frame.border:SetPoint("BOTTOMRIGHT", 1, -1)
    frame.border:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", 
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = {left = 4, right = 4, top = 4, bottom = 4}
    })
    
    -- Title text
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.title:SetPoint("TOP", frame, "TOP", 0, -10)
    frame.title:SetText("Duel Analyzer")
    
    -- Opponent info
    frame.opponentName = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.opponentName:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, -40)
    frame.opponentName:SetText("Opponent: ")
    
    frame.opponentClass = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.opponentClass:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, -60)
    frame.opponentClass:SetText("Class: ")
    
    frame.opponentSpec = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.opponentSpec:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, -80)
    frame.opponentSpec:SetText("Spec: ")
    
    frame.opponentGear = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.opponentGear:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, -100)
    frame.opponentGear:SetText("Gear Score: ")
    
    -- Win chance
    frame.winChance = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.winChance:SetPoint("BOTTOM", frame, "BOTTOM", 0, 40)
    frame.winChance:SetText("Win Chance: Analyzing...")
    
    -- Close button
    frame.closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    frame.closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    
    -- Store reference to the UI
    self.ui = frame
end

-- Calculate overall win chance with advanced analytics and level considerations
function DuelAnalyzer:CalculateWinChance(opponentName)
    -- Define gearModifiers if it doesn't exist
    if not gearModifiers then
        gearModifiers = {
            minDifference = 10, -- Minimum iLvl difference to affect win chance
            maxModifier = 20,   -- Maximum percentage to modify win chance
            scaleFactor = 0.5   -- How quickly the modifier scales with gear difference
        }
    end
    
    -- Get player and opponent class and spec info
    local playerClass = select(2, UnitClass("player"))
    local opponentClass = select(2, UnitClass(opponentName))
    
    -- Get player and opponent specs
    local playerSpec, playerRole = self:GetPlayerSpecialization()
    local opponentSpec, opponentRole = self:GetUnitSpecialization(opponentName)
    
    -- Get player and opponent levels
    local playerLevel = UnitLevel("player") or 0
    local opponentLevel = UnitLevel(opponentName) or 0
    local levelDifference = playerLevel - opponentLevel
    
    -- Store data for UI display
    self.matchupDetails = {
        playerClass = playerClass,
        playerSpec = playerSpec,
        playerRole = playerRole,
        opponentClass = opponentClass,
        opponentSpec = opponentSpec,
        opponentRole = opponentRole,
        playerLevel = playerLevel,
        opponentLevel = opponentLevel,
        levelDifference = levelDifference
    }
    
    -- ========== CLASS MATCHUP BASE CHANCE ==========
    -- Get base matchup chance from database
    local baseChance = 50
    if matchupData[playerClass] and matchupData[playerClass][opponentClass] then
        baseChance = matchupData[playerClass][opponentClass]
    end
    
    -- ========== SPEC VS SPEC ANALYSIS ==========
    local specModifier = 0
    
    -- More detailed spec matchup analysis
    if playerClass == "WARRIOR" then
        if playerSpec == "Arms" then
            -- Arms counters cloth classes better
            if opponentClass == "MAGE" or opponentClass == "WARLOCK" or opponentClass == "PRIEST" then
                specModifier = specModifier + 8
            end
            -- Arms has difficulty with druids
            if opponentClass == "DRUID" and opponentSpec == "Feral" then
                specModifier = specModifier - 5
            end
        elseif playerSpec == "Fury" then
            -- Fury does well against other melee
            if opponentRole == "DAMAGER" and (opponentClass == "ROGUE" or opponentClass == "SHAMAN" or opponentClass == "PALADIN") then
                specModifier = specModifier + 5
            end
            -- Fury struggles against control
            if opponentClass == "MAGE" and opponentSpec == "Frost" then
                specModifier = specModifier - 10
            end
        elseif playerSpec == "Protection" then
            -- Protection counters physical damage
            if opponentClass == "ROGUE" or opponentClass == "HUNTER" or 
               (opponentClass == "WARRIOR" and opponentSpec ~= "Arms") then
                specModifier = specModifier + 12
            end
            -- Protection weak against casters
            if opponentClass == "MAGE" or opponentClass == "WARLOCK" or 
               (opponentClass == "SHAMAN" and opponentSpec == "Elemental") then
                specModifier = specModifier - 8
            end
        end
    elseif playerClass == "PALADIN" then
        if playerSpec == "Retribution" then
            -- Ret does well against warlocks
            if opponentClass == "WARLOCK" then
                specModifier = specModifier + 10
            end
            -- Ret struggles against hunters
            if opponentClass == "HUNTER" then
                specModifier = specModifier - 8
            end
        end
        -- Additional paladin spec matchups would be defined here
    end
    
    -- Similar detailed matchups would be defined for all classes and specs
    -- This is a sample of the logic - a full addon would have extensive matchup data
    
    -- ========== ROLE ADVANTAGE ANALYSIS ==========
    local roleModifier = 0
    
    -- General role advantages (simplified)
    if playerRole == "TANK" and opponentRole == "DAMAGER" then
        roleModifier = 5  -- Tanks generally durable against DPS
        -- Adjust for specific matchups
        if opponentClass == "MAGE" or opponentClass == "WARLOCK" then
            roleModifier = roleModifier - 10  -- But casters counter tanks in duels
        end
    elseif playerRole == "HEALER" and opponentRole == "TANK" then
        roleModifier = 8  -- Healers can outlast tanks
    elseif playerRole == "HEALER" and opponentRole == "DAMAGER" then
        roleModifier = -5  -- Healers vulnerable to burst DPS
        -- Adjust for specific matchups
        if opponentClass == "ROGUE" or opponentClass == "MAGE" then
            roleModifier = roleModifier - 10  -- Classes with interrupts counter healers
        end
    end
    
    -- ========== LEVEL ADVANTAGE ANALYSIS ==========
    local levelModifier = 0
    
    if levelDifference ~= 0 then
        -- Enhanced level difference calculation:
        -- 1-5 level difference: 3% per level
        -- 6-10 level difference: 4% per level beyond 5
        -- 10+ level difference: 5% per level beyond 10
        -- Maximum cap of 40%
        
        if levelDifference > 0 then
            -- Player has level advantage
            if levelDifference <= 5 then
                levelModifier = levelDifference * 3
            elseif levelDifference <= 10 then
                levelModifier = 15 + ((levelDifference - 5) * 4)
            else
                levelModifier = 35 + ((levelDifference - 10) * 5)
            end
            levelModifier = math.min(levelModifier, 40)
        else
            -- Opponent has level advantage
            local absDiff = math.abs(levelDifference)
            if absDiff <= 5 then
                levelModifier = -(absDiff * 3)
            elseif absDiff <= 10 then
                levelModifier = -15 - ((absDiff - 5) * 4)
            else
                levelModifier = -35 - ((absDiff - 10) * 5)
            end
            levelModifier = math.max(levelModifier, -40)
        end
        
        print("|cFF00FF00[Duel Analyzer]|r DEBUG - Level difference: " .. levelDifference .. " (modifier: " .. levelModifier .. "%)")
    end
    
    -- ========== GEAR ANALYSIS ==========
    -- Calculate gear scores with advanced system
    local playerGearScore = self:CalculateGearScore("player")
    local opponentGearScore = self:CalculateGearScore(opponentName)
    
    -- Extract detailed gear information
    local playerGearDetails = self.equipmentDetails
    local gearModifier = 0
    
    -- Base gear score difference
    local gearDifference = playerGearScore - opponentGearScore
    if math.abs(gearDifference) > gearModifiers.minDifference then
        local scaledDifference = (math.abs(gearDifference) - gearModifiers.minDifference) * gearModifiers.scaleFactor
        gearModifier = math.min(scaledDifference, gearModifiers.maxModifier)
        if gearDifference < 0 then
            gearModifier = -gearModifier
        end
    end
    
    print("|cFF00FF00[Duel Analyzer]|r DEBUG - Gear difference: " .. gearDifference .. " (modifier: " .. gearModifier .. "%)")
    
    -- ========== SPECIAL EQUIPMENT ADVANTAGES ==========
    -- Special equipment advantages logic
    -- (Using existing equipment advantage logic)
    
    -- Specific class advantages based on gear
    local equipAdvantage = 0
    
    -- Classes with CC that benefit more from opponent lacking PvP trinket
    if not (self.opponentDetails and self.opponentDetails.hasPvPTrinket) and (
        playerClass == "MAGE" or 
        playerClass == "ROGUE" or 
        (playerClass == "WARRIOR" and playerSpec == "Arms") or
        (playerClass == "DRUID" and playerSpec == "Feral")
    ) then
        equipAdvantage = equipAdvantage + 15
    end
    
    -- Legendary cloak advantage
    if playerGearDetails and playerGearDetails.legendaryCloak and 
       not (self.opponentDetails and self.opponentDetails.legendaryCloak) then
        equipAdvantage = equipAdvantage + 8
    elseif self.opponentDetails and self.opponentDetails.legendaryCloak and 
           not (playerGearDetails and playerGearDetails.legendaryCloak) then
        equipAdvantage = equipAdvantage - 8
    end
    
    -- ========== COMBAT HISTORY ANALYSIS ==========
    local historyModifier = self:CalculateHistoryModifier(opponentName, opponentClass, opponentSpec)
    
    -- ========== CALCULATE FINAL WIN CHANCE ==========
    -- Sum all modifiers
    local finalChance = baseChance + specModifier + roleModifier + levelModifier + gearModifier + equipAdvantage + historyModifier
    
    -- Ensure the chance is between 1 and 99 percent (never certain)
    finalChance = math.max(1, math.min(99, finalChance))
    
    -- Store detailed breakdown for UI display
    self.chanceBreakdown = {
        baseChance = baseChance,
        specModifier = specModifier,
        roleModifier = roleModifier,
        levelModifier = levelModifier,
        gearModifier = gearModifier,
        equipAdvantage = equipAdvantage,
        historyModifier = historyModifier,
        finalChance = finalChance
    }
    
    -- Print detailed breakdown
    print("|cFF00FF00[Duel Analyzer]|r DEBUG - Win chance breakdown:")
    print("|cFF00FF00[Duel Analyzer]|r DEBUG - Base class matchup: " .. baseChance .. "%")
    print("|cFF00FF00[Duel Analyzer]|r DEBUG - Spec matchup: " .. specModifier .. "%")
    print("|cFF00FF00[Duel Analyzer]|r DEBUG - Role matchup: " .. roleModifier .. "%")
    print("|cFF00FF00[Duel Analyzer]|r DEBUG - Level difference: " .. levelModifier .. "%")
    print("|cFF00FF00[Duel Analyzer]|r DEBUG - Gear advantage: " .. gearModifier .. "%")
    print("|cFF00FF00[Duel Analyzer]|r DEBUG - Equipment bonuses: " .. equipAdvantage .. "%")
    print("|cFF00FF00[Duel Analyzer]|r DEBUG - History modifier: " .. historyModifier .. "%")
    print("|cFF00FF00[Duel Analyzer]|r DEBUG - Final win chance: " .. finalChance .. "%")
    
    -- Return the values for display
    return finalChance, baseChance, specModifier + roleModifier, gearModifier + equipAdvantage, historyModifier, playerGearScore, opponentGearScore
end

-- Analyze a potential duel opponent
function DuelAnalyzer:AnalyzeOpponent(opponentName)
    -- Check if opponent name exists
    if not opponentName or opponentName == "" then
        print("|cFF00FF00[Duel Analyzer]|r Unable to analyze: Missing opponent name")
        return
    end

    -- In MoP, we need to handle targeting differently
    -- First check if they're already targeted
    if UnitName("target") == opponentName then
        -- We have the right target, use it
        print("|cFF00FF00[Duel Analyzer]|r Found " .. opponentName .. " (already targeted)")
        self.lastOpponent = opponentName
        self:PerformAnalysis(opponentName, "target")
        return
    end
    
    -- Try various unit IDs
    local unitIDs = {"mouseover", "focus"}
    
    -- Try party members
    for i=1, 4 do
        table.insert(unitIDs, "party"..i)
    end
    
    -- Try raid members
    for i=1, 40 do
        table.insert(unitIDs, "raid"..i)
    end
    
    -- Try nearby players (nameplates)
    for i=1, 40 do
        table.insert(unitIDs, "nameplate"..i)
    end
    
    -- Check all these unit IDs
    for _, unitID in ipairs(unitIDs) do
        if UnitExists(unitID) and UnitIsPlayer(unitID) and UnitName(unitID) == opponentName then
            print("|cFF00FF00[Duel Analyzer]|r Found " .. opponentName .. " (unit: " .. unitID .. ")")
            self.lastOpponent = opponentName
            self:PerformAnalysis(opponentName, unitID)
            return
        end
    end
    
    -- If we get here, we couldn't find them
    print("|cFF00FF00[Duel Analyzer]|r Unable to analyze: Cannot locate " .. opponentName .. " - ensure they are nearby and try /tar " .. opponentName)
end

-- Perform the actual analysis once we've found a valid unit
function DuelAnalyzer:PerformAnalysis(opponentName, unitID)
    print("|cFF00FF00[Duel Analyzer]|r Beginning analysis of " .. opponentName .. " using " .. unitID)
    
    -- Debug: Print unit info to help diagnosis
    print("|cFF00FF00[Duel Analyzer]|r DEBUG - Unit exists: " .. tostring(UnitExists(unitID)))
    print("|cFF00FF00[Duel Analyzer]|r DEBUG - Unit is player: " .. tostring(UnitIsPlayer(unitID)))
    print("|cFF00FF00[Duel Analyzer]|r DEBUG - Unit name: " .. tostring(UnitName(unitID)))
    
    -- Get class info
    local localizedClass, englishClass = UnitClass(unitID)
    
    -- Debug: Print class info (note: in your server, these seem to be reversed)
    print("|cFF00FF00[Duel Analyzer]|r DEBUG - English class: " .. tostring(localizedClass))
    print("|cFF00FF00[Duel Analyzer]|r DEBUG - Localized class: " .. tostring(englishClass))
    
    -- Fix for reversed values or strange formatting
    if englishClass and type(englishClass) == "string" then
        englishClass = string.upper(englishClass)
    end
    
    if not englishClass or englishClass == "" then
        -- Try fallback methods to determine class
        -- (code for fallbacks from previous version)
    end
    
    -- Safety check for class info after our efforts
    if not englishClass or englishClass == "" then
        print("|cFF00FF00[Duel Analyzer]|r Unable to analyze: Cannot determine opponent class after multiple attempts")
        return
    end
    
    print("|cFF00FF00[Duel Analyzer]|r Determined class: " .. localizedClass)
    
    -- Get class color
    local opponentClassColor = RAID_CLASS_COLORS[englishClass]
    if not opponentClassColor then
        print("|cFF00FF00[Duel Analyzer]|r DEBUG - No class color for: " .. englishClass)
        -- Fallback if color not found
        opponentClassColor = { r = 1, g = 1, b = 1 }
    else
        print("|cFF00FF00[Duel Analyzer]|r DEBUG - Found class color")
    end
    
    local coloredClass = string.format("|cff%02x%02x%02x%s|r", 
        math.floor(opponentClassColor.r*255), 
        math.floor(opponentClassColor.g*255), 
        math.floor(opponentClassColor.b*255), 
        localizedClass)
    
    -- Continue with analysis
    local opponentSpec, opponentRole = self:GetUnitSpecialization(unitID)
    local opponentGearScore = self:CalculateGearScore(unitID)
    
    -- Calculate win chance
    local winChance, baseChance, specMod, gearMod, historyMod = self:CalculateWinChance(opponentName)
    
    -- Update UI
    self.ui.opponentName:SetText("Opponent: " .. opponentName)
    self.ui.opponentClass:SetText("Class: " .. coloredClass)
    self.ui.opponentSpec:SetText("Spec: " .. opponentSpec)
    self.ui.opponentGear:SetText("Gear Score: " .. opponentGearScore)
    
    -- Set win chance with color based on likelihood
    local chanceColor = "FFFFFF"
    if winChance >= 70 then
        chanceColor = "00FF00" -- Green for good chance
    elseif winChance >= 40 then
        chanceColor = "FFFF00" -- Yellow for medium chance
    else
        chanceColor = "FF0000" -- Red for poor chance
    end
    
    self.ui.winChance:SetText(string.format("Win Chance: |cff%s%d%%|r", chanceColor, winChance))
    
    -- Show the analysis window
    self.ui:Show()
    
    -- Output to chat if enabled
    if DuelAnalyzerDB.settings.showChatMessage then
        print(string.format("|cFF00FF00[Duel Analyzer]|r Your estimated win chance against %s (%s %s) is |cff%s%d%%|r", 
            opponentName, opponentSpec, localizedClass, chanceColor, winChance))
    end
end

-- Get player's current specialization
function DuelAnalyzer:GetPlayerSpecialization()
    local specIndex = GetSpecialization()
    if specIndex then
        local _, specName, _, _, _, role = GetSpecializationInfo(specIndex)
        return specName, role
    end
    return "Unknown", "Unknown"
end

-- Advanced specialization detection with talent analysis
function DuelAnalyzer:GetUnitSpecialization(unit)
    -- If it's the player, we can get spec directly
    if unit == "player" then
        local specIndex = GetSpecialization()
        if specIndex then
            local _, specName, _, _, _, role = GetSpecializationInfo(specIndex)
            return specName, role
        end
        return "Unknown", "Unknown"
    end
    
    -- For other players, we need to inspect them
    if not UnitIsVisible(unit) then
        return "Unknown (Not Visible)", "Unknown"
    end
    
    if not CanInspect(unit) then
        return "Unknown (Cannot Inspect)", "Unknown"
    end
    
    -- Attempt to find spec through inspection
    -- Note: In MoP, this is more complex due to API limitations
    -- We'll use talents as a proxy for determining spec
    
    -- Request inspection (actual addon would handle INSPECT_READY event)
    NotifyInspect(unit)
    
    -- Create our spec detection frame if it doesn't exist
    if not self.specScanFrame then
        self.specScanFrame = CreateFrame("Frame", "DuelAnalyzerSpecScan")
        self.specScanFrame:RegisterEvent("INSPECT_READY")
        self.specScanFrame.currentUnit = nil
        self.specScanFrame.pendingSpecResults = {}
        
        self.specScanFrame:SetScript("OnEvent", function(frame, event, guid)
            if event == "INSPECT_READY" and frame.currentUnit and UnitGUID(frame.currentUnit) == guid then
                -- Get class
                local _, class = UnitClass(frame.currentUnit)
                
                -- Create a score for each possible specialization based on talent choices
                local specScores = {}
                
                -- In MoP, each class has 3 talent specializations
                -- These are the original WoW specs before 4th specs were added
                if class == "WARRIOR" then
                    specScores = {Arms = 0, Fury = 0, Protection = 0}
                elseif class == "PALADIN" then
                    specScores = {Holy = 0, Protection = 0, Retribution = 0}
                elseif class == "HUNTER" then
                    specScores = {BeastMastery = 0, Marksmanship = 0, Survival = 0}
                elseif class == "ROGUE" then
                    specScores = {Assassination = 0, Combat = 0, Subtlety = 0}
                elseif class == "PRIEST" then
                    specScores = {Discipline = 0, Holy = 0, Shadow = 0}
                elseif class == "DEATHKNIGHT" then
                    specScores = {Blood = 0, Frost = 0, Unholy = 0}
                elseif class == "SHAMAN" then
                    specScores = {Elemental = 0, Enhancement = 0, Restoration = 0}
                elseif class == "MAGE" then
                    specScores = {Arcane = 0, Fire = 0, Frost = 0}
                elseif class == "WARLOCK" then
                    specScores = {Affliction = 0, Demonology = 0, Destruction = 0}
                elseif class == "MONK" then
                    specScores = {Brewmaster = 0, Mistweaver = 0, Windwalker = 0}
                elseif class == "DRUID" then
                    specScores = {Balance = 0, Feral = 0, Guardian = 0, Restoration = 0}
                end
                
                -- In Mists of Pandaria, analyze talent picks to determine specialization
                for tier = 1, 6 do  -- 6 talent tiers in MoP
                    local talentID = select(1, GetTalentInfo(tier, 1, true, nil, frame.currentUnit))
                    
                    -- Example talent analysis for Warriors
                    if class == "WARRIOR" then
                        if tier == 1 then
                            if talentID == 1 then  -- Juggernaut
                                specScores.Arms = specScores.Arms + 2
                            elseif talentID == 2 then  -- Double Time
                                specScores.Fury = specScores.Fury + 1
                                specScores.Protection = specScores.Protection + 1
                            elseif talentID == 3 then  -- Warbringer
                                specScores.Protection = specScores.Protection + 2
                            end
                        end
                        -- Additional tiers would be analyzed similarly
                    end
                    
                    -- Similar analyses for other classes would be added here
                    -- This is just a sample - a full addon would have complete talent mappings
                end
                
                -- Check for specialization-specific spells in their spellbook
                -- This helps with spec detection when talents are ambiguous
                
                -- Example for Warriors
                if class == "WARRIOR" then
                    -- Check for Arms-specific spells
                    if IsSpellKnown(12294, true) then  -- Mortal Strike
                        specScores.Arms = specScores.Arms + 5
                    end
                    
                    -- Check for Fury-specific spells
                    if IsSpellKnown(23881, true) then  -- Bloodthirst
                        specScores.Fury = specScores.Fury + 5
                    end
                    
                    -- Check for Protection-specific spells
                    if IsSpellKnown(2565, true) then  -- Shield Block
                        specScores.Protection = specScores.Protection + 5
                    end
                end
                
                -- Determine highest scoring spec
                local highestScore = 0
                local detectedSpec = "Unknown"
                local detectedRole = "Unknown"
                
                for spec, score in pairs(specScores) do
                    if score > highestScore then
                        highestScore = score
                        detectedSpec = spec
                        
                        -- Set role based on spec
                        if spec == "Protection" or spec == "Guardian" or spec == "Brewmaster" or spec == "Blood" then
                            detectedRole = "TANK"
                        elseif spec == "Holy" or spec == "Discipline" or spec == "Restoration" or spec == "Mistweaver" then
                            detectedRole = "HEALER"
                        else
                            detectedRole = "DAMAGER"
                        end
                    end
                end
                
                -- Ensure the frame has a pendingSpecResults table
                if not frame.pendingSpecResults then
                    frame.pendingSpecResults = {}
                end
                
                -- Store the results
                frame.pendingSpecResults[UnitGUID(frame.currentUnit)] = {
                    spec = detectedSpec,
                    role = detectedRole,
                    class = class,
                    timestamp = GetTime()
                }
                
                -- Clear current inspection
                frame.currentUnit = nil
            end
        end)
    end
    
    -- Ensure pendingSpecResults exists
    if not self.specScanFrame.pendingSpecResults then
        self.specScanFrame.pendingSpecResults = {}
    end
    
    -- Check if we already have recent results for this unit
    local guid = UnitGUID(unit)
    if guid and self.specScanFrame.pendingSpecResults[guid] then
        local result = self.specScanFrame.pendingSpecResults[guid]
        -- Use cached result if it's less than 5 minutes old
        if GetTime() - result.timestamp < 300 then
            return result.spec, result.role
        end
    end
    
    -- Set up a new inspection
    self.specScanFrame.currentUnit = unit
    NotifyInspect(unit)
    
    -- Check equipment to help determine spec
    local mainHandLink = GetInventoryItemLink(unit, 16)  -- Main hand slot
    local offHandLink = GetInventoryItemLink(unit, 17)   -- Off hand slot
    
    local _, class = UnitClass(unit)
    if class == "WARRIOR" then
        if offHandLink then
            local _, _, _, _, _, _, _, _, equipSlot = GetItemInfo(offHandLink)
            if equipSlot == "INVTYPE_SHIELD" then
                return "Protection", "TANK"
            else
                local _, _, _, _, _, _, _, _, mainHandType = GetItemInfo(mainHandLink)
                if mainHandType == "INVTYPE_2HWEAPON" and not IsEquippedItemType("INVTYPE_SHIELD", unit) then
                    return "Arms", "DAMAGER"
                else
                    return "Fury", "DAMAGER"
                end
            end
        elseif mainHandLink then
            local _, _, _, _, _, _, _, _, mainHandType = GetItemInfo(mainHandLink)
            if mainHandType == "INVTYPE_2HWEAPON" then
                return "Arms", "DAMAGER"
            end
        end
    elseif class == "PALADIN" then
        -- Similar logic for Paladins
        if offHandLink then
            local _, _, _, _, _, _, _, _, equipSlot = GetItemInfo(offHandLink)
            if equipSlot == "INVTYPE_SHIELD" then
                -- Check intellect vs strength to distinguish Holy from Prot
                return "Protection", "TANK"  -- Default to Protection, will refine with Inspect data
            end
        end
    end
    
    -- Default return until inspection completes
    return "Analyzing...", "Unknown"
end

-- Advanced gear analysis that considers player level, PvP power, resilience, and set bonuses
function DuelAnalyzer:CalculateGearScore(unit)
    local totalIlvl = 0
    local itemCount = 0
    local pvpPower = 0
    local resilience = 0
    local tier15Count = 0
    local tier16Count = 0
    local legendaryCloak = false
    local legendaryMeta = false
    local setItems = {}
    local trinkets = {}
    local weapons = {}
    
    -- Make sure unit name and level are valid before accessing them
    local unitName = UnitName(unit) or "Unknown"
    local unitLevel = UnitLevel(unit) or 0
    
    -- Show debug info only for target (opponent), not for player
    local isPlayer = (unit == "player")
    local showDebug = not isPlayer
    
    -- Level advantage/disadvantage calculation
    local playerLevel = UnitLevel("player") or 0
    local levelDifference = playerLevel - unitLevel
    
    if showDebug then
        print("|cFF00FF00[Duel Analyzer]|r DEBUG - " .. unitName .. " is level " .. unitLevel)
        
        if levelDifference ~= 0 then
            print("|cFF00FF00[Duel Analyzer]|r DEBUG - Level difference: " .. levelDifference .. " levels " .. 
                (levelDifference > 0 and "advantage" or "disadvantage"))
        end
    end
    
    -- Slot weights - some slots matter more than others
    local slotWeights = {
        [1] = 1.0,    -- Head
        [2] = 0.6,    -- Neck
        [3] = 1.0,    -- Shoulder
        [5] = 1.0,    -- Chest
        [6] = 0.6,    -- Waist
        [7] = 1.0,    -- Legs
        [8] = 0.8,    -- Feet
        [9] = 0.6,    -- Wrist
        [10] = 0.6,   -- Hands
        [11] = 0.6,   -- Finger 1
        [12] = 0.6,   -- Finger 2
        [13] = 1.0,   -- Trinket 1
        [14] = 1.0,   -- Trinket 2
        [15] = 1.2,   -- Back
        [16] = 1.4,   -- Main Hand
        [17] = 1.0    -- Off Hand
    }
    
    -- Slot names for debugging
    local slotNames = {
        [1] = "Head",
        [2] = "Neck",
        [3] = "Shoulder",
        [4] = "Shirt",
        [5] = "Chest",
        [6] = "Waist",
        [7] = "Legs",
        [8] = "Feet",
        [9] = "Wrist",
        [10] = "Hands",
        [11] = "Ring 1",
        [12] = "Ring 2",
        [13] = "Trinket 1",
        [14] = "Trinket 2",
        [15] = "Cloak",
        [16] = "Main Hand",
        [17] = "Off Hand",
        [18] = "Ranged/Relic"
    }
    
    -- Inspect the unit if possible
    if unit ~= "player" and CanInspect(unit) and UnitIsPlayer(unit) and UnitIsVisible(unit) then
        NotifyInspect(unit)
        if showDebug then
            print("|cFF00FF00[Duel Analyzer]|r DEBUG - Inspecting " .. unitName .. "'s equipment")
        end
    elseif showDebug then
        print("|cFF00FF00[Duel Analyzer]|r DEBUG - Using visible equipment data for " .. unitName)
    end
    
    -- Loop through equipped items for detailed analysis
    if showDebug then
        print("|cFF00FF00[Duel Analyzer]|r DEBUG - Equipped items:")
    end
    
    for i = 1, 18 do
        if i ~= 4 then  -- Skip shirt slot
            local itemLink = GetInventoryItemLink(unit, i)
            if itemLink then
                -- Get basic item info
                local itemID, itemName, _, itemLevel = GetItemInfo(itemLink)
                
                -- Make sure itemName is valid
                itemName = itemName or "Unknown Item"
                itemLevel = itemLevel or 0
                
                -- Print item details only for target
                if showDebug then
                    print("|cFF00FF00[Duel Analyzer]|r DEBUG - " .. slotNames[i] .. ": " .. 
                        itemName .. " (iLvl " .. itemLevel .. ")")
                end
                
                if itemLevel and itemLevel > 0 then
                    -- Apply slot weighting
                    local weight = slotWeights[i] or 1.0
                    totalIlvl = totalIlvl + (itemLevel * weight)
                    itemCount = itemCount + weight
                    
                    -- Check for set items (Tier 15, Tier 16)
                    local _, _, _, _, _, _, _, _, equipSlot = GetItemInfo(itemLink)
                    if equipSlot == "INVTYPE_CHEST" or equipSlot == "INVTYPE_HEAD" or 
                       equipSlot == "INVTYPE_SHOULDER" or equipSlot == "INVTYPE_LEGS" or 
                       equipSlot == "INVTYPE_HAND" then
                        -- This is approximated for MoP - in a real addon you'd check item IDs
                        if itemName then
                            -- Check Tier 15 pieces (Throne of Thunder)
                            if itemName:find("Lightning") or itemName:find("Fire") or 
                               itemName:find("of the Haunted Forest") or itemName:find("Keeper") or 
                               itemName:find("Plate of") or itemName:find("Battlegear") then
                                tier15Count = tier15Count + 1
                                if showDebug then
                                    print("|cFF00FF00[Duel Analyzer]|r DEBUG - Found Tier 15 piece: " .. itemName)
                                end
                            end
                            
                            -- Check Tier 16 pieces (Siege of Orgrimmar)
                            if itemName:find("Celestial") or itemName:find("Cyclopean") or 
                               itemName:find("Veil of") or itemName:find("Chronomancer") or 
                               itemName:find("Plate of") or itemName:find("Headguard") then
                                tier16Count = tier16Count + 1
                                if showDebug then
                                    print("|cFF00FF00[Duel Analyzer]|r DEBUG - Found Tier 16 piece: " .. itemName)
                                end
                            end
                        end
                    end
                    
                    -- Check for legendary cloak
                    if i == 15 then -- Back slot
                        if itemName and (itemName:find("Xuen") or itemName:find("Jina") or 
                                        itemName:find("Gong") or itemName:find("Fenyu")) then
                            legendaryCloak = true
                            if showDebug then
                                print("|cFF00FF00[Duel Analyzer]|r DEBUG - Found legendary cloak: " .. itemName)
                            end
                        end
                    end
                    
                    -- Store weapon info for later analysis
                    if i == 16 or i == 17 then -- Main hand or off hand
                        table.insert(weapons, {slot = i, link = itemLink, ilvl = itemLevel, name = itemName})
                    end
                    
                    -- Store trinket info for later analysis
                    if i == 13 or i == 14 then -- Trinkets
                        table.insert(trinkets, {slot = i, link = itemLink, ilvl = itemLevel, name = itemName})
                        
                        -- Look for PvP trinkets
                        if itemName and (itemName:find("Insignia") or itemName:find("Medallion") or 
                                       itemName:find("Emblem") or itemName:find("Badge")) then
                            if showDebug then
                                print("|cFF00FF00[Duel Analyzer]|r DEBUG - Found PvP trinket: " .. itemName)
                            end
                        end
                    end
                end
            elseif showDebug then
                print("|cFF00FF00[Duel Analyzer]|r DEBUG - " .. slotNames[i] .. ": Empty")
            end
        end
    end
    
    -- Calculate base gear score
    local baseScore = 0
    if itemCount > 0 then
        baseScore = math.floor(totalIlvl / itemCount)
    end
    
    if showDebug then
        print("|cFF00FF00[Duel Analyzer]|r DEBUG - Base gear score: " .. baseScore)
    end
    
    -- Calculate final score with modifiers
    local finalScore = baseScore
    
    -- Apply level advantage/disadvantage
    if levelDifference ~= 0 then
        local levelModifier = math.min(math.abs(levelDifference) * 5, 25) -- 5 points per level, max 25
        if levelDifference > 0 then
            finalScore = finalScore + levelModifier
            if showDebug then
                print("|cFF00FF00[Duel Analyzer]|r DEBUG - Level advantage bonus: +" .. levelModifier)
            end
        else
            finalScore = finalScore - levelModifier
            if showDebug then
                print("|cFF00FF00[Duel Analyzer]|r DEBUG - Level disadvantage penalty: -" .. levelModifier)
            end
        end
    end
    
    -- Apply set bonuses
    if tier15Count >= 2 then
        finalScore = finalScore + 5  -- 2-piece bonus
        if showDebug then
            print("|cFF00FF00[Duel Analyzer]|r DEBUG - Tier 15 2-piece bonus: +5")
        end
    end
    if tier15Count >= 4 then
        finalScore = finalScore + 10 -- 4-piece bonus
        if showDebug then
            print("|cFF00FF00[Duel Analyzer]|r DEBUG - Tier 15 4-piece bonus: +10")
        end
    end
    
    if tier16Count >= 2 then
        finalScore = finalScore + 8  -- 2-piece bonus (better than tier 15)
        if showDebug then
            print("|cFF00FF00[Duel Analyzer]|r DEBUG - Tier 16 2-piece bonus: +8")
        end
    end
    if tier16Count >= 4 then
        finalScore = finalScore + 15 -- 4-piece bonus (better than tier 15)
        if showDebug then
            print("|cFF00FF00[Duel Analyzer]|r DEBUG - Tier 16 4-piece bonus: +15")
        end
    end
    
    -- Apply legendary bonuses
    if legendaryCloak then
        finalScore = finalScore + 20
        if showDebug then
            print("|cFF00FF00[Duel Analyzer]|r DEBUG - Legendary cloak bonus: +20")
        end
    end
    
    if legendaryMeta then
        finalScore = finalScore + 15
        if showDebug then
            print("|cFF00FF00[Duel Analyzer]|r DEBUG - Legendary meta gem bonus: +15")
        end
    end
    
    -- Check for PvP trinket
    local hasPvPTrinket = false
    for _, trinket in ipairs(trinkets) do
        if trinket.name and (trinket.name:find("Insignia") or trinket.name:find("Medallion") or 
                         trinket.name:find("Emblem") or trinket.name:find("Badge")) then
            hasPvPTrinket = true
            break
        end
    end
    
    -- Apply PvP trinket bonus
    if hasPvPTrinket then
        finalScore = finalScore + 15
        if showDebug then
            print("|cFF00FF00[Duel Analyzer]|r DEBUG - PvP trinket bonus: +15")
        end
    end
    
    -- Store detailed info for win calculation
    self.equipmentDetails = {
        baseScore = baseScore,
        finalScore = finalScore,
        pvpPower = pvpPower,
        resilience = resilience,
        tier15Count = tier15Count,
        tier16Count = tier16Count,
        legendaryCloak = legendaryCloak,
        hasPvPTrinket = hasPvPTrinket,
        levelDifference = levelDifference
    }
    
    if showDebug then
        print("|cFF00FF00[Duel Analyzer]|r DEBUG - Final gear score: " .. finalScore)
    end
    
    return finalScore
end

-- Calculate modifier based on duel history
function DuelAnalyzer:CalculateHistoryModifier(opponentName, opponentClass, opponentSpec)
    -- Check if we have history with this player
    if not duelHistory[opponentName] then
        return 0
    end
    
    local history = duelHistory[opponentName]
    local wins = history.wins or 0
    local losses = history.losses or 0
    
    -- If fewer than 3 duels, don't use history
    if wins + losses < 3 then
        return 0
    end
    
    -- Calculate win rate
    local winRate = wins / (wins + losses)
    
    -- Convert to a modifier between -10 and +10
    return (winRate - 0.5) * 20
end

-- Record duel results
function DuelAnalyzer:RecordDuelResult(opponentName, wasWin)
    -- Safety check
    if not opponentName then
        return
    end
    
    if not duelHistory[opponentName] then
        duelHistory[opponentName] = {
            wins = 0,
            losses = 0,
            lastDuel = time()
        }
    end
    
    if wasWin then
        duelHistory[opponentName].wins = duelHistory[opponentName].wins + 1
    else
        duelHistory[opponentName].losses = duelHistory[opponentName].losses + 1
    end
    
    duelHistory[opponentName].lastDuel = time()
    
    -- Save to persistent storage
    DuelAnalyzerDB.history = duelHistory
end

-- Create a fast version of CalculateWinChance for tooltips
-- This uses lightweight calculations for better performance
function DuelAnalyzer:QuickWinChance(unit)
    -- Check cache first
    local name = UnitName(unit)
    if self.tooltipCache[name] then
        self.tooltipCacheTime[name] = GetTime() -- Update the timestamp
        return unpack(self.tooltipCache[name])
    end
    
    -- Get player and opponent class
    local _, playerClass = UnitClass("player")
    local _, opponentClass = UnitClass(unit)
    
    -- Get base matchup chance
    local baseChance = 50
    if matchupData[playerClass] and matchupData[playerClass][opponentClass] then
        baseChance = matchupData[playerClass][opponentClass]
    end
    
    -- Calculate level advantage/disadvantage
    local playerLevel = UnitLevel("player") or 0
    local opponentLevel = UnitLevel(unit) or 0
    local levelDifference = playerLevel - opponentLevel
    
    local levelModifier = 0
    if levelDifference ~= 0 then
        -- Enhanced level difference calculation:
        -- 1-5 level difference: 3% per level
        -- 6-10 level difference: 4% per level beyond 5
        -- 10+ level difference: 5% per level beyond 10
        -- Maximum cap of 40%
        
        if levelDifference > 0 then
            -- Player has level advantage
            if levelDifference <= 5 then
                levelModifier = levelDifference * 3
            elseif levelDifference <= 10 then
                levelModifier = 15 + ((levelDifference - 5) * 4)
            else
                levelModifier = 35 + ((levelDifference - 10) * 5)
            end
            levelModifier = math.min(levelModifier, 40)
        else
            -- Opponent has level advantage
            local absDiff = math.abs(levelDifference)
            if absDiff <= 5 then
                levelModifier = -(absDiff * 3)
            elseif absDiff <= 10 then
                levelModifier = -15 - ((absDiff - 5) * 4)
            else
                levelModifier = -35 - ((absDiff - 10) * 5)
            end
            levelModifier = math.max(levelModifier, -40)
        end
    end
    -- Quick gear estimate (just compare visible items)
    local playerGearScore = 0
    local opponentGearScore = 0
    
    -- Check a few key slots for a rough estimate
    local keySlots = {1, 5, 7, 16} -- Head, Chest, Legs, Weapon
    
    for _, slot in ipairs(keySlots) do
        local playerItem = GetInventoryItemLink("player", slot)
        if playerItem then
            local _, _, _, itemLevel = GetItemInfo(playerItem)
            if itemLevel then
                playerGearScore = playerGearScore + itemLevel
            end
        end
        
        local opponentItem = GetInventoryItemLink(unit, slot)
        if opponentItem then
            local _, _, _, itemLevel = GetItemInfo(opponentItem)
            if itemLevel then
                opponentGearScore = opponentGearScore + itemLevel
            end
        end
    end
    
    -- Calculate average item level
    playerGearScore = (#keySlots > 0) and math.floor(playerGearScore / #keySlots) or 0
    opponentGearScore = (#keySlots > 0) and math.floor(opponentGearScore / #keySlots) or 0
    
    -- Calculate gear advantage
    local gearModifier = 0
    local gearDifference = playerGearScore - opponentGearScore
    
    if math.abs(gearDifference) > 10 then
        gearModifier = math.min(math.abs(gearDifference) * 0.5, 15)
        if gearDifference < 0 then
            gearModifier = -gearModifier
        end
    end
    
    -- Calculate history modifier
    -- Calculate history modifier
    local historyModifier = 0
    if duelHistory[name] then
        local history = duelHistory[name]
        local wins = history.wins or 0
        local losses = history.losses or 0
        
        if wins + losses >= 3 then
            local winRate = wins / (wins + losses)
            historyModifier = (winRate - 0.5) * 20
        end
    end
    
    -- Final calculation
    local finalChance = baseChance + levelModifier + gearModifier + historyModifier
    
    -- Ensure it's between 1-99%
    finalChance = math.max(1, math.min(99, finalChance))
    
    -- Store in cache
    self.tooltipCache[name] = {finalChance, baseChance, 0, gearModifier, historyModifier, playerGearScore, opponentGearScore}
    self.tooltipCacheTime[name] = GetTime()
    
    return finalChance, baseChance, 0, gearModifier, historyModifier, playerGearScore, opponentGearScore
end

-- Tooltip Integration for Duel Analyzer
function DuelAnalyzer:CreateScouterFrame()
    -- Main scouter frame
    local frame = CreateFrame("Frame", "DuelAnalyzerScouter", UIParent)
    frame:SetSize(225, 225)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetFrameStrata("DIALOG") -- Higher strata to ensure visibility
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()
    
    -- Background texture (DBZ Scouter)
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(true)
    -- Try to use the scouter texture
    bg:SetTexture(SCOUTER_TEXTURE)
    
    -- Check if texture loaded correctly, use fallback if not
    C_Timer.After(0.1, function()
        if not bg:GetTexture() then
            print("|cFFFF0000[Duel Analyzer]|r WARNING: Could not load scouter texture, using fallback")
            bg:SetTexture(FALLBACK_TEXTURE)
        end
    end)
    
    -- Create a semi-transparent black background for text
    local textBg = frame:CreateTexture(nil, "ARTWORK")
    textBg:SetSize(120, 80)
    textBg:SetPoint("CENTER", frame, "CENTER", 0, 0)
    textBg:SetTexture(0, 0, 0, 0.7)
    
    -- Power Level text
    local powerText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    powerText:SetPoint("CENTER", frame, "CENTER", 0, 15)
    powerText:SetText("SCANNING...")
    powerText:SetTextColor(1, 0.2, 0.2) -- Red text like in DBZ
    
    -- Name text
    local nameText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameText:SetPoint("CENTER", frame, "CENTER", 0, -10)
    nameText:SetText("")
    
    -- Create a simpler animation system that works in MoP
    -- Instead of using animation groups which seem to be causing issues
    frame.flashTimer = 0
    frame.flashState = true
    frame.flashSpeed = 0.5
    
    frame:SetScript("OnUpdate", function(self, elapsed)
        if self:IsShown() and self.scanning then
            self.flashTimer = self.flashTimer + elapsed
            if self.flashTimer > self.flashSpeed then
                self.flashTimer = 0
                self.flashState = not self.flashState
                
                if self.flashState then
                    powerText:SetAlpha(1.0)
                else
                    powerText:SetAlpha(0.3)
                end
            end
        end
    end)
    
    -- Scanning functions
    frame.StartScanning = function(self)
        self.scanning = true
        self.flashTimer = 0
        self.flashState = true
    end
    
    frame.StopScanning = function(self)
        self.scanning = false
        powerText:SetAlpha(1.0)
    end
    
    -- Close button
    local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -5)
    
    -- Sound function
    frame.PlayBeep = function()
        PlaySoundFile(BEEP_SOUND, "Master")
    end
    
    -- Store references
    frame.powerText = powerText
    frame.nameText = nameText
    
    self.scouterFrame = frame
    return frame
end

-- Calculate a power level for a unit
function DuelAnalyzer:CalculatePowerLevel(unit)
    -- Get basic information
    local opponentLevel = UnitLevel(unit) or 0
    local playerLevel = UnitLevel("player") or 0
    local levelDifference = playerLevel - opponentLevel
    local _, opponentClass = UnitClass(unit)
    
    -- Base power level on level
    local powerLevel = opponentLevel * 100
    
    -- Get gear score
    local gearScore = 0
    local itemCount = 0
    
    for i = 1, 18 do
        if i ~= 4 then -- Skip shirt
            local itemLink = GetInventoryItemLink(unit, i)
            if itemLink then
                local _, _, _, itemLevel = GetItemInfo(itemLink)
                if itemLevel then
                    gearScore = gearScore + itemLevel
                    itemCount = itemCount + 1
                end
            end
        end
    end
    
    -- Add gear score to power level
    if itemCount > 0 then
        powerLevel = powerLevel + (gearScore / itemCount) * 10
    end
    
    -- Class modifiers (some classes are stronger in DBZ terms)
    if opponentClass == "WARRIOR" then
        powerLevel = powerLevel * 1.15 -- Like Saiyans
    elseif opponentClass == "MAGE" then
        powerLevel = powerLevel * 1.1 -- Like Namekians
    elseif opponentClass == "DEATHKNIGHT" then
        powerLevel = powerLevel * 1.2 -- Like Frieza
    end
    
    -- Level difference adjustment
    if levelDifference > 0 then
        -- Target is lower level
        powerLevel = powerLevel * (1 - (levelDifference * 0.05))
    elseif levelDifference < 0 then
        -- Target is higher level
        powerLevel = powerLevel * (1 + (math.abs(levelDifference) * 0.05))
    end
    
    -- Make it interesting - random factor
    powerLevel = powerLevel * (0.9 + math.random() * 0.2)
    
    -- For strong players, possibly go over 9000
    if opponentLevel >= 90 and (itemCount > 0 and gearScore/itemCount > 450) then
        powerLevel = math.max(powerLevel, 9001)
    end
    
    return math.floor(powerLevel)
end

-- Animate the power level counting
function DuelAnalyzer:AnimatePowerLevel(targetPower, targetName)
    -- Create frame if it doesn't exist
    if not self.scouterFrame then
        self:CreateScouterFrame()
    end
    
    local frame = self.scouterFrame
    local startPower = math.min(1000, targetPower / 3) -- Start lower for dramatic effect
    local currentPower = startPower
    local countSpeed = 0.05 -- Time between updates
    local countStep = math.max(1, math.floor((targetPower - startPower) / 50)) -- Count by larger steps for higher powers
    
    -- Set initial values
    frame.nameText:SetText(targetName)
    frame.powerText:SetText("SCANNING")
    
    -- Start scanning animation
    frame:StartScanning()
    
    -- Show the frame
    frame:Show()
    
    -- Play beep sound
    frame:PlayBeep()
    
    -- Schedule power level reveal
    C_Timer.After(2.5, function()
        -- Stop scanning animation
        frame:StopScanning()
        
        -- Initial power level
        frame.powerText:SetText(math.floor(startPower))
        
        -- Create timer for updating the counter
        local countTimer = C_Timer.NewTicker(countSpeed, function(self)
            -- Update power level
            currentPower = currentPower + countStep
            
            -- Play beep sound occasionally
            if math.random(1, 3) == 1 then
                frame:PlayBeep()
            end
            
            -- Check if we're done
            if currentPower >= targetPower then
                currentPower = targetPower
                self:Cancel()
                
                -- Set final power level color based on value
                if targetPower > 9000 then
                    frame.powerText:SetTextColor(1, 0, 0) -- Red
                    frame.powerText:SetText("OVER 9000!")
                    PlaySoundFile(LEVEL_UP_SOUND, "Master")
                elseif targetPower > 5000 then
                    frame.powerText:SetTextColor(1, 0.5, 0) -- Orange
                    frame.powerText:SetText(targetPower)
                else
                    frame.powerText:SetTextColor(0, 1, 0) -- Green
                    frame.powerText:SetText(targetPower)
                end
                
                -- Add close timer
                C_Timer.After(5, function()
                    frame:Hide()
                end)
            else
                -- Update displayed power
                frame.powerText:SetText(math.floor(currentPower))
            end
        end)
    end)
end

-- Show scouter for a unit
function DuelAnalyzer:ShowScouter(unit)
    if not unit or not UnitIsPlayer(unit) then return end
    
    local name = UnitName(unit)
    if not name then return end
    
    -- Calculate power level
    local powerLevel = self:CalculatePowerLevel(unit)
    
    -- Show scouter animation
    self:AnimatePowerLevel(powerLevel, name)
end

-- AnalyzeTooltipUnit function with DBZ Scouter style
function DuelAnalyzer:AnalyzeTooltipUnit(unit)
    -- Don't analyze non-players or yourself
    if not unit or not UnitIsPlayer(unit) or UnitIsUnit(unit, "player") then return end
    
    -- Get opponent name
    local name = UnitName(unit)
    if not name then return end
    
    -- Store reference to current unit for click detection
    self.currentTooltipUnit = unit
    
    -- Check if DBZ Scouter style is enabled
    if DuelAnalyzerDB and DuelAnalyzerDB.settings and DuelAnalyzerDB.settings.scouterStyle then
        -- DBZ Scouter Style
        self:AddScouterTooltip(unit)
    else
        -- Regular Style
        self:AddRegularTooltip(unit)
    end
end

-- Function for regular tooltip style
function DuelAnalyzer:AddRegularTooltip(unit)
    local name = UnitName(unit)
    
    -- Get quick win chance calculation
    local winChance, baseChance, specMod, gearMod, historyMod = self:QuickWinChance(unit)
    
    -- Format text color for win chance
    local chanceColor = "FFFFFF"
    if winChance >= 70 then
        chanceColor = "00FF00" -- Green for good chance
    elseif winChance >= 40 then
        chanceColor = "FFFF00" -- Yellow for medium chance
    else
        chanceColor = "FF0000" -- Red for poor chance
    end
    
    -- Add tooltip lines
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("|cFF00FF00[Duel Analyzer]|r")
    GameTooltip:AddLine("Win Chance: |cff" .. chanceColor .. winChance .. "%|r")
    
    -- Add history if available
    if duelHistory and duelHistory[name] then
        local history = duelHistory[name]
        local wins = history.wins or 0
        local losses = history.losses or 0
        
        if wins + losses > 0 then
            local winRate = math.floor((wins / (wins + losses)) * 100)
            local historyColor = "FFFFFF"
            
            if winRate > 60 then historyColor = "00FF00"
            elseif winRate < 40 then historyColor = "FF0000"
            end
            
            GameTooltip:AddLine("History: |cff" .. historyColor .. wins .. "-" .. losses .. " (" .. winRate .. "%)|r")
        end
    end
end

-- Function for DBZ Scouter tooltip style
function DuelAnalyzer:AddScouterTooltip(unit)
    local name = UnitName(unit)
    
    -- Get quick win chance
    local winChance = select(1, self:QuickWinChance(unit))
    
    -- Calculate Power Level (based on gear and level)
    local powerLevel = self:CalculatePowerLevel(unit)
    
    -- Format text color for win chance
    local chanceColor = "FFFFFF"
    if winChance >= 70 then
        chanceColor = "00FF00" -- Green for good chance
    elseif winChance >= 40 then
        chanceColor = "FFFF00" -- Yellow for medium chance
    else
        chanceColor = "FF0000" -- Red for poor chance
    end
    
    -- Add tooltip lines in DBZ Scouter style
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("|cFFFF6600Click to scan with DBZ Scouter!|r")
    
    -- Add the "Power Level" line
    if powerLevel > 9000 then
        GameTooltip:AddLine("Power Level: |cFFFF0000OVER 9000!|r")
    else
        GameTooltip:AddLine("Power Level: |cFFFF6600" .. powerLevel .. "|r")
    end
    
    -- Add win chance as "Battle Prediction"
    GameTooltip:AddLine("Battle Prediction: |cff" .. chanceColor .. winChance .. "% Victory Chance|r")
end

-- Clear current tooltip unit when tooltip hides
GameTooltip:HookScript("OnHide", function()
    DuelAnalyzer.currentTooltipUnit = nil
end)

-- Make the tooltip clickable with a frame overlay
local tooltipFrame = CreateFrame("Frame", "DuelAnalyzerTooltipFrame")
tooltipFrame:EnableMouse(true)
tooltipFrame:SetScript("OnMouseDown", function(self, button)
    if button == "LeftButton" and DuelAnalyzer.currentTooltipUnit then
        -- Show scouter for current tooltip unit
        DuelAnalyzer:ShowScouter(DuelAnalyzer.currentTooltipUnit)
        -- Hide tooltip
        GameTooltip:Hide()
    end
end)





-- Debug function to test if the scouter is working properly
function DuelAnalyzer:DebugScouter()
    print("|cFF00FF00[Duel Analyzer]|r Starting scouter debug test...")
    
    -- Check if scouter.tga exists by trying to create a texture
    local texturePath = "Interface\\AddOns\\DuelAnalyzer\\scouter.tga"
    local testTexture = UIParent:CreateTexture(nil, "ARTWORK")
    testTexture:SetTexture(texturePath)
    
    -- Short delay to let texture load
    C_Timer.After(0.5, function()
        -- Check if texture loaded
        if testTexture:GetTexture() then
            print("|cFF00FF00[Duel Analyzer]|r Scouter texture found at: " .. texturePath)
        else
            print("|cFFFF0000[Duel Analyzer]|r Scouter texture NOT found at: " .. texturePath)
            print("|cFFFF0000[Duel Analyzer]|r Make sure you have a file named 'scouter.tga' in your DuelAnalyzer folder")
            print("|cFFFF0000[Duel Analyzer]|r Will use fallback texture instead")
        end
        
        -- Clean up test texture
        testTexture:SetTexture(nil)
        
        -- Create the scouter frame if it doesn't exist
        if not self.scouterFrame then
            print("|cFF00FF00[Duel Analyzer]|r Creating scouter frame...")
            self:CreateScouterFrame()
        else
            print("|cFF00FF00[Duel Analyzer]|r Scouter frame already exists")
        end
        
        -- Display a test scouter
        print("|cFF00FF00[Duel Analyzer]|r Displaying test scouter...")
        self:AnimatePowerLevel(8500, "Debug Test")
    end)
    
    return true
end

-- Simplified tooltip click detection
GameTooltip:HookScript("OnMouseDown", function(self, button)
    if button == "LeftButton" and DuelAnalyzer.currentTooltipUnit then
        -- Show scouter for current tooltip unit
        DuelAnalyzer:ShowScouter(DuelAnalyzer.currentTooltipUnit)
        -- Hide tooltip
        self:Hide()
    end
end)



-- Add slash command for testing the scouter
SLASH_SCOUTERTEST1 = "/scoutertest"
SlashCmdList["SCOUTERTEST"] = function(msg)
    DuelAnalyzer:DebugScouter()
end

-- Slash command handler
SLASH_DUELANALYZER1 = "/danalyzer"
SLASH_DUELANALYZER2 = "/duelanalyzer"
SlashCmdList["DUELANALYZER"] = function(msg)
    local command, rest = msg:match("^(%S*)%s*(.-)$")
    command = command:lower()
    
    if command == "show" then
        DuelAnalyzerDB.settings.showWindow = true
        print("|cFF00FF00[Duel Analyzer]|r Window will be shown for duels")
    elseif command == "hide" then
        DuelAnalyzerDB.settings.showWindow = false
        print("|cFF00FF00[Duel Analyzer]|r Window will be hidden for duels")
    elseif command == "chat" then
        DuelAnalyzerDB.settings.showChatMessage = not DuelAnalyzerDB.settings.showChatMessage
        print("|cFF00FF00[Duel Analyzer]|r Chat messages " .. (DuelAnalyzerDB.settings.showChatMessage and "enabled" or "disabled"))
    elseif command == "track" then
        DuelAnalyzerDB.settings.trackHistory = not DuelAnalyzerDB.settings.trackHistory
        print("|cFF00FF00[Duel Analyzer]|r History tracking " .. (DuelAnalyzerDB.settings.trackHistory and "enabled" or "disabled"))
    elseif command == "reset" then
        DuelAnalyzerDB.history = {}
        duelHistory = {}
        print("|cFF00FF00[Duel Analyzer]|r Duel history has been reset")
    elseif command == "tooltip" then
        if not DuelAnalyzerDB.settings.showTooltip then
            DuelAnalyzerDB.settings.showTooltip = true
            print("|cFF00FF00[Duel Analyzer]|r Tooltips enabled")
        else
            DuelAnalyzerDB.settings.showTooltip = false
            print("|cFF00FF00[Duel Analyzer]|r Tooltips disabled")
        end
    elseif command == "scouter" then
        -- Toggle scouter style
        if not DuelAnalyzerDB.settings.scouterStyle then
            DuelAnalyzerDB.settings.scouterStyle = true
            print("|cFF00FF00[Duel Analyzer]|r Scouter style enabled! It's over 9000!")
            
            -- Show a test scouter
            DuelAnalyzer:AnimatePowerLevel(9001, "Test Scouter")
        else
            DuelAnalyzerDB.settings.scouterStyle = false
            print("|cFF00FF00[Duel Analyzer]|r Scouter style disabled")
        end
    elseif command == "scan" and UnitExists("target") then
        -- Added direct command to scan current target
        local name = UnitName("target")
        if name then
            local powerLevel = DuelAnalyzer:CalculatePowerLevel("target")
            DuelAnalyzer:AnimatePowerLevel(powerLevel, name)
        end
    elseif command == "analyze" and rest ~= "" then
        -- Manual analysis of a specific player
        local targetName = rest
        if UnitExists(targetName) then
            DuelAnalyzer:AnalyzeOpponent(targetName)
        else
            print("|cFF00FF00[Duel Analyzer]|r Player not found. Try targeting them first.")
        end
    elseif command == "analyze" or command == "" then
        -- Analyze current target or last duel request
        if UnitExists("target") and UnitIsPlayer("target") then
            local targetName = UnitName("target")
            print("|cFF00FF00[Duel Analyzer]|r Analyzing current target: " .. targetName)
            DuelAnalyzer:AnalyzeOpponent(targetName)
        elseif DuelAnalyzer.lastDuelRequest then
            print("|cFF00FF00[Duel Analyzer]|r Please target " .. DuelAnalyzer.lastDuelRequest .. " first")
        else
            print("|cFF00FF00[Duel Analyzer]|r No target selected. Please target a player first.")
        end
    else
        -- Show help
        print("|cFF00FF00Duel Analyzer Commands:|r")
        print("/danalyzer - Analyze your current target")
        print("/danalyzer analyze - Analyze your current target")
        print("/danalyzer analyze [name] - Analyze a specific player")
        print("/danalyzer show - Show the analyzer window for duels")
        print("/danalyzer hide - Hide the analyzer window for duels")
        print("/danalyzer chat - Toggle chat messages")
        print("/danalyzer track - Toggle history tracking")
        print("/danalyzer tooltip - Toggle tooltips")
        print("/danalyzer reset - Reset all duel history")
        print("/danalyzer scouter - Toggle DBZ Scouter style")
        print("/danalyzer scan - Scan current target with DBZ Scouter")
        print("/scoutertest - Test the DBZ Scouter functionality")
    end
end

-- CLEAN SINGLE TOOLTIP IMPLEMENTATION
-- Variable to track if we've already processed this tooltip
DuelAnalyzer.processedTooltip = nil

-- Single tooltip hook
GameTooltip:HookScript("OnTooltipSetUnit", function(self)
    local _, unit = self:GetUnit()
    
    -- Only process if tooltips are enabled
    if not (unit and DuelAnalyzerDB and DuelAnalyzerDB.settings and DuelAnalyzerDB.settings.showTooltip) then
        return
    end
    
    -- Don't analyze non-players or yourself
    if not UnitIsPlayer(unit) or UnitIsUnit(unit, "player") then
        return
    end

    -- Check if this is the same unit we already processed
    if DuelAnalyzer.processedTooltip == unit then
        return
    end
    
    -- Mark as processed
    DuelAnalyzer.processedTooltip = unit
    DuelAnalyzer.currentTooltipUnit = unit
    
    -- Reset when the tooltip hides
    self:HookScript("OnHide", function()
        DuelAnalyzer.processedTooltip = nil
        DuelAnalyzer.currentTooltipUnit = nil
    end)
    
    -- Make tooltip clickable
    self:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" and DuelAnalyzer.currentTooltipUnit then
            DuelAnalyzer:ShowScouter(DuelAnalyzer.currentTooltipUnit)
            self:Hide()
        end
    end)
    
    -- Calculate win chance
    local name = UnitName(unit)
    local winChance = select(1, DuelAnalyzer:QuickWinChance(unit))
    
    -- Format text color for win chance
    local chanceColor = "FFFFFF"
    if winChance >= 70 then
        chanceColor = "00FF00" -- Green for good chance
    elseif winChance >= 40 then
        chanceColor = "FFFF00" -- Yellow for medium chance
    else
        chanceColor = "FF0000" -- Red for poor chance
    end
    
    -- Check if DBZ Scouter style is enabled
    if DuelAnalyzerDB.settings.scouterStyle then
        -- Calculate Power Level
        local powerLevel = DuelAnalyzer:CalculatePowerLevel(unit)
        
        -- Add DBZ Scouter style
        self:AddLine(" ")
        self:AddLine("|cFFFF6600Click to scan with DBZ Scouter!|r")
        
        -- Add the "Power Level" line
        if powerLevel > 9000 then
            self:AddLine("Power Level: |cFFFF0000OVER 9000!|r")
        else
            self:AddLine("Power Level: |cFFFF6600" .. powerLevel .. "|r")
        end
        
        -- Add win chance as "Battle Prediction"
        self:AddLine("Battle Prediction: |cff" .. chanceColor .. winChance .. "% Victory Chance|r")
    else
        -- Regular style
        self:AddLine(" ")
        self:AddLine("|cFF00FF00[Duel Analyzer]|r")
        self:AddLine("Win Chance: |cff" .. chanceColor .. winChance .. "%|r")
        
        -- Add history if available
        if duelHistory and duelHistory[name] then
            local history = duelHistory[name]
            local wins = history.wins or 0
            local losses = history.losses or 0
            
            if wins + losses > 0 then
                local winRate = math.floor((wins / (wins + losses)) * 100)
                local historyColor = "FFFFFF"
                
                if winRate > 60 then historyColor = "00FF00"
                elseif winRate < 40 then historyColor = "FF0000"
                end
                
                self:AddLine("History: |cff" .. historyColor .. wins .. "-" .. losses .. " (" .. winRate .. "%)|r")
            end
        end
    end
end)

-- Initialize the addon
DuelAnalyzer:OnLoad()
