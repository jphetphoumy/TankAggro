local ADDON_NAME = ...
-- Main frame with default WoW skin
local f = CreateFrame("Frame", "TankAggroAlertFrame", UIParent, "BasicFrameTemplateWithInset")
f:SetSize(360, 160)
f:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
f:EnableMouse(true)
f:SetMovable(true)
f:RegisterForDrag("LeftButton")
f:SetScript("OnDragStart", f.StartMoving)
f:SetScript("OnDragStop", f.StopMovingOrSizing)
f.TitleText:SetText("Tank Aggro")

-- ===== Config =====
local POLL_INTERVAL = 0.2
local SOUND_ON_LOSS = SOUNDKIT.RAID_WARNING
local LINE_HEIGHT   = 14
local SECTION_GAP   = 6
local BODY_SIDE_PAD = 10
local SHOW_IN_WORLD = true -- set false to only show in instances

-- ===== State =====
local tracked = {}            -- nameplate unit tokens we know about
local inCombat = false
local isInInstance = false
local elapsedSince = 0
local playerName = UnitName("player") or "player"
local lastLostTagged = {}     -- mobGUID => who took it (to ping once)

-- ===== Helpers =====
local function groupUnitIterator()
  local n, isRaid = GetNumGroupMembers(), IsInRaid()
  if n == 0 then
    return function() return nil end
  end
  local i = 0
  return function()
    i = i + 1
    if isRaid then
      if i > n then return nil end
      return ("raid%d"):format(i)
    else
      -- include player first, then party1..partyN
      if i == 1 then return "player" end
      if i-1 > n then return nil end
      return ("party%d"):format(i-1)
    end
  end
end

local function isEnemyUnit(unit)
  return UnitCanAttack("player", unit) and not UnitIsDead(unit)
end

local function unitHasAggroOnMob(unit, mob)
  local s = UnitThreatSituation(unit, mob)
  return s == 3
end

-- ===== UI Section Factory (WoW-styled headers as buttons) =====
local function NewSection(parent, label)
  local sec = CreateFrame("Frame", nil, parent)
  sec:SetSize(1,1) -- size set by layout

  -- Header button with UIPanelButton look
  local header = CreateFrame("Button", nil, sec, "UIPanelButtonTemplate")
  header:SetPoint("TOPLEFT")
  header:SetPoint("TOPRIGHT")
  header:SetHeight(22)
  header:SetText(label .. " (0)")

  header.Arrow = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  header.Arrow:SetPoint("RIGHT", -6, 0)
  header.Arrow:SetText("▼") -- collapsed by default

  -- Body frame for lines
  local body = CreateFrame("Frame", nil, sec, "BackdropTemplate")
  body:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
  body:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -2)
  body:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 }
  })
  body:SetBackdropColor(0,0,0,0.5)

  body.lines = {}
  body.used = 0
  body.collapsed = true
  body:Hide()

  local function ensureLine(i)
    if body.lines[i] then return body.lines[i] end
    local fs = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    if i == 1 then
      fs:SetPoint("TOPLEFT", BODY_SIDE_PAD, -6)
      fs:SetPoint("RIGHT", -BODY_SIDE_PAD, 0)
    else
      fs:SetPoint("TOPLEFT", body.lines[i-1], "BOTTOMLEFT", 0, -2)
      fs:SetPoint("RIGHT", -BODY_SIDE_PAD, 0)
    end
    fs:SetJustifyH("LEFT")
    fs:SetText("")
    body.lines[i] = fs
    return fs
  end

  function body:SetLines(texts)
    -- write texts and compute height
    local count = #texts
    body.used = count
    for i=1, count do
      local fs = ensureLine(i)
      fs:SetText(texts[i])
      fs:Show()
    end
    for j=count+1, #body.lines do
      body.lines[j]:Hide()
    end

    if count == 0 then
      body:SetHeight(10)
    else
      -- Rough height: first line top padding (6) + (count-1)* (LINE_HEIGHT+2) + LINE_HEIGHT + bottom padding (6)
      local h = 6 + (count * LINE_HEIGHT) + ((count-1) * 2) + 6
      body:SetHeight(h)
    end
  end

  function sec:SetCount(n)
    local base = label
    header:SetText(("%s (%d)"):format(base, n))
  end

  function sec:SetTint(r,g,b)
    -- Tint header subtly by changing text color; button skin stays default
    local font = header:GetFontString()
    font:SetTextColor(r,g,b)
  end

  header:SetScript("OnClick", function()
    body.collapsed = not body.collapsed
    if body.collapsed then
      body:Hide()
      header.Arrow:SetText("▼")
    else
      body:Show()
      header.Arrow:SetText("▲")
    end
    parent:RequestLayout()
  end)

  sec.Header = header
  sec.Body   = body
  return sec
end

-- ===== Build UI: three sections stacked; auto layout =====
f.Container = CreateFrame("Frame", nil, f)
f.Container:SetPoint("TOPLEFT", f.Inset, "TOPLEFT", 6, -6)
f.Container:SetPoint("TOPRIGHT", f.Inset, "TOPRIGHT", -6, -6)
f.Container:SetPoint("BOTTOM", f.Inset, "BOTTOM", 0, 6)

local SecHave  = NewSection(f.Container, "I have aggro")
local SecLost  = NewSection(f.Container, "Lost aggro")
local SecGroup = NewSection(f.Container, "Group aggro")

-- layout function: stack sections with spacing, size parent height
function f.Container:RequestLayout()
  -- Anchor top of first section
  SecHave:ClearAllPoints()
  SecHave:SetPoint("TOPLEFT")
  SecHave:SetPoint("TOPRIGHT")

  local y = 0

  local function positionSection(sec, anchor, yOff)
    sec:ClearAllPoints()
    sec:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, yOff)
    sec:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, yOff)
  end

  -- Size each section to header + (visible body height)
  local function sizeSection(sec)
    local headerH = 22
    local bodyH   = (sec.Body:IsShown() and sec.Body:GetHeight() or 0)
    sec:SetHeight(headerH + (bodyH > 0 and (2 + bodyH) or 0))
  end

  sizeSection(SecHave)
  positionSection(SecLost, SecHave, -SECTION_GAP)
  sizeSection(SecLost)
  positionSection(SecGroup, SecLost, -SECTION_GAP)
  sizeSection(SecGroup)

  -- Compute container min height (just informative; parent frame auto-resizes via Inset bounds)
  local total = SecHave:GetHeight() + SECTION_GAP + SecLost:GetHeight() + SECTION_GAP + SecGroup:GetHeight()
  -- Adjust outer frame height to fit content nicely
  local topPad = 44 -- title bar + inset spacing
  local bottomPad = 28
  f:SetHeight(topPad + total + bottomPad)
end

-- initial collapsed state (bodies hidden, arrows down)
SecHave.Body.collapsed  = true;  SecHave.Header.Arrow:SetText("▼")
SecLost.Body.collapsed  = true;  SecLost.Header.Arrow:SetText("▼")
SecGroup.Body.collapsed = true;  SecGroup.Header.Arrow:SetText("▼")
f.Container:RequestLayout()

-- ===== Threat Scan =====
local function scanThreat()
  if not inCombat or (not SHOW_IN_WORLD and not isInInstance) then
    f:Hide()
    return
  end
  f:Show()

  local haveAggro, lostAggro, holderLists = {}, {}, {}
  local lostCount, insecureCount = 0, 0
  local newLoss = false

  for unit in pairs(tracked) do
    if UnitExists(unit) and isEnemyUnit(unit) and UnitAffectingCombat(unit) then
      local mobName = UnitName(unit) or "Unknown"
      local status = UnitThreatSituation("player", unit)

      if status == 3 then
        table.insert(haveAggro, mobName)
      else
        if status == 2 or status == 1 then
          insecureCount = insecureCount + 1
        end

        local holder
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
          local key = UnitGUID(unit) or mobName
          if not lastLostTagged[key] then newLoss = true end
          lastLostTagged[key] = holder
          holderLists[holder] = holderLists[holder] or {}
          table.insert(holderLists[holder], mobName)
        else
          if status == nil or status == 0 then
            lostCount = lostCount + 1
            table.insert(lostAggro, ("%s -> ?"):format(mobName))
            local key = UnitGUID(unit) or mobName
            if not lastLostTagged[key] then newLoss = true end
            lastLostTagged[key] = "?"
          end
        end
      end
    end
  end

  -- Build group holder strings
  local groupHolders = {}
  for name, mobs in pairs(holderLists) do
    table.sort(mobs)
    table.insert(groupHolders, ("%s: %s"):format(name, table.concat(mobs, ", ")))
  end

  table.sort(haveAggro)
  table.sort(lostAggro)
  table.sort(groupHolders)

  -- Sound on new loss
  if newLoss then
    PlaySound(SOUND_ON_LOSS, "Master")
  end

  -- Title color based on status (WoW look)
  if lostCount > 0 then
    f.TitleText:SetTextColor(0.9, 0.2, 0.2)
  elseif insecureCount > 0 then
    f.TitleText:SetTextColor(0.95, 0.85, 0.3)
  else
    f.TitleText:SetTextColor(1, 0.82, 0) -- default golden
  end

  -- Update sections
  SecHave:SetCount(#haveAggro)
  SecHave:SetTint(0.4, 1.0, 0.4)
  SecHave.Body:SetLines(haveAggro)

  SecLost:SetCount(lostCount)
  SecLost:SetTint(1.0, 0.4, 0.4)
  SecLost.Body:SetLines(lostAggro)

  SecGroup:SetCount(#groupHolders)
  SecGroup:SetTint(0.6, 0.8, 1.0)
  SecGroup.Body:SetLines(groupHolders)

  -- If a section is not collapsed but it has 0 lines, still show a small body height for clarity
  if not SecHave.Body.collapsed then SecHave.Body:Show() end
  if not SecLost.Body.collapsed then SecLost.Body:Show() end
  if not SecGroup.Body.collapsed then SecGroup.Body:Show() end

  f.Container:RequestLayout()
end

-- ===== Events =====
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

f:RegisterEvent("PLAYER_REGEN_DISABLED")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("NAME_PLATE_UNIT_ADDED")
f:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
f:RegisterEvent("UNIT_THREAT_LIST_UPDATE")
f:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE")
f:RegisterEvent("PLAYER_TARGET_CHANGED")
f:RegisterEvent("GROUP_ROSTER_UPDATE")
f:RegisterEvent("ZONE_CHANGED_NEW_AREA")

-- Poll to catch edge cases
f:SetScript("OnUpdate", function(_, elapsed)
  if not inCombat then return end
  elapsedSince = elapsedSince + elapsed
  if elapsedSince >= POLL_INTERVAL then
    elapsedSince = 0
    scanThreat()
  end
end)

-- Start hidden
f:Hide()