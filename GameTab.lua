-- A side tab on the native Guild & Communities window, matching the game's tabs.
-- Like FreeLFG's group-finder tab, this is an independent button: Blizzard's
-- frame is only observed and post-hooked, never re-parented or scripted over.
local ADDON, ns = ...
local MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"
local MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local TAB_NAMES = { "ChatTab", "RosterTab", "GuildBenefitsTab", "GuildInfoTab" }
local tabs, hooked = {}, {}

local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e = pcall(fn, ...)
    if ok then return a, b, c, d, e end
end

local function Get(obj, method, ...)
    if type(obj) ~= "table" then return nil end
    return Call(obj[method], obj, ...)
end

local function ScreenRect(obj)
    local scale = Get(obj, "GetEffectiveScale") or 1
    local left, bottom = Get(obj, "GetLeft"), Get(obj, "GetBottom")
    local width, height = Get(obj, "GetWidth"), Get(obj, "GetHeight")
    if not (left and bottom and width and height) then return nil end
    return left * scale, bottom * scale, width * scale, height * scale
end

local function AtlasAvailable(tex, atlas)
    if not tex or not tex.SetAtlas then return false end
    local ok = pcall(tex.SetAtlas, tex, atlas)
    if not ok then return false end
    if C_Texture and C_Texture.GetAtlasInfo then
        local got, info = pcall(C_Texture.GetAtlasInfo, atlas)
        if not got or not info then return false end
    end
    return true
end

local function SetIcon(tab, width, hasAtlas)
    local icon = tab:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(MEDIA .. "tab")
    icon:SetSize(width * 50 / 55, width * 50 / 55)
    icon:SetTexCoord(0, 1, 0, 1)
    icon:SetPoint("CENTER", tab, "CENTER", -width * 3 / 55, 0)
    if tab.CreateMaskTexture and icon.AddMaskTexture then
        local ok = pcall(function()
            local mask = tab:CreateMaskTexture()
            if hasAtlas then mask:SetAtlas("common-sidetab-mask")
            else mask:SetTexture(MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE") end
            mask:SetAllPoints(icon)
            icon:AddMaskTexture(mask)
        end)
        if not ok then icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    end
    return icon
end

local function NativeGap(frame, anchor)
    local _, anchorBottom, anchorWidth, anchorHeight = ScreenRect(anchor)
    if not anchorBottom then return 4 end
    local scale = Get(frame, "GetEffectiveScale") or 1
    local anchorLeft = ScreenRect(anchor)
    local nearestAbove
    for _, name in ipairs(TAB_NAMES) do
        local other = frame[name]
        if other and other ~= anchor and Get(other, "IsShown") ~= false then
            local left, bottom = ScreenRect(other)
            if left and bottom and bottom > anchorBottom
                and math.abs(left - anchorLeft) <= math.max(8 * scale, anchorWidth * 0.25)
                and (not nearestAbove or bottom < nearestAbove) then
                nearestAbove = bottom
            end
        end
    end
    if nearestAbove then
        local gap = (nearestAbove - (anchorBottom + anchorHeight)) / scale
        if gap >= 0 and gap <= 40 then return gap end
    end
    return 4
end

local function Place(frame, button)
    local anchor = frame.GuildInfoTab
    if not anchor then button:Hide(); return false end
    local parentScale = Get(frame, "GetEffectiveScale") or 1
    local anchorScale = Get(anchor, "GetEffectiveScale") or parentScale
    local width = (Get(anchor, "GetWidth") or 35) * anchorScale / parentScale
    local height = (Get(anchor, "GetHeight") or width) * anchorScale / parentScale
    width = math.max(20, math.min(64, width))
    height = math.max(20, math.min(64, height))
    button:ClearAllPoints()
    button:SetSize(width, height)
    if button.fgAtlas then
        button.fgArt:SetSize(width, width * 60 / 55)
        button.fgArt:ClearAllPoints(); button.fgArt:SetPoint("CENTER")
        button.fgIcon:SetSize(width * 50 / 55, width * 50 / 55)
        button.fgIcon:ClearAllPoints(); button.fgIcon:SetPoint("CENTER", button, "CENTER", -width * 3 / 55, 0)
        button.fgHighlight:SetSize(width, width * 60 / 55)
        button.fgHighlight:ClearAllPoints(); button.fgHighlight:SetPoint("CENTER")
    else
        button.fgArt:SetSize(width * 1.6, width * 1.6)
        button.fgArt:ClearAllPoints(); button.fgArt:SetPoint("TOPLEFT", button, "TOPLEFT", -width * 0.075, width * 0.275)
        button.fgIcon:SetSize(width * 0.8, width * 0.8)
        button.fgIcon:ClearAllPoints(); button.fgIcon:SetPoint("CENTER")
        button.fgHighlight:SetAllPoints()
    end
    button:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -NativeGap(frame, anchor))
    button:SetFrameStrata(Get(anchor, "GetFrameStrata") or Get(frame, "GetFrameStrata") or "MEDIUM")
    button:SetFrameLevel(Get(anchor, "GetFrameLevel") or Get(frame, "GetFrameLevel") or 1)
    return true
end

local function Update(frame)
    frame = frame or _G.CommunitiesFrame
    local button = frame and tabs[frame]
    if not button then return false end
    local guildTab = frame.GuildInfoTab
    local show = IsInGuild and IsInGuild() and Get(frame, "IsShown") ~= false
        and guildTab and Get(guildTab, "IsShown") ~= false
    if show and Place(frame, button) then button:SetShown(true)
    else button:SetShown(false) end
    return show and true or false
end

function ns.UpdateGameTab(frame) return Update(frame) end

function ns.InstallGameTab()
    local frame = _G.CommunitiesFrame
    if not frame then return false end
    local button = tabs[frame]
    if not button then
        button = CreateFrame("Button", "FreeGuildCommunitiesTab", frame)
        local art = button:CreateTexture(nil, "BACKGROUND")
        local hasAtlas = AtlasAvailable(art, "common-sidetab")
        button.fgAtlas = hasAtlas
        button.fgArt = art
        if hasAtlas then
            art:SetSize(55, 60)
            art:SetPoint("CENTER")
        else
            art:SetTexture("Interface\\SpellBook\\SpellBook-SkillLineTab")
            art:SetSize(52, 52)
            art:SetPoint("CENTER")
        end
        button.fgIcon = SetIcon(button, 55, hasAtlas)
        local highlight = button:CreateTexture(nil, "HIGHLIGHT")
        button.fgHighlight = highlight
        if not (hasAtlas and AtlasAvailable(highlight, "common-sidetab-hover")) then
            highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
            highlight:SetBlendMode("ADD")
            highlight:SetAllPoints()
        else
            highlight:SetSize(55, 60)
            highlight:SetPoint("CENTER")
        end
        button:SetScript("OnClick", function() if ns.OpenConfig then ns.OpenConfig() end end)
        button:SetScript("OnEnter", function(self)
            if GameTooltip then GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText("Free Guild"); GameTooltip:Show() end
        end)
        button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        tabs[frame] = button
    end

    if not hooked[frame] then
        hooked[frame] = true
        if frame.HookScript then pcall(frame.HookScript, frame, "OnShow", function() Update(frame) end) end
        if hooksecurefunc then
            for _, method in ipairs({ "UpdateCommunitiesTabs", "OnClubSelected", "SetDisplayMode" }) do
                if type(frame[method]) == "function" then
                    pcall(hooksecurefunc, frame, method, function() Update(frame) end)
                end
            end
        end
        local guildTab = frame.GuildInfoTab
        if guildTab and guildTab.HookScript then
            pcall(guildTab.HookScript, guildTab, "OnShow", function() Update(frame) end)
            pcall(guildTab.HookScript, guildTab, "OnHide", function() Update(frame) end)
        end
    end
    Update(frame)
    return true
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("PLAYER_GUILD_UPDATE")
boot:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name ~= "Blizzard_Communities" then return end
    if event == "PLAYER_GUILD_UPDATE" then Update(); return end
    ns.InstallGameTab()
end)
