-- Free Guild - group invites, raid rosters and raid attendance.
--
-- Invites: the addon invites directly (C_PartyInfo.InviteUnit). If the game refuses it, the names
-- stay in a list and the "Invite next" button sends them one per click (/invite, secure button).
-- A group of 5 is turned into a raid as soon as more people are waiting than it can hold.

local ADDON, ns = ...

local function Clock() return GetTime and GetTime() or 0 end
local function Changed() if ns.OnChanged then ns.OnChanged() end end

-- ------------------------------------------------------------ group helpers
local function InGroupNow() return IsInGroup and IsInGroup() or false end
local function InRaidNow() return IsInRaid and IsInRaid() or false end
local function GroupSize() local n = GetNumGroupMembers and GetNumGroupMembers() or 0; return math.max(n, 1) end
local function IsLead()
    if not InGroupNow() then return true end
    return (UnitIsGroupLeader and UnitIsGroupLeader("player")) or (UnitIsGroupAssistant and UnitIsGroupAssistant("player")) or false
end

-- names (short and full) of everybody in my group, me included
function ns.GroupNames()
    local out = {}
    local function add(n) if n then out[n] = true; out[ns.Short(n)] = true end end
    add(UnitName and UnitName("player"))
    local n = GetNumGroupMembers and GetNumGroupMembers() or 0
    if InRaidNow() and GetRaidRosterInfo then
        for i = 1, n do add((GetRaidRosterInfo(i))) end
    elseif UnitName then
        for i = 1, 4 do
            local nm, realm = UnitName("party" .. i)
            if nm then add(nm); if realm and realm ~= "" then add(nm .. "-" .. realm) end end
        end
    end
    return out
end

-- ------------------------------------------------------------ invites
ns.invites = {}          -- full names waiting to be invited, in order
ns.inviteManual = false  -- true once the game refused an invite from the addon: use the button
local sent = {}          -- [full name] = time the invite went out (waiting for an answer)
local SENT_TTL = 60      -- an invite not answered after this is no longer counted

local function InviteFn() return (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit end
local function ConvertFn() return (C_PartyInfo and C_PartyInfo.ConvertToRaid) or ConvertToRaid end

local function Pending()
    local n, now = 0, Clock()
    local inGroup = ns.GroupNames()
    for name, t in pairs(sent) do
        if inGroup[name] or inGroup[ns.Short(name)] or now - t > SENT_TTL then sent[name] = nil else n = n + 1 end
    end
    return n
end

local function Room()
    local max = InRaidNow() and 40 or 5
    return max - GroupSize() - Pending()
end

local converting, toldConvert, toldLead = false, false, false

function ns.ProcessInvites()
    if #ns.invites == 0 or ns.inviteManual then Changed(); return end
    if InCombatLockdown and InCombatLockdown() then return end
    if not IsLead() then
        if not toldLead then ns.Print("only the group leader or an assistant can invite."); toldLead = true end
        Changed(); return
    end
    -- more people waiting than a group of 5 can hold: become a raid (needs at least one member)
    if not InRaidNow() and #ns.invites > Room() and InGroupNow() and GroupSize() > 1 and not converting then
        local ok, why = ns.TryProtected("convert", ConvertFn())
        if ok then converting = true; return end      -- wait for GROUP_ROSTER_UPDATE
        if not toldConvert then
            toldConvert = true
            ns.Print("could not turn the group into a raid (" .. tostring(why) .. "). Do it in the game (right-click your portrait), the rest will follow.")
        end
    end
    local room = Room()
    local inGroup = ns.GroupNames()
    while room > 0 and #ns.invites > 0 do
        local name = table.remove(ns.invites, 1)
        if not (inGroup[name] or inGroup[ns.Short(name)]) then
            local ok, why = ns.TryProtected("invite", InviteFn(), name)
            if ok then
                sent[name] = Clock(); room = room - 1
            elseif why == "refused" then
                table.insert(ns.invites, 1, name)
                ns.inviteManual = true
                ns.Print("the game refused invites from an addon: press \"Invite next\" for each one (" .. #ns.invites .. " waiting).")
                break
            else
                ns.Print("could not invite " .. ns.Short(name) .. " (" .. tostring(why) .. ").")
            end
        end
    end
    if #ns.invites > 0 and not ns.inviteManual and C_Timer and C_Timer.After then
        C_Timer.After(SENT_TTL + 1, ns.ProcessInvites)      -- unanswered invites free their place
    end
    Changed()
end

-- invite these members (member tables). Skips me, offline members and people already in my group.
-- returns added, skippedOffline
function ns.InviteMembers(list)
    local me = UnitName and UnitName("player")
    local inGroup = ns.GroupNames()
    local added, offline = 0, 0
    for _, m in ipairs(list) do
        if m.short ~= me and not (inGroup[m.name] or inGroup[m.short]) then
            if not m.online then offline = offline + 1
            else
                local dup
                for _, n in ipairs(ns.invites) do if n == m.name then dup = true end end
                if not dup and not sent[m.name] then ns.invites[#ns.invites + 1] = m.name; added = added + 1 end
            end
        end
    end
    toldConvert, toldLead = false, false
    ns.Print(added .. " invite(s)" .. (offline > 0 and (", " .. offline .. " offline skipped") or "") .. ".")
    ns.ProcessInvites()
    return added, offline
end

function ns.ClearInvites() wipe(ns.invites); ns.inviteManual = false; Changed() end

-- "Invite next" (secure button, one /invite per click) when the game refuses direct invites
function ns.InviteNextMacro()
    local inGroup = ns.GroupNames()
    while #ns.invites > 0 do
        local name = table.remove(ns.invites, 1)
        if not (inGroup[name] or inGroup[ns.Short(name)]) then
            sent[name] = Clock()
            if #ns.invites == 0 then ns.inviteManual = false end
            return "/invite " .. name
        end
    end
    ns.inviteManual = false
end

-- ------------------------------------------------------------ raid rosters
-- gdb.raids = { list = { { name, members = { [full name] = { role, bench, excused } }, events = { { t, s = { [full name] = "P"|"A"|"E"|"B" } } } } }, cur }
local MAX_EVENTS = 100
ns.ROLES = { "TANK", "HEALER", "DAMAGER" }
ns.ROLE_LABEL = { TANK = "Tank", HEALER = "Heal", DAMAGER = "DPS" }
ns.STATUS_LABEL = { P = "Present", A = "Absent", E = "Excused", B = "Bench" }

function ns.RaidDB()
    local g = ns.GuildDB()
    if not g then return nil end
    g.raids = type(g.raids) == "table" and g.raids or {}
    local r = g.raids
    r.list = type(r.list) == "table" and r.list or {}
    if #r.list == 0 then r.list[1] = { name = "Roster 1", members = {}, events = {} } end
    for _, ro in ipairs(r.list) do ro.members = ro.members or {}; ro.events = ro.events or {} end
    if type(r.cur) ~= "number" or not r.list[r.cur] then r.cur = 1 end
    return r
end

function ns.CurRoster() local r = ns.RaidDB(); return r and r.list[r.cur] end

function ns.NewRoster()
    local r = ns.RaidDB(); if not r then return end
    local n = #r.list + 1
    local name = "Roster " .. n
    local used = {}; for _, ro in ipairs(r.list) do used[ro.name] = true end
    while used[name] do n = n + 1; name = "Roster " .. n end
    r.list[#r.list + 1] = { name = name, members = {}, events = {} }
    r.cur = #r.list
    Changed()
end

function ns.RenameRoster(name)
    local ro = ns.CurRoster()
    name = (name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if ro and name ~= "" then ro.name = name; Changed() end
end

function ns.DeleteRoster()
    local r = ns.RaidDB(); if not r then return end
    table.remove(r.list, r.cur)
    r.cur = math.max(1, r.cur - 1)
    ns.RaidDB()      -- recreates "Roster 1" when the last one was deleted
    Changed()
end

function ns.AddToRoster(list)
    local ro = ns.CurRoster(); if not ro then return 0 end
    local n = 0
    for _, m in ipairs(list) do
        if not ro.members[m.name] then ro.members[m.name] = {}; n = n + 1 end
    end
    Changed()
    return n
end

function ns.RemoveFromRoster(name)
    local ro = ns.CurRoster(); if ro then ro.members[name] = nil; Changed() end
end

local function cycle(list, v)
    for i, x in ipairs(list) do if x == v then return list[i + 1] end end
    return list[1]
end
function ns.CycleRole(name)
    local ro = ns.CurRoster(); local e = ro and ro.members[name]; if not e then return end
    e.role = cycle(ns.ROLES, e.role); Changed()
end
function ns.ToggleBench(name)
    local ro = ns.CurRoster(); local e = ro and ro.members[name]; if not e then return end
    e.bench = (not e.bench) or nil; Changed()
end
function ns.ToggleExcused(name)
    local ro = ns.CurRoster(); local e = ro and ro.members[name]; if not e then return end
    e.excused = (not e.excused) or nil; Changed()
end

-- status of a member at the last raid (nil if not recorded)
function ns.LastStatus(ro, name)
    local ev = ro and ro.events[#ro.events]
    return ev and ev.s[name]
end
-- fix the last raid by hand: Present -> Absent -> Excused -> Bench -> Present
function ns.CycleLastStatus(name)
    local ro = ns.CurRoster(); local ev = ro and ro.events[#ro.events]
    if not ev then return end
    ev.s[name] = cycle({ "P", "A", "E", "B" }, ev.s[name]) or "P"   -- after Bench (or unrecorded): back to Present
    Changed()
end

-- attendance: present, counted (present + absent; excused and bench are not counted), raids recorded for him
function ns.Attendance(ro, name)
    local p, c, n = 0, 0, 0
    for _, ev in ipairs(ro and ro.events or {}) do
        local s = ev.s[name]
        if s then
            n = n + 1
            if s == "P" then p = p + 1; c = c + 1 elseif s == "A" then c = c + 1 end
        end
    end
    return p, c, n
end

-- record a raid: present = in my group now; absent ones are "Excused" if marked so, "Bench" if on the bench
function ns.TakeAttendance()
    local ro = ns.CurRoster()
    if not ro then return end
    if not InGroupNow() then ns.Print("you are not in a group: nothing to record."); return end
    if not next(ro.members) then ns.Print("this roster is empty."); return end
    local inGroup = ns.GroupNames()
    local ev = { t = time and time() or 0, s = {} }
    local cnt = { P = 0, A = 0, E = 0, B = 0 }
    for name, e in pairs(ro.members) do
        local s
        if inGroup[name] or inGroup[ns.Short(name)] then s = "P"
        elseif e.excused then s = "E"
        elseif e.bench then s = "B"
        else s = "A" end
        e.excused = nil                    -- an excuse is for one raid
        ev.s[name] = s
        cnt[s] = cnt[s] + 1
    end
    ro.events[#ro.events + 1] = ev
    while #ro.events > MAX_EVENTS do table.remove(ro.events, 1) end
    ns.Print(string.format("%s: raid recorded - %d present, %d absent, %d excused, %d bench.", ro.name, cnt.P, cnt.A, cnt.E, cnt.B))
    Changed()
    return cnt
end

function ns.UndoAttendance()
    local ro = ns.CurRoster()
    if ro and #ro.events > 0 then
        table.remove(ro.events)
        ns.Print(ro.name .. ": last raid removed.")
        Changed()
    end
end

-- ------------------------------------------------------------ events
local f = CreateFrame("Frame")
f:RegisterEvent("GROUP_ROSTER_UPDATE")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:SetScript("OnEvent", function(_, event)
    if event == "GROUP_ROSTER_UPDATE" then converting = false; Pending() end   -- forget invites that were accepted
    if #ns.invites > 0 and not ns.inviteManual then
        if C_Timer and C_Timer.After then C_Timer.After(0.3, ns.ProcessInvites) else ns.ProcessInvites() end
    end
    Changed()
end)
