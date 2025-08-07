local ADDON_NAME, ns = ...

local frame = ns.frame
local header1, body1 = ns.header1, ns.body1
local header2, body2 = ns.header2, ns.body2
local header3, body3 = ns.header3, ns.body3

-- state
local tracked = {}
local inCombat = false
local elapsedSinceCheck = 0
local playerName = UnitName("player")
local lastLostTagged = {}
local isInInstance = false

local function isEnemyUnit(unit)
  return UnitCanAttack("player", unit) and not UnitIsDead(unit)
end

local function groupUnitIterator()
  local n, isRaid = GetNumGroupMembers(), IsInRaid()
  if n == 0 then return function() return nil end end
  local i = 0
  return function()
    i = i + 1
    if i > n then return nil end
    if isRaid then
      return ("raid%d"):format(i)
    else
      if i == 1 then
        return "player"
      else
        return ("party%d"):format(i-1)
      end
    end
  end
end

local function unitHasAggroOnMob(unit, mob)
  local s = UnitThreatSituation(unit, mob)
  return s == 3
end

local function scanThreat()
  if not inCombat then
    frame:Hide()
    return
  end
  if not ns.SHOW_IN_WORLD and not isInInstance then
    frame:Hide()
    return
  end
  frame:Show()

  local haveAggro, lostAggro, groupHolders = {}, {}, {}
  local holderLists = {}
  local lostCount, insecureCount = 0, 0
  local newLossHappened = false

  for unit in pairs(tracked) do
    if UnitExists(unit) and isEnemyUnit(unit) and UnitAffectingCombat(unit) then
      local mobName = UnitName(unit) or "Unknown"
      local playerThreat = UnitThreatSituation("player", unit)

      if playerThreat == 3 then
        table.insert(haveAggro, mobName)
      else
        if playerThreat == 2 or playerThreat == 1 then
          insecureCount = insecureCount + 1
        end
        local holder = nil
        if unitHasAggroOnMob("player", unit) then
          holder = playerName
        else
          for gunit in groupUnitIterator() do
            if UnitExists(gunit) and unitHasAggroOnMob(gunit, unit) then
              holder = UnitName(gunit)
              break
            end
          end
        end
        if holder and holder ~= playerName then
          lostCount = lostCount + 1
          table.insert(lostAggro, ("%s -> %s"):format(mobName, holder))
          if not lastLostTagged[UnitGUID(unit) or mobName] then
            newLossHappened = true
          end
          lastLostTagged[UnitGUID(unit) or mobName] = holder
        else
          if playerThreat == nil or playerThreat == 0 then
            lostCount = lostCount + 1
            table.insert(lostAggro, ("%s -> ?"):format(mobName))
            if not lastLostTagged[UnitGUID(unit) or mobName] then
              newLossHappened = true
            end
            lastLostTagged[UnitGUID(unit) or mobName] = "?"
          end
        end
        if holder then
          holderLists[holder] = holderLists[holder] or {}
          table.insert(holderLists[holder], mobName)
        end
      end
    end
  end

  for name, mobs in pairs(holderLists) do
    table.sort(mobs)
    table.insert(groupHolders, ("%s: %s"):format(name, table.concat(mobs, ", ")))
  end
  table.sort(haveAggro)
  table.sort(lostAggro)
  table.sort(groupHolders)

  if newLossHappened then
    PlaySound(ns.SOUND_ON_LOSS, "Master")
  end

  if lostCount > 0 then
    ns.setBackdropColor(0.8, 0.1, 0.1)
  elseif insecureCount > 0 then
    ns.setBackdropColor(0.9, 0.7, 0.1)
  else
    ns.setBackdropColor(0.1, 0.6, 0.1)
  end

  ns.setHeaderCount(header1, "I have aggro", #haveAggro, {0.05,0.35,0.05})
  ns.setHeaderCount(header2, "Lost aggro", lostCount, {0.35,0.05,0.05})
  ns.setHeaderCount(header3, "Group aggro", #groupHolders, {0.1,0.1,0.3})

  ns.fillLines(body1, haveAggro)
  ns.fillLines(body2, lostAggro)
  ns.fillLines(body3, groupHolders)

  ns.resizeFrame()
end

frame:SetScript("OnEvent", function(_, event, arg1)
  if event == "PLAYER_REGEN_DISABLED" then
    inCombat = true
    wipe(lastLostTagged)
    frame:Show()
    scanThreat()
  elseif event == "PLAYER_REGEN_ENABLED" then
    inCombat = false
    wipe(lastLostTagged)
    frame:Hide()
  elseif event == "NAME_PLATE_UNIT_ADDED" then
    if UnitCanAttack("player", arg1) then
      tracked[arg1] = true
    end
  elseif event == "NAME_PLATE_UNIT_REMOVED" then
    tracked[arg1] = nil
    lastLostTagged[UnitGUID(arg1) or (UnitName(arg1) or arg1)] = nil
  elseif event == "UNIT_THREAT_LIST_UPDATE" or event == "UNIT_THREAT_SITUATION_UPDATE" then
    scanThreat()
  elseif event == "PLAYER_TARGET_CHANGED" then
    scanThreat()
  elseif event == "GROUP_ROSTER_UPDATE" or event == "ZONE_CHANGED_NEW_AREA" then
    local _, instanceType = IsInInstance()
    isInInstance = (instanceType ~= "none")
    scanThreat()
  end
end)

frame:SetScript("OnUpdate", function(_, elapsed)
  if not inCombat then return end
  elapsedSinceCheck = elapsedSinceCheck + elapsed
  if elapsedSinceCheck >= ns.POLL_INTERVAL then
    elapsedSinceCheck = 0
    scanThreat()
  end
end)

frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
frame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
frame:RegisterEvent("UNIT_THREAT_LIST_UPDATE")
frame:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE")
frame:RegisterEvent("PLAYER_TARGET_CHANGED")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")

frame:Hide()
local ADDON_NAME = ...
local f = CreateFrame("Frame", "TankAggroAlertFrame", UIParent)

-- ====== Config ======
local POLL_INTERVAL = 0.2
local SHOW_IN_WORLD = true          -- set false if you only want in instances
local SOUND_ON_LOSS = SOUNDKIT.RAID_WARNING

-- ====== UI ======
f:SetSize(300, 220)
f:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
f.bg = f:CreateTexture(nil, "BACKGROUND")
f.bg:SetAllPoints()
f.bg:SetColorTexture(0, 0, 0, 0.4)

f:EnableMouse(true)
f:SetMovable(true)
f:RegisterForDrag("LeftButton")
f:SetScript("OnDragStart", f.StartMoving)
f:SetScript("OnDragStop", f.StopMovingOrSizing)

local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
title:SetPoint("TOP", 0, -6)
title:SetText("Tank Aggro")

local function newSection(parent, label, yOff)
  local header = CreateFrame("Button", nil, parent)
  header:SetPoint("TOPLEFT", 8, yOff)
  header:SetSize(284, 22)

  header.bg = header:CreateTexture(nil, "ARTWORK")
  header.bg:SetAllPoints()
  header.bg:SetColorTexture(0.1, 0.1, 0.1, 0.6)

  header.text = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  header.text:SetPoint("LEFT", 8, 0)
  header.text:SetText(label)

  header.arrow = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  header.arrow:SetPoint("RIGHT", -8, 0)
  header.arrow:SetText("▲")

  local body = CreateFrame("Frame", nil, parent)
  body:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
  body:SetSize(284, 1) -- height dynamic

  local lines = {}
  for i=1, 10 do
    local fs = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", 10, -((i-1)*14))
    fs:SetJustifyH("LEFT")
    fs:SetWidth(264)
    fs:SetText("")
    lines[i] = fs
  end
  body.lines = lines
  body.maxLines = #lines
  body:Hide()

  header.collapsed = true
  header:SetScript("OnClick", function()
    header.collapsed = not header.collapsed
    if header.collapsed then
      body:Hide()
      header.arrow:SetText("▼")
    else
      body:Show()
      header.arrow:SetText("▲")
    end
  end)
  header.arrow:SetText("▼")

  return header, body
end

-- Sections: I have aggro, I lost aggro, Group holders
local header1, body1 = newSection(f, "I have aggro (0)", -28)
local header2, body2 = newSection(f, "Lost aggro (0)", -28 - 22 - 4)
local header3, body3 = newSection(f, "Group aggro (0)", -28 - (22+4)*2)

-- Resize frame to fit sections if expanded
local function resizeFrame()
  local h = 40
  local function bodyHeight(body)
    if not body:IsShown() then return 0 end
    -- find last non-empty line
    local last = 0
    for i=body.maxLines,1,-1 do
      if body.lines[i]:GetText() and body.lines[i]:GetText() ~= "" then last = i break end
    end
    return (last>0) and (last*14 + 4) or 0
  end
  h = h + 22 + 4 + bodyHeight(body1)
  h = h + 22 + 4 + bodyHeight(body2)
  h = h + 22 + 6 + bodyHeight(body3)
  f:SetHeight(h)
end

local function setHeaderCount(header, label, n, color)
  header.text:SetText(("%s (%d)"):format(label, n))
  if color then
    header.bg:SetColorTexture(color[1], color[2], color[3], 0.7)
  end
end

local function setBackdropColor(r,g,b)
  f.bg:SetColorTexture(r, g, b, 0.4)
end

-- ====== State ======
local tracked = {} -- [unitToken] = true for visible enemy nameplates
local inCombat = false
local elapsedSinceCheck = 0
local playerName = UnitName("player")
local lastLostTagged = {} -- mobGUID => who took it (to detect new losses)
local isInInstance = false

-- ====== Helpers ======
local function isEnemyUnit(unit)
  return UnitCanAttack("player", unit) and not UnitIsDead(unit)
end

local function groupUnitIterator()
  local n, isRaid = GetNumGroupMembers(), IsInRaid()
  if n == 0 then
    return function() return nil end
  end
  local i = 0
  return function()
    i = i + 1
    if i > n then return nil end
    if isRaid then
      return ("raid%d"):format(i)
    else
      -- parties don't include player in the count from GetNumGroupMembers() in some variants; include player explicitly
      if i == 1 then
        return "player"
      else
        return ("party%d"):format(i-1)
      end
    end
  end
end

local function unitHasAggroOnMob(unit, mob)
  local s = UnitThreatSituation(unit, mob)
  return s == 3
end

local function fillLines(body, lines)
  -- lines: array of strings to show
  for i=1, body.maxLines do
    local text = lines[i]
    body.lines[i]:SetText(text or "")
  end
end

-- ====== Core scan ======
local function scanThreat()
  if not inCombat then
    f:Hide()
    return
  end
  if not SHOW_IN_WORLD and not isInInstance then
    f:Hide()
    return
  end
  f:Show()

  local haveAggro = {}   -- strings
  local lostAggro = {}   -- strings like "Mob -> Name"
  local groupHolders = {} -- strings like "Name: Mob1, Mob2"
  local holderLists = {}  -- name -> {mob names}

  local lostCount = 0
  local insecureCount = 0
  local newLossHappened = false

  for unit in pairs(tracked) do
    if UnitExists(unit) and isEnemyUnit(unit) and UnitAffectingCombat(unit) then
      local mobName = UnitName(unit) or "Unknown"
      local playerThreat = UnitThreatSituation("player", unit)

      if playerThreat == 3 then
        table.insert(haveAggro, mobName)
      else
        if playerThreat == 2 or playerThreat == 1 then
          insecureCount = insecureCount + 1
        end
        -- find which group member (including player/pet) actually has aggro
        local holder = nil
        -- check player first for completeness
        if unitHasAggroOnMob("player", unit) then
          holder = playerName
        else
          for gunit in groupUnitIterator() do
            if UnitExists(gunit) and unitHasAggroOnMob(gunit, unit) then
              holder = UnitName(gunit)
              break
            end
          end
        end

        if holder and holder ~= playerName then
          lostCount = lostCount + 1
          table.insert(lostAggro, ("%s -> %s"):format(mobName, holder))
          if not lastLostTagged[UnitGUID(unit) or mobName] then
            newLossHappened = true
          end
          lastLostTagged[UnitGUID(unit) or mobName] = holder
        else
          -- not sure who has aggro (maybe another non-group unit, pet, or threat reset)
          -- still counts as lost aggro if we don't have it
          if playerThreat == nil or playerThreat == 0 then
            lostCount = lostCount + 1
            table.insert(lostAggro, ("%s -> ?"):format(mobName))
            if not lastLostTagged[UnitGUID(unit) or mobName] then
              newLossHappened = true
            end
            lastLostTagged[UnitGUID(unit) or mobName] = "?"
          end
        end

        -- build group holder lists
        if holder then
          holderLists[holder] = holderLists[holder] or {}
          table.insert(holderLists[holder], mobName)
        end
      end
    end
  end

  -- make group holder display
  for name, mobs in pairs(holderLists) do
    table.sort(mobs)
    table.insert(groupHolders, ("%s: %s"):format(name, table.concat(mobs, ", ")))
  end
  table.sort(haveAggro)
  table.sort(lostAggro)
  table.sort(groupHolders)

  -- Alerts + colors
  if newLossHappened then
    PlaySound(SOUND_ON_LOSS, "Master")
  end

  if lostCount > 0 then
    setBackdropColor(0.8, 0.1, 0.1) -- red
  elseif insecureCount > 0 then
    setBackdropColor(0.9, 0.7, 0.1) -- yellow
  else
    setBackdropColor(0.1, 0.6, 0.1) -- green
  end

  -- Update headers
  setHeaderCount(header1, "I have aggro", #haveAggro, {0.05,0.35,0.05})
  setHeaderCount(header2, "Lost aggro", lostCount, {0.35,0.05,0.05})
  setHeaderCount(header3, "Group aggro", #groupHolders, {0.1,0.1,0.3})

  -- Fill bodies
  fillLines(body1, haveAggro)
  fillLines(body2, lostAggro)
  fillLines(body3, groupHolders)

  resizeFrame()
end

-- ====== Events ======
f:SetScript("OnEvent", function(_, event, arg1)
  if event == "PLAYER_REGEN_DISABLED" then
    inCombat = true
    wipe(lastLostTagged)
    f:Show()
    scanThreat()
  elseif event == "PLAYER_REGEN_ENABLED" then
    inCombat = false
    wipe(lastLostTagged)
    f:Hide()
  elseif event == "NAME_PLATE_UNIT_ADDED" then
    if UnitCanAttack("player", arg1) then
      tracked[arg1] = true
    end
  elseif event == "NAME_PLATE_UNIT_REMOVED" then
    tracked[arg1] = nil
    lastLostTagged[UnitGUID(arg1) or (UnitName(arg1) or arg1)] = nil
  elseif event == "UNIT_THREAT_LIST_UPDATE" or event == "UNIT_THREAT_SITUATION_UPDATE" then
    scanThreat()
  elseif event == "PLAYER_TARGET_CHANGED" then
    scanThreat()
  elseif event == "GROUP_ROSTER_UPDATE" or event == "ZONE_CHANGED_NEW_AREA" then
    local _, instanceType = IsInInstance()
    isInInstance = (instanceType ~= "none")
    scanThreat()
  end
end)

-- Polling to catch edge cases
f:SetScript("OnUpdate", function(_, elapsed)
  if not inCombat then return end
  elapsedSinceCheck = elapsedSinceCheck + elapsed
  if elapsedSinceCheck >= POLL_INTERVAL then
    elapsedSinceCheck = 0
    scanThreat()
  end
end)

-- Register events
f:RegisterEvent("PLAYER_REGEN_DISABLED")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("NAME_PLATE_UNIT_ADDED")
f:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
f:RegisterEvent("UNIT_THREAT_LIST_UPDATE")
f:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE")
f:RegisterEvent("PLAYER_TARGET_CHANGED")
f:RegisterEvent("GROUP_ROSTER_UPDATE")
f:RegisterEvent("ZONE_CHANGED_NEW_AREA")

-- Start hidden
f:Hide()
