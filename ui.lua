local ADDON_NAME, ns = ...

local f = CreateFrame("Frame", "TankAggroAlertFrame", UIParent)
ns.frame = f

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
  header:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, yOff)
  header:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -8, yOff)
  header:SetHeight(22)

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
  body:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -2)
  body:SetHeight(1)

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
    ns.resizeFrame()
  end)
  header.arrow:SetText("▼")

  return header, body
end

local header1, body1 = newSection(f, "I have aggro (0)", -28)
local header2, body2 = newSection(f, "Lost aggro (0)", -28 - 22 - 4)
local header3, body3 = newSection(f, "Group aggro (0)", -28 - (22+4)*2)

ns.header1, ns.body1 = header1, body1
ns.header2, ns.body2 = header2, body2
ns.header3, ns.body3 = header3, body3

function ns.setHeaderCount(header, label, n, color)
  header.text:SetText(('%s (%d)'):format(label, n))
  if color then
    header.bg:SetColorTexture(color[1], color[2], color[3], 0.7)
  end
end

function ns.setBackdropColor(r,g,b)
  f.bg:SetColorTexture(r, g, b, 0.4)
end

function ns.fillLines(body, lines)
  for i=1, body.maxLines do
    local text = lines[i]
    body.lines[i]:SetText(text or "")
  end
end

function ns.resizeFrame()
  local h = 40
  local function bodyHeight(body)
    if not body:IsShown() then return 0 end
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

ns.frame:Hide()
