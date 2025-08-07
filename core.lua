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
