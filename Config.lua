-- Free Guild - window: Roster (multi-select, set rank), Rules (level ranges -> rank), Queue & log

local ADDON, ns = ...
local UI = LibStub("LibFreeUI-1.0")
local C = UI.C
local MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"

local kit = UI:New({ name = "FreeGuildOptions", title = "Free Guild", sub = "Guild ranks", addon = ADDON,
                     icon = MEDIA .. "icon", circle = MEDIA .. "circle", shadow = MEDIA .. "shadow", w = 900, h = 660,
                     subFn = function()
                         local g = GetGuildInfo and GetGuildInfo("player")
                         return g and ("  ·  " .. g .. "  ·  " .. #ns.members .. " members") or "  ·  not in a guild"
                     end })

local frame
local selected = {}            -- [full name] = true
local sortKey, sortAsc = "rank", true
local filter = { text = "", rank = -1, online = false, minL = nil, maxL = nil }
local view = {}                -- filtered + sorted members shown in the list
local lastClicked
local bulkRank
local selRule = 1           -- rule shown in the editor
local changesN = 0          -- members the rules would move (whatever the other filters)

-- "To change" filter: only members the rules would give another rank (kept between sessions)
local function OnlyChanges() local d = ns.GetDB(); return d and d.onlyChanges or false end
local function SetOnlyChanges(v) local d = ns.GetDB(); if d then d.onlyChanges = v or nil end end

local function ClassColor(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return 0.85, 0.85, 0.85
end

-- last seen: "online" only when the game says so (an offline member gone less than an hour ago also gives 0 h)
local function LastText(h, online)
    if online then return "|cff66dd77online|r" end
    if h == nil then return "?" end
    if h == 0 then return "< 1 h" end
    if h < 24 then return h .. " h" end
    local d = math.floor(h / 24)
    if d < 31 then return d .. " d" end
    if d < 365 then return math.floor(d / 30) .. " mo" end
    return math.floor(d / 365) .. " y"
end

local function BuildView()
    wipe(view)
    changesN = 0
    local only = OnlyChanges()
    local t = (filter.text or ""):lower()
    for _, m in ipairs(ns.members) do
        local ok = true
        local planned = ns.PlannedTarget(m) ~= nil
        if planned then changesN = changesN + 1 end
        if t ~= "" then
            ok = m.short:lower():find(t, 1, true) or m.note:lower():find(t, 1, true) or m.onote:lower():find(t, 1, true)
                 or m.classDisplay:lower():find(t, 1, true)
        end
        if ok and filter.rank >= 0 and m.rank ~= filter.rank then ok = false end
        if ok and filter.online and not m.online then ok = false end
        if ok and filter.minL and m.level < filter.minL then ok = false end
        if ok and filter.maxL and m.level > filter.maxL then ok = false end
        if ok and only and not planned then ok = false end
        if ok then view[#view + 1] = m end
    end
    local function key(m)
        if sortKey == "name" then return m.short:lower()
        elseif sortKey == "level" then return m.level
        elseif sortKey == "class" then return m.classDisplay
        elseif sortKey == "last" then return m.online and -1 or (m.last or 1e9)
        else return m.rank end
    end
    table.sort(view, function(a, b)
        local ka, kb = key(a), key(b)
        if ka == kb then return a.short < b.short end
        if sortAsc then return ka < kb else return ka > kb end
    end)
end

local function NumSelected()
    local n = 0
    for _, m in ipairs(ns.members) do if selected[m.name] then n = n + 1 end end
    return n
end

-- ranks I can give (below mine)
local function AssignableRanks()
    local out = {}
    local my = ns.MyRank() or 99
    for r = my + 1, ns.NumRanks() - 1 do out[#out + 1] = { key = r, label = (r + 1) .. ". " .. ns.RankName(r) } end
    return out
end
local function AllRanks(withNone, noneLabel)
    local out = {}
    if withNone or noneLabel then out[1] = { key = -1, label = noneLabel or "All ranks" } end
    for r = 0, ns.NumRanks() - 1 do out[#out + 1] = { key = r, label = (r + 1) .. ". " .. ns.RankName(r) } end
    return out
end

local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT", "SHAMAN", "MAGE", "WARLOCK", "MONK", "DRUID", "DEMONHUNTER", "EVOKER" }
local function ClassItems()
    local out = { { key = "ANY", label = "Any class" } }
    for _, c in ipairs(CLASSES) do
        local nm = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[c]) or (c:sub(1, 1) .. c:sub(2):lower())
        out[#out + 1] = { key = c, label = nm }
    end
    return out
end

-- ------------------------------------------------------------ Raids tab (rosters, invites, attendance)
local ROLE_COLOR = { TANK = { 0.45, 0.7, 1 }, HEALER = { 0.4, 0.9, 0.5 }, DAMAGER = { 1, 0.55, 0.45 } }
local ROLE_ORDER = { TANK = 1, HEALER = 2, DAMAGER = 3 }
local STATUS_COLOR = { P = { 0.4, 0.87, 0.47 }, A = { 1, 0.4, 0.35 }, E = { 1, 0.8, 0.3 }, B = { 0.6, 0.6, 0.65 } }

local function BuildRaids(p, PAD, LX)
    local raidView = {}
    local function ro() return ns.CurRoster() end

    -- top bar: roster choice, rename, new, delete, undo
    local pick = kit:Dropdown(p, nil, LX, 0, 200, function()
        local out, r = {}, ns.RaidDB()
        for i, x in ipairs(r and r.list or {}) do out[#out + 1] = { key = i, label = x.name } end
        return out
    end, function() local r = ns.RaidDB(); return r and r.cur end,
       function(v) local r = ns.RaidDB(); if r then r.cur = v; kit:Refresh() end end, 0)
    kit.flow[#kit.flow] = nil
    pick:ClearAllPoints(); pick:SetPoint("TOPLEFT", LX, 0)
    local nameB = kit:InputBox(p, 150); nameB:SetPoint("TOPLEFT", LX + 210, 0)
    local function rename() ns.RenameRoster(nameB:GetText()); nameB:ClearFocus() end
    nameB:SetScript("OnEnterPressed", rename)
    nameB:SetScript("OnEscapePressed", function(s) s:ClearFocus(); kit:Refresh() end)
    kit:OnRefresh(function() local x = ro(); if x and not nameB:HasFocus() then nameB:SetText(x.name) end end)
    local bRen = kit:Button(p, "Rename", 80, false, rename); bRen:SetPoint("LEFT", nameB, "RIGHT", 6, 0)
    local bNew = kit:Button(p, "New roster", 100, false, function() ns.NewRoster() end); bNew:SetPoint("LEFT", bRen, "RIGHT", 6, 0)
    local bDel = kit:Button(p, "Delete", 80, false, function(s)
        if s.armed and (GetTime() - s.armed) < 4 then s.armed = nil; ns.DeleteRoster()
        else s.armed = GetTime(); s.label:SetText("Sure?") end
        kit:Refresh()
    end)
    bDel:SetPoint("LEFT", bNew, "RIGHT", 6, 0)
    bDel.tip = "Delete this roster and its raid history (click twice)."
    kit:OnRefresh(function() if not (bDel.armed and (GetTime() - bDel.armed) < 4) then bDel.armed = nil; bDel.label:SetText("Delete") end end)
    local bUndo = kit:Button(p, "Remove last raid", 140, false, function() ns.UndoAttendance() end)
    bUndo:SetPoint("TOPRIGHT", -PAD, 0)
    bUndo.tip = "Remove the last recorded raid of this roster."
    kit:OnRefresh(function() local x = ro(); bUndo:SetEnabled(x and #x.events > 0 or false) end)

    -- list
    local COLS = {
        { key = "name", label = "Name", w = 150 }, { key = "level", label = "Lvl", w = 40 }, { key = "role", label = "Role", w = 70 },
        { key = "spot", label = "Spot", w = 80 }, { key = "next", label = "Next raid", w = 90 }, { key = "last", label = "Last raid", w = 90 },
        { key = "att", label = "Attendance", w = 110 }, { key = "seen", label = "Last seen", w = 90 }, { key = "del", label = "", w = 0 },
    }
    local CLICKABLE = { role = "Click: Tank / Heal / DPS", spot = "Click: main / bench", next = "Click: excused for the next raid",
                        last = "Click: correct the last raid (present / absent / excused / bench)", del = "Click: remove from this roster" }
    local list = CreateFrame("Frame", nil, p)
    list:SetPoint("TOPLEFT", LX, -36); list:SetPoint("BOTTOMRIGHT", -PAD, 44)
    local lbg = kit:Fill(list, C.panel); lbg:SetAllPoints()
    kit:Border(list, 0.06)
    local head = CreateFrame("Frame", nil, list)
    head:SetPoint("TOPLEFT"); head:SetPoint("TOPRIGHT"); head:SetHeight(24)
    local hbg = kit:Fill(head, { 1, 1, 1, 0.04 }); hbg:SetAllPoints()
    local x = 8
    for _, c in ipairs(COLS) do
        local t = kit:Text(head, 12, C.dim); t:SetPoint("LEFT", x, 0); t:SetText(c.label)
        c.x = x; x = x + c.w
    end

    local RH, rows, offset = 22, {}, 0
    local function rowsFit() return math.max(5, math.floor(((list:GetHeight() or 400) - 26) / RH)) end
    local function cellTip(cell)
        local r = cell.row
        if not r.name then return end
        GameTooltip:SetOwner(cell, "ANCHOR_RIGHT")
        GameTooltip:AddLine(r.name, 1, 1, 1)
        if cell.key == "att" then
            local x = ro()
            local shown = 0
            for i = #x.events, 1, -1 do
                local ev = x.events[i]
                local s = ev.s[r.name]
                if s then
                    local col = STATUS_COLOR[s]
                    GameTooltip:AddDoubleLine(date and date("%d/%m/%Y %H:%M", ev.t) or tostring(ev.t), ns.STATUS_LABEL[s], 0.7, 0.7, 0.75, col[1], col[2], col[3])
                    shown = shown + 1
                    if shown >= 12 then break end
                end
            end
            if shown == 0 then GameTooltip:AddLine("No raid recorded yet.", 0.6, 0.6, 0.65) end
            GameTooltip:AddLine("Excused and bench raids are not counted.", 0.5, 0.5, 0.55, true)
        elseif CLICKABLE[cell.key] then
            GameTooltip:AddLine(CLICKABLE[cell.key], 0.5, 0.5, 0.55)
        end
        GameTooltip:Show()
    end
    local ACTIONS = {
        role = function(n) ns.CycleRole(n) end, spot = function(n) ns.ToggleBench(n) end,
        next = function(n) ns.ToggleExcused(n) end, last = function(n) ns.CycleLastStatus(n) end,
        del = function(n) ns.RemoveFromRoster(n) end,
    }
    for i = 1, 30 do
        local r = CreateFrame("Frame", nil, list)
        r:SetHeight(RH)
        r:SetPoint("TOPLEFT", 1, -25 - (i - 1) * RH); r:SetPoint("TOPRIGHT", -1, -25 - (i - 1) * RH)
        r.zebra = kit:Fill(r, { 1, 1, 1, (i % 2 == 0) and 0.025 or 0 }); r.zebra:SetAllPoints()
        r.cols = {}
        for _, c in ipairs(COLS) do
            local cell = CreateFrame("Button", nil, r)
            cell:SetPoint("TOPLEFT", c.x - 4, 0); cell:SetHeight(RH)
            if c.w > 0 then cell:SetWidth(c.w) else cell:SetPoint("TOPRIGHT", r, "TOPRIGHT", -6, 0) end
            cell.key, cell.row = c.key, r
            cell.hl = kit:Fill(cell, { 1, 1, 1, 0.05 }, "ARTWORK", 1); cell.hl:SetAllPoints(); cell.hl:Hide()
            local t = kit:Text(cell, 12, C.text); t:SetWordWrap(false)
            t:SetPoint("LEFT", 4, 0); t:SetPoint("RIGHT", -2, 0)
            if c.key == "del" then t:ClearAllPoints(); t:SetPoint("RIGHT", -4, 0); t:SetText("x"); t:SetTextColor(unpack(C.muted)) end
            cell:SetScript("OnEnter", function(s) if ACTIONS[s.key] then s.hl:Show() end; cellTip(s) end)
            cell:SetScript("OnLeave", function(s) s.hl:Hide(); GameTooltip:Hide() end)
            cell:SetScript("OnClick", function(s) local a = ACTIONS[s.key]; if a and s.row.name then a(s.row.name); kit:Refresh() end end)
            r.cols[c.key] = t
        end
        rows[i] = r
    end
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, d) offset = offset - d * 3; kit:Refresh() end)
    local empty = kit:Text(list, 13, C.muted); empty:SetPoint("CENTER"); empty:SetWidth(520); empty:SetText("")

    local counts = kit:Text(p, 13, C.text); counts:SetPoint("BOTTOMLEFT", LX, 14)
    kit:OnRefresh(function()
        wipe(raidView)
        local x = ro()
        local c = { main = 0, bench = 0, TANK = 0, HEALER = 0, DAMAGER = 0, online = 0 }
        for name, e in pairs(x and x.members or {}) do
            local m = ns.FindMember(nil, name)
            raidView[#raidView + 1] = { name = name, e = e, m = m }
            if e.bench then c.bench = c.bench + 1 else
                c.main = c.main + 1
                if e.role then c[e.role] = c[e.role] + 1 end
            end
            if m and m.online then c.online = c.online + 1 end
        end
        table.sort(raidView, function(a, b)
            local ba, bb = a.e.bench and 1 or 0, b.e.bench and 1 or 0
            if ba ~= bb then return ba < bb end
            local ra, rb = ROLE_ORDER[a.e.role] or 4, ROLE_ORDER[b.e.role] or 4
            if ra ~= rb then return ra < rb end
            return a.name < b.name
        end)
        local NROWS = rowsFit()
        offset = math.max(0, math.min(offset, #raidView - NROWS))
        for i, r in ipairs(rows) do
            local v = (i <= NROWS) and raidView[i + offset]
            r.name = v and v.name or nil
            if v then
                local m, e = v.m, v.e
                r.cols.name:SetText(ns.Short(v.name))
                if m then r.cols.name:SetTextColor(ClassColor(m.class)) else r.cols.name:SetTextColor(unpack(C.muted)) end
                r.cols.name:SetAlpha((m and m.online) and 1 or 0.65)
                r.cols.level:SetText(m and m.level or "-"); r.cols.level:SetTextColor(unpack(C.dim))
                r.cols.role:SetText(e.role and ns.ROLE_LABEL[e.role] or "-")
                r.cols.role:SetTextColor(unpack(ROLE_COLOR[e.role] or C.muted))
                r.cols.spot:SetText(e.bench and "Bench" or "Main"); r.cols.spot:SetTextColor(unpack(e.bench and C.muted or C.text))
                r.cols.next:SetText(e.excused and "Excused" or "-"); r.cols.next:SetTextColor(unpack(e.excused and STATUS_COLOR.E or C.muted))
                local ls = ns.LastStatus(x, v.name)
                r.cols.last:SetText(ls and ns.STATUS_LABEL[ls] or "-"); r.cols.last:SetTextColor(unpack(STATUS_COLOR[ls] or C.muted))
                local pr, ct = ns.Attendance(x, v.name)
                if ct > 0 then
                    local pct = math.floor(pr * 100 / ct + 0.5)
                    r.cols.att:SetText(pct .. "%  (" .. pr .. "/" .. ct .. ")")
                    r.cols.att:SetTextColor(unpack(pct >= 75 and STATUS_COLOR.P or (pct >= 50 and STATUS_COLOR.E or STATUS_COLOR.A)))
                else r.cols.att:SetText("-"); r.cols.att:SetTextColor(unpack(C.muted)) end
                r.cols.seen:SetText(m and LastText(m.last, m.online) or "|cff888888left guild|r")
                r:Show()
            else r:Hide() end
        end
        if not ns.GuildDB() then empty:SetText("You are not in a guild.")
        elseif #raidView == 0 then empty:SetText("This roster is empty. Select members in the Roster tab, then come back and click \"Add selected\".")
        else empty:SetText("") end
        counts:SetText(string.format("Main %d  ·  Tank %d  ·  Heal %d  ·  DPS %d  ·  Bench %d  ·  Online %d",
            c.main, c.TANK, c.HEALER, c.DAMAGER, c.bench, c.online))
    end)

    -- bottom bar
    local bTake = kit:Button(p, "Take attendance", 150, true, function() ns.TakeAttendance() end)
    bTake:SetPoint("BOTTOMRIGHT", -PAD, 8)
    bTake.tip = "Record a raid now: members of this roster in your group are present, the others absent (or excused / bench)."
    local bInvR = kit:Button(p, "Invite roster", 120, false, function()
        local x = ro(); if not x then return end
        local withBench = IsShiftKeyDown and IsShiftKeyDown()
        local l = {}
        for name, e in pairs(x.members) do
            local m = ns.FindMember(nil, name)
            if m and (withBench or not e.bench) then l[#l + 1] = m end
        end
        table.sort(l, function(a, b) return a.short < b.short end)
        ns.InviteMembers(l)
    end)
    bInvR:SetPoint("RIGHT", bTake, "LEFT", -8, 0)
    bInvR.tip = "Invite the online main members of this roster. Shift-click: the bench too."
    local bAdd = kit:Button(p, "Add selected", 140, false, function()
        local l = {}
        for _, m in ipairs(ns.members) do if selected[m.name] then l[#l + 1] = m end end
        if #l == 0 then ns.Print("select members in the Roster tab first."); return end
        local n = ns.AddToRoster(l)
        ns.Print(n .. " member(s) added to " .. ro().name .. ".")
        wipe(selected)
        kit:Refresh()
    end)
    bAdd:SetPoint("RIGHT", bInvR, "LEFT", -8, 0)
    bAdd.tip = "Add the members selected in the Roster tab to this roster."
    kit:OnRefresh(function()
        local n = NumSelected()
        bAdd.label:SetText(n > 0 and ("Add selected (" .. n .. ")") or "Add selected")
        bAdd:SetEnabled(n > 0)
        local x = ro()
        bTake:SetEnabled(x and next(x.members) ~= nil or false)
        bInvR:SetEnabled(x and next(x.members) ~= nil or false)
    end)
end

-- ------------------------------------------------------------ Stats tab (who is in the guild)
local function BuildStats(p, PAD, LX, gotoRoster)
    local onlineOnly = false
    local sortByCount = { class = false, level = false, rank = false }

    -- summary lines
    local sum = kit:Text(p, 14, C.text); sum:SetPoint("TOPLEFT", LX, -2)
    local sum2 = kit:Text(p, 12, C.dim); sum2:SetPoint("TOPLEFT", LX, -24)
    local onl = kit:Switch(p, function() return onlineOnly end, function(v) onlineOnly = v; kit:Refresh() end)
    onl:SetPoint("TOPRIGHT", -PAD - 84, -2)
    local onlL = kit:Text(p, 12, C.dim); onlL:SetPoint("LEFT", onl, "RIGHT", 8, 0); onlL:SetText("Online only")
    local bRef = kit:Button(p, "Refresh", 90, false, function() ns.RequestRoster() end)
    bRef:SetPoint("TOPRIGHT", -PAD - 190, 2)

    -- three tables: class, level, rank
    local W = kit.W - 2 * PAD
    local COLGAP = 28
    local CW = math.floor((W - 2 * COLGAP) / 3)
    local RH, MAXROWS = 20, 14
    local tables = {}
    local function MakeTable(key, title, x)
        local t = { key = key, rows = {} }
        local head = CreateFrame("Button", nil, p)
        head:SetPoint("TOPLEFT", x, -58); head:SetSize(CW, 22)
        head.t = kit:Text(head, 13, C.accent); head.t:SetPoint("LEFT", 6, 0)
        local hn = kit:Text(head, 12, C.dim); hn:SetPoint("RIGHT", -52, 0); hn:SetText("#")
        local hp = kit:Text(head, 12, C.dim); hp:SetPoint("RIGHT", -6, 0); hp:SetText("%")
        head:SetScript("OnClick", function() sortByCount[key] = not sortByCount[key]; kit:Refresh() end)
        head:SetScript("OnEnter", function(s) GameTooltip:SetOwner(s, "ANCHOR_TOP"); GameTooltip:AddLine("Click: sort by " .. (sortByCount[key] and title:lower() or "count"), 1, 1, 1); GameTooltip:Show() end)
        head:SetScript("OnLeave", function() GameTooltip:Hide() end)
        local hl = kit:Fill(head, { 1, 1, 1, 0.07 }); hl:SetHeight(1); hl:SetPoint("BOTTOMLEFT"); hl:SetPoint("BOTTOMRIGHT")
        t.head, t.title = head, title
        for i = 1, MAXROWS do
            local r = CreateFrame("Button", nil, p)
            r:SetPoint("TOPLEFT", x, -82 - (i - 1) * RH); r:SetSize(CW, RH)
            r.zebra = kit:Fill(r, { 1, 1, 1, (i % 2 == 0) and 0.025 or 0 }); r.zebra:SetAllPoints()
            r.bar = kit:Fill(r, { C.accent[1], C.accent[2], C.accent[3], 0.16 }, "ARTWORK")
            r.bar:SetPoint("TOPLEFT"); r.bar:SetPoint("BOTTOMLEFT"); r.bar:SetWidth(1)
            r.hl = kit:Fill(r, { 1, 1, 1, 0.05 }, "ARTWORK", 1); r.hl:SetAllPoints(); r.hl:Hide()
            r.l = kit:Text(r, 13, C.text); r.l:SetPoint("LEFT", 6, 0); r.l:SetWidth(CW - 110); r.l:SetWordWrap(false)
            r.n = kit:Text(r, 13, C.text); r.n:SetPoint("RIGHT", -52, 0); r.n:SetJustifyH("RIGHT")
            r.p = kit:Text(r, 12, C.muted); r.p:SetPoint("RIGHT", -6, 0); r.p:SetJustifyH("RIGHT")
            r:SetScript("OnEnter", function(s)
                if not s.item then return end
                s.hl:Show()
                GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
                GameTooltip:AddLine(s.item.label, 1, 1, 1)
                GameTooltip:AddLine(s.item.n .. " member(s)" .. ((not onlineOnly) and (", " .. s.item.on .. " online") or ""), 0.8, 0.8, 0.85)
                if s.item.lvl then GameTooltip:AddLine(string.format("Average level %.1f", s.item.lvl), 0.7, 0.7, 0.75) end
                GameTooltip:AddLine("Click: show them in the Roster tab", 0.5, 0.5, 0.55)
                GameTooltip:Show()
            end)
            r:SetScript("OnLeave", function(s) s.hl:Hide(); GameTooltip:Hide() end)
            r:SetScript("OnClick", function(s) if s.item then gotoRoster(key, s.item.value, s.item.label, onlineOnly) end end)
            t.rows[i] = r
        end
        tables[#tables + 1] = t
        return t
    end
    MakeTable("class", "By class", LX)
    MakeTable("level", "By level", LX + CW + COLGAP)
    MakeTable("rank", "By rank", LX + 2 * (CW + COLGAP))
    local empty = kit:Text(p, 13, C.muted); empty:SetPoint("CENTER", 0, 20)

    local function pct(n, total) return total > 0 and (math.floor(n * 100 / total + 0.5) .. "%") or "-" end

    kit:OnRefresh(function()
        local list = {}
        local on, sumL, maxL = 0, 0, 0
        for _, m in ipairs(ns.members) do
            if m.online then on = on + 1 end
            if not onlineOnly or m.online then
                list[#list + 1] = m
                sumL = sumL + (m.level or 0)
                if (m.level or 0) > maxL then maxL = m.level end
            end
        end
        local total = #list
        local all = #ns.members
        sum:SetText(string.format("Total |cffffffff%d|r     Online |cff66dd77%d|r     Offline |cff9a9ca6%d|r     Average level |cff6fb8ff%s|r",
            all, on, all - on, total > 0 and string.format("%.1f", sumL / total) or "-"))
        -- activity: new members (seen first after tracking started) and inactive ones
        local g = ns.GuildDB()
        local since = g and g.trackingSince or 0
        local new7, off14, off30, maxed = 0, 0, 0, 0
        for _, m in ipairs(list) do
            local d = ns.MemberDays(m)
            if d and d <= 7 and m.firstSeen and m.firstSeen - since > 60 then new7 = new7 + 1 end
            if not m.online and m.last then
                if m.last >= 30 * 24 then off30 = off30 + 1 elseif m.last >= 14 * 24 then off14 = off14 + 1 end
            end
            if (m.level or 0) >= 60 then maxed = maxed + 1 end
        end
        sum2:SetText(string.format("New this week %d   ·   Away 14-29 days %d   ·   Away 30+ days %d   ·   Level 60 %d%s",
            new7, off14, off30, maxed, onlineOnly and "   ·   |cffff8a3donline members only|r" or ""))

        -- groups
        local groups = { class = {}, level = {}, rank = {} }
        local function add(key, id, m, label, order, color)
            local t = groups[key]
            local e = t[id]
            if not e then e = { value = id, label = label, order = order, color = color, n = 0, on = 0, sum = 0 }; t[id] = e end
            e.n = e.n + 1; e.sum = e.sum + (m.level or 0)
            if m.online then e.on = e.on + 1 end
        end
        for _, m in ipairs(list) do
            add("class", m.class or "?", m, m.classDisplay ~= "" and m.classDisplay or (m.class or "?"), 0, { ClassColor(m.class) })
            local lo = math.floor(((m.level or 1) - 1) / 5) * 5 + 1
            add("level", lo, m, lo .. "-" .. (lo + 4), lo)
            add("rank", m.rank, m, ns.RankName(m.rank), m.rank)
        end
        -- every rank and every level bracket up to the highest one, even when empty
        for r = 0, ns.NumRanks() - 1 do
            if not groups.rank[r] then groups.rank[r] = { value = r, label = ns.RankName(r), order = r, n = 0, on = 0, sum = 0 } end
        end
        for lo = 1, math.max(1, maxL), 5 do
            if not groups.level[lo] then groups.level[lo] = { value = lo, label = lo .. "-" .. (lo + 4), order = lo, n = 0, on = 0, sum = 0 } end
        end
        for _, t in ipairs(tables) do
            local items = {}
            local maxN = 0
            for _, e in pairs(groups[t.key]) do
                e.lvl = e.n > 0 and (e.sum / e.n) or nil
                items[#items + 1] = e
                if e.n > maxN then maxN = e.n end
            end
            local byCount = sortByCount[t.key]
            table.sort(items, function(a, b)
                if byCount and a.n ~= b.n then return a.n > b.n end
                if t.key == "class" then return a.label < b.label end
                return a.order < b.order
            end)
            t.head.t:SetText(t.title .. (byCount and "  v" or "  ^"))
            for i, r in ipairs(t.rows) do
                local e = items[i]
                r.item = e
                if e then
                    r.l:SetText(e.label)
                    r.l:SetTextColor(unpack(e.color or (e.n > 0 and C.text or C.muted)))
                    r.n:SetText(e.n); r.n:SetTextColor(unpack(e.n > 0 and C.text or C.muted))
                    r.p:SetText(pct(e.n, total))
                    r.bar:SetWidth(math.max(1, (maxN > 0 and e.n / maxN or 0) * (CW - 2)))
                    r.bar:SetShown(e.n > 0)
                    r:Show()
                else r:Hide() end
            end
        end
        if not IsInGuild() then empty:SetText("You are not in a guild.")
        elseif all == 0 then empty:SetText("Loading the roster...")
        elseif total == 0 then empty:SetText("Nobody is online.")
        else empty:SetText("") end
    end)
end

-- ------------------------------------------------------------ build
local function Build()
    local pages, footer = kit:Build()
    frame = kit.frame
    local PAD, W = kit.PAD, kit.W
    local LX, RX, COLW = kit.LX, kit.RX, kit.COLW

    -- =============================== Roster
    local p = pages.roster
    local offset = 0          -- first row shown in the list
    local search = kit:InputBox(p, 180)
    search:SetPoint("TOPLEFT", LX, 0)
    local sh = kit:Text(search, 12, C.muted); sh:SetPoint("LEFT", 8, 0); sh:SetText("Search name, note, class...")
    search:SetScript("OnTextChanged", function(s) filter.text = s:GetText() or ""; sh:SetShown(filter.text == ""); kit:Refresh() end)
    local rankDD = kit:Dropdown(p, nil, LX + 190, 0, 170, function() return AllRanks(true) end,
        function() return filter.rank end, function(v) filter.rank = v; kit:Refresh() end, 0)
    rankDD:ClearAllPoints(); rankDD:SetPoint("TOPLEFT", LX + 190, 0)
    kit.flow[#kit.flow] = nil   -- fixed place (not a column element)
    local lvlL = kit:Text(p, 12, C.dim); lvlL:SetPoint("TOPLEFT", LX + 372, -6); lvlL:SetText("Level")
    local minB = kit:InputBox(p, 40); minB:SetPoint("TOPLEFT", LX + 410, 0); minB:SetJustifyH("CENTER"); minB:SetNumeric(true)
    local toL = kit:Text(p, 12, C.dim); toL:SetPoint("LEFT", minB, "RIGHT", 6, 0); toL:SetText("to")
    local maxB = kit:InputBox(p, 40); maxB:SetPoint("LEFT", toL, "RIGHT", 6, 0); maxB:SetJustifyH("CENTER"); maxB:SetNumeric(true)
    minB:SetScript("OnTextChanged", function(s) filter.minL = tonumber(s:GetText()); kit:Refresh() end)
    maxB:SetScript("OnTextChanged", function(s) filter.maxL = tonumber(s:GetText()); kit:Refresh() end)
    local onl = kit:Switch(p, function() return filter.online end, function(v) filter.online = v; kit:Refresh() end)
    onl:SetPoint("TOPLEFT", LX + 580, -4)
    local onlL = kit:Text(p, 12, C.dim); onlL:SetPoint("LEFT", onl, "RIGHT", 8, 0); onlL:SetText("Online only")
    local chg = kit:Switch(p, OnlyChanges, function(v) SetOnlyChanges(v); offset = 0; kit:Refresh() end)
    chg:SetPoint("TOPLEFT", LX + 706, -4)
    local chgL = kit:Text(p, 12, C.dim); chgL:SetPoint("LEFT", chg, "RIGHT", 8, 0)
    chg.tip = "Show only the members your rules would give another rank (the ones \"Queue these changes\" would take)."
    chg:HookScript("OnEnter", function(s) GameTooltip:SetOwner(s, "ANCHOR_TOP"); GameTooltip:AddLine(s.tip, 1, 1, 1, true); GameTooltip:Show() end)
    chg:HookScript("OnLeave", function() GameTooltip:Hide() end)

    -- list
    local COLS = {
        { key = "sel", label = "", w = 24 }, { key = "name", label = "Name", w = 150 }, { key = "level", label = "Lvl", w = 40 },
        { key = "class", label = "Class", w = 92 }, { key = "rank", label = "Rank", w = 140 }, { key = "last", label = "Last seen", w = 84 },
        { key = "note", label = "Note", w = 0 },
    }
    local list = CreateFrame("Frame", nil, p)
    list:SetPoint("TOPLEFT", LX, -36); list:SetPoint("BOTTOMRIGHT", -PAD, 44)
    local lbg = kit:Fill(list, C.panel); lbg:SetAllPoints()
    kit:Border(list, 0.06)
    local head = CreateFrame("Frame", nil, list)
    head:SetPoint("TOPLEFT"); head:SetPoint("TOPRIGHT"); head:SetHeight(24)
    local hbg = kit:Fill(head, { 1, 1, 1, 0.04 }); hbg:SetAllPoints()
    local x = 6
    local headBtns = {}
    for _, c in ipairs(COLS) do
        if c.key ~= "sel" and c.key ~= "note" then
            local b = CreateFrame("Button", nil, head)
            b:SetPoint("LEFT", x, 0); b:SetSize(c.w - 4, 22)
            b.t = kit:Text(b, 12, C.dim); b.t:SetPoint("LEFT"); b.t:SetText(c.label)
            b:SetScript("OnClick", function()
                if sortKey == c.key then sortAsc = not sortAsc else sortKey, sortAsc = c.key, true end
                kit:Refresh()
            end)
            headBtns[c.key] = b
        elseif c.key == "note" then
            local t = kit:Text(head, 12, C.dim); t:SetPoint("LEFT", x, 0); t:SetText(c.label)
        end
        c.x = x
        x = x + c.w
    end
    kit:OnRefresh(function()
        for k, b in pairs(headBtns) do
            local lab
            for _, c in ipairs(COLS) do if c.key == k then lab = c.label end end
            b.t:SetText(lab .. (sortKey == k and (sortAsc and "  ^" or "  v") or ""))
            b.t:SetTextColor(unpack(sortKey == k and C.accent or C.dim))
        end
    end)

    local RH = 22
    local rows = {}
    local NROWS = 15
    local function rowsFit()
        local h = (list:GetHeight() or 400) - 26
        return math.max(5, math.floor(h / RH))
    end
    local tip = function(r)
        local m = r.m
        if not m then return end
        GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
        local cr, cg, cb = ClassColor(m.class)
        GameTooltip:AddLine(m.name, cr, cg, cb)
        GameTooltip:AddLine(string.format("Level %d %s  ·  %s", m.level, m.classDisplay, ns.RankName(m.rank)), 1, 1, 1)
        if m.zone ~= "" then GameTooltip:AddLine(m.zone, 0.7, 0.7, 0.75) end
        if m.note ~= "" then GameTooltip:AddLine("Note: " .. m.note, 0.9, 0.9, 0.7, true) end
        if m.onote ~= "" then GameTooltip:AddLine("Officer note: " .. m.onote, 0.6, 0.9, 0.6, true) end
        GameTooltip:AddLine("Last seen: " .. LastText(m.last, m.online):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""), 0.7, 0.7, 0.75)
        local to = ns.RuleTarget(m)
        if to and to ~= m.rank then GameTooltip:AddLine("Your rules say: " .. ns.RankName(to), 1, 0.6, 0.3) end
        GameTooltip:AddLine("Click: select  ·  Shift-click: select a range", 0.5, 0.5, 0.55)
        GameTooltip:Show()
    end
    for i = 1, 30 do
        local r = CreateFrame("Button", nil, list)
        r:SetHeight(RH)
        r:SetPoint("TOPLEFT", 1, -25 - (i - 1) * RH); r:SetPoint("TOPRIGHT", -1, -25 - (i - 1) * RH)
        r.zebra = kit:Fill(r, { 1, 1, 1, (i % 2 == 0) and 0.025 or 0 }); r.zebra:SetAllPoints()
        r.sel = kit:Fill(r, { C.accent[1], C.accent[2], C.accent[3], 0.14 }, "ARTWORK"); r.sel:SetAllPoints()
        r.hl = kit:Fill(r, { 1, 1, 1, 0.05 }, "ARTWORK", 1); r.hl:SetAllPoints(); r.hl:Hide()
        r.box = kit:Fill(r, C.control, "ARTWORK", 2); r.box:SetSize(12, 12); r.box:SetPoint("LEFT", 8, 0)
        r.tick = kit:Fill(r, C.accent, "ARTWORK", 3); r.tick:SetSize(8, 8); r.tick:SetPoint("CENTER", r.box)
        r.cols = {}
        for ci, c in ipairs(COLS) do
            if c.key ~= "sel" then
                local t = kit:Text(r, 12, C.text); t:SetWordWrap(false)
                t:SetPoint("LEFT", c.x, 0)
                if c.w > 0 then t:SetWidth(c.w - 6) else t:SetPoint("RIGHT", -6, 0) end
                r.cols[c.key] = t
            end
        end
        r:SetScript("OnEnter", function(s) s.hl:Show(); tip(s) end)
        r:SetScript("OnLeave", function(s) s.hl:Hide(); GameTooltip:Hide() end)
        r:SetScript("OnClick", function(s)
            local m = s.m
            if not m then return end
            if IsShiftKeyDown() and lastClicked then
                local a, b
                for vi, vm in ipairs(view) do
                    if vm == m then a = vi end
                    if vm.name == lastClicked then b = vi end
                end
                if a and b then
                    if a > b then a, b = b, a end
                    for vi = a, b do selected[view[vi].name] = true end
                end
            else
                selected[m.name] = not selected[m.name] or nil
            end
            lastClicked = m.name
            kit:Refresh()
        end)
        rows[i] = r
    end
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, d) offset = offset - d * 3; kit:Refresh() end)
    local empty = kit:Text(list, 13, C.muted); empty:SetPoint("CENTER"); empty:SetText("")
    kit:OnRefresh(function()
        BuildView()
        NROWS = rowsFit()
        offset = math.max(0, math.min(offset, #view - NROWS))
        for i, r in ipairs(rows) do
            local m = (i <= NROWS) and view[i + offset]
            r.m = m or nil
            if m then
                r.cols.name:SetText(m.short); r.cols.name:SetTextColor(ClassColor(m.class))
                if not m.online then r.cols.name:SetAlpha(0.65) else r.cols.name:SetAlpha(1) end
                r.cols.level:SetText(m.level)
                r.cols.class:SetText(m.classDisplay); r.cols.class:SetTextColor(unpack(C.dim))
                local to = ns.RuleTarget(m)
                local flag = (to and to ~= m.rank and not (ns.GuildDB() and ns.GuildDB().protected[m.rank])) and "  |cffff9a4d*|r" or ""
                r.cols.rank:SetText(ns.RankName(m.rank) .. (m.pending and "  |cff888888(sent)|r" or "") .. flag)
                r.cols.last:SetText(LastText(m.last, m.online))
                r.cols.note:SetText(m.note); r.cols.note:SetTextColor(unpack(C.muted))
                r.sel:SetShown(selected[m.name] and true or false)
                r.tick:SetShown(selected[m.name] and true or false)
                r:Show()
            else
                r:Hide()
            end
        end
        if not IsInGuild() then empty:SetText("You are not in a guild.")
        elseif #ns.members == 0 then empty:SetText("Loading the roster...")
        elseif #view == 0 and OnlyChanges() and changesN == 0 then empty:SetText("Nobody needs a new rank by your rules.")
        elseif #view == 0 then empty:SetText("Nobody matches these filters.")
        else empty:SetText("") end
    end)

    -- selection bar
    local selT = kit:Text(p, 13, C.text); selT:SetPoint("BOTTOMLEFT", LX, 14)
    kit:OnRefresh(function()
        selT:SetText(NumSelected() .. " selected  ·  " .. #view .. " shown")
        chgL:SetText("To change (" .. changesN .. ")")
        chgL:SetTextColor(unpack((changesN > 0) and { 1, 0.6, 0.3 } or C.dim))
    end)
    local bAll = kit:Button(p, "Select shown", 100, false, function() for _, m in ipairs(view) do selected[m.name] = true end; kit:Refresh() end)
    bAll:SetPoint("BOTTOMLEFT", LX + 172, 8)
    local bNone = kit:Button(p, "Clear", 60, false, function() wipe(selected); kit:Refresh() end)
    bNone:SetPoint("LEFT", bAll, "RIGHT", 6, 0)
    local bInv = kit:Button(p, "Invite", 70, false, function()
        local list = {}
        for _, m in ipairs(ns.members) do if selected[m.name] then list[#list + 1] = m end end
        if #list == 0 then ns.Print("select members first."); return end
        ns.InviteMembers(list)
    end)
    bInv:SetPoint("LEFT", bNone, "RIGHT", 6, 0)
    bInv.tip = "Invite the selected members to your group (online ones only). The group becomes a raid when needed."
    kit:OnRefresh(function() bInv:SetEnabled(NumSelected() > 0) end)
    local bulk = kit:Dropdown(p, nil, 0, 0, 170, AssignableRanks, function() return bulkRank end, function(v) bulkRank = v; kit:Refresh() end, 0)
    kit.flow[#kit.flow] = nil
    bulk:ClearAllPoints(); bulk:SetPoint("BOTTOMRIGHT", -PAD - 170, 9)
    bulk.placeholder = "choose a rank..."
    local setL = kit:Text(p, 13, C.dim); setL:SetPoint("RIGHT", bulk, "LEFT", -8, 0); setL:SetText("Set rank to")
    local bQueue = kit:Button(p, "Queue for selected", 160, true, function()
        if bulkRank == nil then ns.Print("choose a rank first."); return end
        local n, skipped = 0, 0
        for _, m in ipairs(ns.members) do
            if selected[m.name] then
                if m.rank ~= bulkRank and ns.CanSet(m, bulkRank) then ns.QueueChange(m, bulkRank, "manual"); n = n + 1
                elseif m.rank ~= bulkRank then skipped = skipped + 1 end
            end
        end
        ns.Print(n .. " change(s) queued" .. (skipped > 0 and (", " .. skipped .. " skipped (rank not below yours or no permission)") or "") .. ". Press \"Apply next\" for each one.")
        wipe(selected)
        kit:Refresh()
    end)
    bQueue:SetPoint("BOTTOMRIGHT", -PAD, 8)
    -- "To change" mode: each member goes to the rank given by the rules (selected ones, or all shown)
    local bRules = kit:Button(p, "Queue all shown", 160, true, function()
        local useSel = NumSelected() > 0
        local n, already = 0, 0
        for _, m in ipairs(view) do
            if not useSel or selected[m.name] then
                local to, why = ns.PlannedTarget(m)
                local inQueue
                for _, j in ipairs(ns.queue) do if j.name == m.name and j.to == to then inQueue = true end end
                if to and inQueue then already = already + 1
                elseif to and ns.QueueChange(m, to, why) then n = n + 1 end
            end
        end
        ns.Print(n .. " change(s) queued" .. (already > 0 and (", " .. already .. " already in the queue") or "")
            .. ". Press \"Apply next\" for each one (or the key bound to it).")
        wipe(selected)
        kit:Refresh()
    end)
    bRules:SetPoint("BOTTOMRIGHT", -PAD, 8)
    bRules.tip = "Queue the rank your rules give to each member shown (or only the selected ones)."
    kit:OnRefresh(function()
        local only = OnlyChanges()
        bRules:SetShown(only); bQueue:SetShown(not only); bulk:SetShown(not only); setL:SetShown(not only)
        if only then
            local ns_ = NumSelected()
            bRules.label:SetText(ns_ > 0 and ("Queue " .. ns_ .. " selected") or ("Queue all shown (" .. #view .. ")"))
            bRules:SetEnabled(#view > 0)
        end
    end)

    BuildRaids(pages.raids, PAD, LX)

    -- Stats tab; a click on a line opens the Roster tab filtered on it
    BuildStats(pages.stats, PAD, LX, function(kind, value, label, onlineOnly)
        search:SetText(""); filter.text = ""
        filter.rank = -1; filter.minL = nil; filter.maxL = nil
        minB:SetText(""); maxB:SetText("")
        filter.online = onlineOnly and true or false
        SetOnlyChanges(false)
        if kind == "rank" then filter.rank = value
        elseif kind == "level" then filter.minL, filter.maxL = value, value + 4; minB:SetText(value); maxB:SetText(value + 4)
        elseif kind == "class" then filter.text = label; search:SetText(label) end
        offset = 0
        kit.activeTab = "roster"
        kit:Refresh()
    end)

    -- =============================== Rules
    p = pages.rules
    kit:Caption(p, "Rules (first match wins)", LX, 0)
    local SLOTS = 8
    local RYH = 24
    local function rules() local g = ns.GuildDB(); return g and g.rules or {} end
    local function cur() local g = ns.GuildDB(); return g and g.rules[selRule] end
    local rowFS = {}
    for i = 1, SLOTS do
        local holder = CreateFrame("Frame", nil, p)
        holder:SetSize(COLW, RYH - 2)
        holder:SetPoint("TOPLEFT", LX, -22 - (i - 1) * RYH)
        kit:Flow(holder, "TOPLEFT", LX, -22 - (i - 1) * RYH, COLW)
        local function rule() local g = ns.GuildDB(); return g and g.rules[i] end
        local hl = kit:Fill(holder, { C.accent[1], C.accent[2], C.accent[3], 0.14 }); hl:SetAllPoints()
        local sw = kit:Switch(holder, function() local r = rule(); return r and r.on end, function(v) local r = rule(); if r then r.on = v; kit:Refresh() end end)
        sw:SetPoint("LEFT", 2, 0)
        local pick = CreateFrame("Button", nil, holder)
        pick:SetPoint("LEFT", sw, "RIGHT", 8, 0); pick:SetPoint("RIGHT", -28, 0); pick:SetHeight(RYH - 2)
        local txt = kit:Text(pick, 12, C.text); txt:SetPoint("LEFT"); txt:SetPoint("RIGHT"); txt:SetWordWrap(false); txt:SetJustifyH("LEFT")
        pick:SetScript("OnClick", function() selRule = i; kit:Refresh() end)
        local del = CreateFrame("Button", nil, holder); del:SetSize(22, 22); del:SetPoint("RIGHT", 0, 0)
        local dx = kit:Text(del, 15, C.muted); dx:SetPoint("CENTER"); dx:SetText("x")
        del:SetScript("OnEnter", function() dx:SetTextColor(unpack(C.bad)) end)
        del:SetScript("OnLeave", function() dx:SetTextColor(unpack(C.muted)) end)
        del:SetScript("OnClick", function()
            local g = ns.GuildDB()
            if g and g.rules[i] then
                table.remove(g.rules, i)
                if selRule > #g.rules then selRule = #g.rules end
                kit:Refresh()
            end
        end)
        kit:OnRefresh(function()
            local r = rule()
            holder:SetShown(r and true or false)
            if r then
                txt:SetText(i .. ".  " .. ns.RuleConditions(r) .. "  |cffff9a4d->|r  " .. (r.rank ~= nil and ns.RankName(r.rank) or "|cff777777(no rank)|r"))
                txt:SetTextColor(unpack(r.on and C.text or C.muted))
                hl:SetShown(selRule == i)
            end
        end)
    end
    local bAdd = kit:Button(p, "+ Add a rule", 130, false, function()
        local g = ns.GuildDB(); if not g or #g.rules >= SLOTS then return end
        g.rules[#g.rules + 1] = { on = true }
        selRule = #g.rules
        kit:Refresh()
    end)
    bAdd:SetPoint("TOPLEFT", LX, -22 - SLOTS * RYH - 4)
    kit:Flow(bAdd, "TOPLEFT", LX, -22 - SLOTS * RYH - 4)
    kit:OnRefresh(function() local g = ns.GuildDB(); bAdd:SetShown(g and #g.rules < SLOTS or false) end)

    -- editor of the selected rule
    local EY = -22 - SLOTS * RYH - 44
    local edCap = kit:Caption(p, "Edit rule", LX, EY)
    local ed = {}      -- every editor widget, to show/hide
    local function lbl(text, x, y)
        local t = kit:Text(p, 12, C.dim); t:SetPoint("TOPLEFT", LX + x, y - 6); t:SetText(text)
        kit:Flow(t, "TOPLEFT", LX + x, y - 6)
        ed[#ed + 1] = t
        return t
    end
    local function numBox(x, y, field, w)
        local b = kit:InputBox(p, w or 44); b:SetPoint("TOPLEFT", LX + x, y); b:SetJustifyH("CENTER"); b:SetNumeric(true)
        kit:Flow(b, "TOPLEFT", LX + x, y)
        local function commit() local r = cur(); if r then r[field] = tonumber(b:GetText()); kit:Refresh() end end
        b:SetScript("OnEnterPressed", function(s) s:ClearFocus(); commit() end)
        b:HookScript("OnEditFocusLost", commit)
        kit:OnRefresh(function() local r = cur(); if r and not b:HasFocus() then b:SetText(r[field] or "") end end)
        ed[#ed + 1] = b
        return b
    end
    local function textBox(x, y, field, w)
        local b = kit:InputBox(p, w); b:SetPoint("TOPLEFT", LX + x, y)
        kit:Flow(b, "TOPLEFT", LX + x, y)
        b:SetMaxLetters(60)
        local function commit() local r = cur(); if r then local t = b:GetText() or ""; r[field] = t ~= "" and t or nil; kit:Refresh() end end
        b:SetScript("OnEnterPressed", function(s) s:ClearFocus(); commit() end)
        b:HookScript("OnEditFocusLost", commit)
        kit:OnRefresh(function() local r = cur(); if r and not b:HasFocus() then b:SetText(r[field] or "") end end)
        ed[#ed + 1] = b
        return b
    end
    local function fixedDD(x, y, w, items, get, set)
        local d = kit:Dropdown(p, nil, LX + x, y, w, items, get, set, 0)
        kit.flow[#kit.flow] = nil
        d:ClearAllPoints(); d:SetPoint("TOPLEFT", LX + x, y)
        ed[#ed + 1] = d
        return d
    end
    local y1 = EY - 22
    lbl("Give rank", 0, y1)
    local dd = fixedDD(96, y1, COLW - 96, AssignableRanks,
        function() local r = cur(); return r and r.rank end, function(v) local r = cur(); if r then r.rank = v; kit:Refresh() end end)
    dd.placeholder = "choose a rank..."
    local y2 = y1 - 30
    lbl("Level", 0, y2); numBox(96, y2, "min"); lbl("to", 146, y2); numBox(166, y2, "max")
    lbl("Class", 224, y2)
    fixedDD(262, y2, COLW - 262, ClassItems,
        function() local r = cur(); return (r and type(r.class) == "string") and r.class or "ANY" end,
        function(v) local r = cur(); if r then r.class = (v ~= "ANY") and v or nil; kit:Refresh() end end)
    local y3 = y2 - 30
    lbl("Member days", 0, y3); numBox(96, y3, "sinceMin"); lbl("to", 146, y3); numBox(166, y3, "sinceMax")
    lbl("Offline over", 224, y3); numBox(300, y3, "offDays"); lbl("days", 350, y3)
    local y4 = y3 - 30
    lbl("Now has rank", 0, y4)
    fixedDD(96, y4, COLW - 96, function() return AllRanks(false, "Any rank") end,
        function() local r = cur(); return r and r.fromRank or -1 end,
        function(v) local r = cur(); if r then r.fromRank = (v >= 0) and v or nil; kit:Refresh() end end)
    local y5 = y4 - 30
    lbl("Note has", 0, y5); textBox(96, y5, "note", 110)
    lbl("Officer note", 216, y5); textBox(292, y5, "onote", COLW - 292)
    local rh = kit:Hint(p, "", LX, y5 - 34, COLW)
    kit:OnRefresh(function()
        local has = cur() and true or false
        edCap:SetText(has and ("EDIT RULE " .. selRule) or "EDIT RULE")
        for _, w in ipairs(ed) do w:SetShown(has) end
        local g = ns.GuildDB()
        local since = g and g.trackingSince and date and date("%d/%m/%Y", g.trackingSince) or "?"
        rh:SetText((has and "Empty field = no condition; every filled field must match. " or "Add a rule to start. ") ..
            "Member days count from the first time Free Guild saw the member (the game gives no join date; everybody already in the guild counts from " .. since .. "). Rules only give ranks below yours and skip protected ranks.")
    end)

    kit:Caption(p, "Never change these ranks", RX, 0)
    local rankSw = {}
    for r = 0, 9 do
        local s = kit:SwitchRow(p, "", RX, -22 - r * 26, COLW,
            function() local g = ns.GuildDB(); return g and g.protected[r] end,
            function(v) local g = ns.GuildDB(); if g then g.protected[r] = v or nil; kit:Refresh() end end)
        rankSw[r] = s
        kit:OnRefresh(function()
            local exists = r < ns.NumRanks()
            s:SetShown(exists); s.labelFS:SetShown(exists)
            if exists then s.labelFS:SetText((r + 1) .. ". " .. ns.RankName(r) .. ((ns.MyRank() and r <= ns.MyRank()) and "  |cff777777(yours or above)|r" or "")) end
        end)
    end
    local oy = -22 - 10 * 26 - 14
    kit:Caption(p, "Options", RX, oy)
    kit:SwitchRow(p, "Rules may also demote", RX, oy - 22, COLW,
        function() local g = ns.GuildDB(); return g and g.allowDemote end, function(v) local g = ns.GuildDB(); if g then g.allowDemote = v; kit:Refresh() end end)
    kit:SwitchRow(p, "Remind me at login", RX, oy - 22 - 30, COLW,
        function() local g = ns.GuildDB(); return g and g.remind end, function(v) local g = ns.GuildDB(); if g then g.remind = v end end)
    local planT = kit:Text(p, 13, C.text); planT:SetPoint("TOPLEFT", RX, oy - 22 - 72)
    kit:Flow(planT, "TOPLEFT", RX, oy - 22 - 72)
    local bPlan = kit:Button(p, "Queue these changes", 170, true, function()
        local plan = ns.PlanRules()
        for _, c in ipairs(plan) do ns.QueueChange(c.m, c.to, c.why) end
        ns.Print(#plan .. " change(s) queued. Press \"Apply next\" for each one (or the key bound to it).")
        kit.activeTab = "queue"
        kit:Refresh()
    end)
    bPlan:SetPoint("TOPLEFT", RX, oy - 22 - 98)
    kit:Flow(bPlan, "TOPLEFT", RX, oy - 22 - 98)
    local bExp = kit:Button(p, "Export", 80, false, function() ns.ExportRules() end)
    bExp:SetPoint("LEFT", bPlan, "RIGHT", 8, 0)
    local bImp = kit:Button(p, "Import", 80, false, function() ns.ImportRules() end)
    bImp:SetPoint("LEFT", bExp, "RIGHT", 6, 0)
    kit:OnRefresh(function()
        local n = #ns.PlanRules()
        planT:SetText(n == 0 and "Nobody needs a new rank." or (n .. " member(s) would get a new rank."))
        bPlan:SetEnabled(n > 0)
    end)

    -- =============================== Queue & log
    p = pages.queue
    kit:Caption(p, "Waiting to be applied", LX, 0)
    kit:Caption(p, "Done", RX, 0)
    local function Lines(x, getLines)
        local box = CreateFrame("Frame", nil, p)
        box:SetPoint("TOPLEFT", x, -22); box:SetSize(COLW, 380)
        kit:Flow(box, "TOPLEFT", x, -22, COLW)
        local bgx = kit:Fill(box, C.panel); bgx:SetAllPoints()
        kit:Border(box, 0.06)
        local fs, off = {}, 0
        for i = 1, 17 do
            local t = kit:Text(box, 12, C.text); t:SetWordWrap(false)
            t:SetPoint("TOPLEFT", 8, -6 - (i - 1) * 22); t:SetPoint("RIGHT", -8, 0)
            fs[i] = t
        end
        box:EnableMouseWheel(true)
        box:SetScript("OnMouseWheel", function(_, d) off = off - d * 3; kit:Refresh() end)
        kit:OnRefresh(function()
            local lines = getLines()
            off = math.max(0, math.min(off, #lines - #fs))
            for i, t in ipairs(fs) do t:SetText(lines[i + off] or "") end
            if #lines == 0 then fs[1]:SetText("|cff777777(empty)|r") end
        end)
        return box
    end
    Lines(LX, function()
        local out = {}
        for i, j in ipairs(ns.queue) do
            out[#out + 1] = string.format("%d.  %s   %s |cffff9a4d->|r %s   |cff777777%s|r", i, j.short or ns.Short(j.name), ns.RankName(j.from), ns.RankName(j.to), j.why or "")
        end
        return out
    end)
    Lines(RX, function()
        local out = {}
        local g = ns.GuildDB()
        for _, e in ipairs(g and g.log or {}) do
            out[#out + 1] = "|cff777777" .. (date and date("%d/%m %H:%M", e.t) or "") .. "|r  " .. e.text
        end
        return out
    end)
    kit:Hint(p, "One rank step per click or key press, sent with the game's /gpromote and /gdemote. Use \"Apply next\" below, or bind a key to \"Apply the next rank change\" (Key Bindings > AddOns > Free Guild).", LX, -412, W - 2 * PAD)

    -- =============================== Guild (MOTD, info text, member notes, bank)
    p = pages.guild
    -- text box that does not overwrite what you are typing; key = what it shows (changes -> reload text)
    local function Sync(box, value, key)
        value = value or ""
        if box.syncKey ~= key then box.syncKey = key; box.dirty = false; box:SetText(value)
        elseif not box.dirty and not box:HasFocus() and box:GetText() ~= value then box:SetText(value) end
    end
    local function Dirty(box) box:HookScript("OnTextChanged", function(s, user) if user then s.dirty = true end end) end

    kit:Caption(p, "Message of the day", LX, 0)
    local motd = kit:InputBox(p, COLW); motd:SetPoint("TOPLEFT", LX, -22); kit:Flow(motd, "TOPLEFT", LX, -22, COLW)
    motd:SetMaxLetters(128); Dirty(motd)
    local bMotd = kit:Button(p, "Set message", 130, true, function()
        if ns.SetMOTD(motd:GetText() or "") then motd.dirty = false end
    end)
    bMotd:SetPoint("TOPLEFT", LX, -54); kit:Flow(bMotd, "TOPLEFT", LX, -54)
    -- fallback when the game refuses addons: the game's own /gmotd through a secure button
    local bMotdSecure = kit:Button(p, "Set with /gmotd", 150, true, function() motd.dirty = false end)
    bMotdSecure:SetPoint("TOPLEFT", LX, -54); kit:Flow(bMotdSecure, "TOPLEFT", LX, -54)
    local sMotd = ns.MakeMacroButton("FreeGuildMotdButton", bMotdSecure, function()
        local t = motd:GetText() or ""
        if t == "" then ns.Print("type a message first."); return nil end
        return "/gmotd " .. t
    end)
    sMotd:SetAllPoints(bMotdSecure)
    local motdHint = kit:Hint(p, "", LX + 160, -58, COLW - 160)
    kit:OnRefresh(function()
        local can = ns.CanEditMOTD()
        local refused = ns.refused.motd
        bMotd:SetShown(not refused); bMotd:SetEnabled(can)
        if not InCombatLockdown() then bMotdSecure:SetShown(refused and true or false); end
        motdHint:SetText(not can and "Your rank cannot edit the message." or (refused and "The game refuses addons to set it; this button sends /gmotd for you." or ""))
        Sync(motd, ns.GetMOTD(), "motd")
    end)

    kit:Caption(p, "Guild information", LX, -100)
    local infoBox = CreateFrame("Frame", nil, p)
    infoBox:SetPoint("TOPLEFT", LX, -122); infoBox:SetSize(COLW, 150)
    kit:Flow(infoBox, "TOPLEFT", LX, -122, COLW)
    local ibg = kit:Fill(infoBox, C.control); ibg:SetAllPoints()
    kit:Border(infoBox, 0.08)
    local info = CreateFrame("EditBox", nil, infoBox)
    info:SetMultiLine(true); info:SetAutoFocus(false); info:SetMaxLetters(500)
    info:SetPoint("TOPLEFT", 8, -6); info:SetPoint("BOTTOMRIGHT", -8, 6)
    UI.SetFont(info, 12); info:SetTextColor(unpack(C.text))
    info:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
    Dirty(info)
    local bInfo = kit:Button(p, "Save information", 150, true, function()
        if ns.SetInfoText(info:GetText() or "") then info.dirty = false end
    end)
    bInfo:SetPoint("TOPLEFT", LX, -282); kit:Flow(bInfo, "TOPLEFT", LX, -282)
    local infoHint = kit:Hint(p, "", LX + 160, -287, COLW - 160)
    kit:OnRefresh(function()
        local can = ns.CanEditInfo()
        bInfo:SetEnabled(can)
        local handOff = ns.refused and ns.refused.info
        if bInfo.label then bInfo.label:SetText(handOff and "Copy for the game" or "Save information") end
        infoHint:SetText(not can and "Your rank cannot edit the guild information."
            or (handOff and "The game only accepts it from its own window: copy, then paste it there." or ""))
        Sync(info, ns.GetInfoText(), "info")
    end)

    -- member notes: the member you clicked last in the Roster tab
    kit:Caption(p, "Member notes", RX, 0)
    local who = kit:Text(p, 13, C.text); who:SetPoint("TOPLEFT", RX, -22); who:SetPoint("RIGHT", p, "TOPLEFT", RX + COLW, 0); who:SetWordWrap(false)
    kit:Flow(who, "TOPLEFT", RX, -22, COLW)
    local function target() return lastClicked and ns.FindMember(nil, lastClicked) end
    local function NoteEditor(label, y, officer)
        local l = kit:Text(p, 12, C.dim); l:SetPoint("TOPLEFT", RX, y); l:SetText(label); kit:Flow(l, "TOPLEFT", RX, y)
        local b = kit:InputBox(p, COLW - 80); b:SetPoint("TOPLEFT", RX, y - 18); kit:Flow(b, "TOPLEFT", RX, y - 18, COLW - 80)
        b:SetMaxLetters(31); Dirty(b)
        local save = kit:Button(p, "Save", 70, true, function()
            local m = target()
            if m and ns.SetNote(m, b:GetText() or "", officer) then b.dirty = false end
        end)
        save:SetPoint("TOPLEFT", RX + COLW - 70, y - 18); kit:Flow(save, "TOPLEFT", RX + COLW - 70, y - 18)
        kit:OnRefresh(function()
            local m = target()
            local can = ns.CanEditNote(officer)
            save:SetEnabled(m and can and true or false)
            b:SetEnabled(m and true or false)
            Sync(b, m and (officer and m.onote or m.note) or "", m and m.name or "")
        end)
    end
    NoteEditor("Public note", -52, false)
    NoteEditor("Officer note", -100, true)
    local nHint = kit:Hint(p, "", RX, -150, COLW)
    kit:OnRefresh(function()
        local m = target()
        if m then
            who:SetText(m.short .. "  |cff888888" .. ns.RankName(m.rank) .. "  ·  level " .. m.level .. "|r"); who:SetTextColor(ClassColor(m.class))
        else who:SetText("No member picked"); who:SetTextColor(unpack(C.muted)) end
        local msg = m and "" or "Click a member in the Roster tab, then come back here. "
        if not ns.CanEditNote(false) then msg = msg .. "Your rank cannot edit public notes. " end
        if not ns.CanEditNote(true) then msg = msg .. "Your rank cannot edit officer notes." end
        nHint:SetText(msg)
    end)

    kit:Caption(p, "Guild bank", RX, -200)
    local bank = kit:Text(p, 14, C.text); bank:SetPoint("TOPLEFT", RX, -224); bank:SetPoint("RIGHT", p, "TOPLEFT", RX + COLW, 0)
    bank:SetWordWrap(false); kit:Flow(bank, "TOPLEFT", RX, -224, COLW)
    local bRead = kit:Button(p, "Read now", 110, false, function()
        ns.RecordBank(true)
        if not (ns.GuildDB() and ns.GuildDB().bank and ns.GuildDB().bank.money) then ns.Print("open the guild bank first, the game only gives the money while it is open.") end
    end)
    bRead:SetPoint("TOPLEFT", RX, -252); kit:Flow(bRead, "TOPLEFT", RX, -252)
    kit:Hint(p, "Recorded each time you open the guild bank. The game only gives the amount while the bank window is open.", RX + 120, -257, COLW - 120)
    kit:OnRefresh(function() bank:SetText(ns.BankText()) end)

    -- =============================== footer
    local status = kit:Text(footer, 12, C.muted); status:SetPoint("LEFT", PAD, 0); status:SetPoint("RIGHT", -440, 0); status:SetWordWrap(false)
    local bNext = kit:Button(footer, "Apply next", 170, true, function() end)
    bNext:SetPoint("RIGHT", -PAD, 0)
    local sNext = ns.MakeApplyButton("FreeGuildApplyButtonUI", bNext)   -- secure layer over the button
    sNext:SetAllPoints(bNext)
    sNext:HookScript("PostClick", function() kit:Refresh() end)
    local bClear = kit:Button(footer, "Clear queue", 110, false, function() ns.ClearQueue() end)
    bClear:SetPoint("RIGHT", bNext, "LEFT", -8, 0)
    local bRef = kit:Button(footer, "Refresh roster", 120, false, function() ns.RequestRoster() end)
    bRef:SetPoint("RIGHT", bClear, "LEFT", -8, 0)
    -- only when the game refuses direct invites: one /invite per click
    local bInvNext = kit:Button(footer, "Invite next", 150, true, function() end)
    bInvNext:SetPoint("LEFT", PAD, 0)
    local sInv = ns.MakeMacroButton("FreeGuildInviteButton", bInvNext, function() return ns.InviteNextMacro() end)
    sInv:SetAllPoints(bInvNext)
    sInv:HookScript("PostClick", function() kit:Refresh() end)
    kit:OnRefresh(function()
        if InCombatLockdown() then return end      -- secure button: no show / hide in combat
        local on = ns.inviteManual and #ns.invites > 0
        bInvNext:SetShown(on and true or false); sInv:SetShown(on and true or false)
        if on then bInvNext.label:SetText("Invite next  (" .. #ns.invites .. ")") end
        status:ClearAllPoints()
        status:SetPoint("LEFT", on and (PAD + 160) or PAD, 0); status:SetPoint("RIGHT", -440, 0)
    end)
    kit:OnRefresh(function()
        local n = #ns.queue
        bNext.label:SetText(n > 0 and ("Apply next  (" .. n .. ")") or "Apply next")
        bNext:SetEnabled(n > 0)
        bClear:SetEnabled(n > 0)
        local perm = (ns.MyRank() == nil) and "Not in a guild."
            or ((not ns.CanPromote() and not ns.CanDemote()) and "Your rank cannot change ranks." or nil)
        status:SetText(perm or (ns.lastDone and ("Last: " .. ns.lastDone) or "Select members, choose a rank, queue, then apply one by one."))
    end)
end

kit.o.tabs = { { "roster", "Roster" }, { "stats", "Stats" }, { "raids", "Raids" }, { "rules", "Rules" }, { "guild", "Guild" }, { "queue", "Queue & log" } }

local function DoBuild() if not kit.frame then Build() end end

-- ------------------------------------------------------------ public
ns.OnChanged = function() kit:Refresh() end

local inHub = kit:RegisterHub("FreeGuild", DoBuild, function(show) if ns.ApplyMinimapVisibility then ns.ApplyMinimapVisibility(show) end end)

ns.ToggleConfig = function()
    if not ns.GetDB() then return end
    ns.RequestRoster()
    ns.RequestGuildInfo()
    kit:Toggle("FreeGuild", DoBuild)
end
function FreeGuild_Toggle() ns.ToggleConfig() end
