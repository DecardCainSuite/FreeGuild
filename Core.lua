-- Free Guild - roster, ranks and level rules for guild leaders and officers.
--
-- Rank changes are restricted by the game: each one has to come from a click or a key press.
-- So changes are put in a queue, and every click on "Apply next" (or the key bound to it)
-- sends one. Nothing is ever changed without you pressing something.

local ADDON, ns = ...
local PREFIX = "|cffff8a3dFree Guild|r: "
function ns.Print(msg) print(PREFIX .. msg) end

local db, gdb          -- saved variables, settings of the current guild
ns.members = {}        -- current roster (see Scan)
ns.ranks = {}          -- [rankIndex 0..n-1] = name
ns.queue = {}          -- pending rank changes
local lastScan = 0

-- ------------------------------------------------------------ helpers
local function GuildKey()
    local name, _, _, realm = GetGuildInfo("player")
    if not name then return nil end
    return name .. " - " .. (realm or (GetRealmName and GetRealmName()) or "?")
end

local function Short(name) return name and (name:match("^([^%-]+)") or name) or "?" end
ns.Short = Short

function ns.GetDB() return db end
function ns.GuildDB() return gdb end

local GUILD_DEFAULTS = {
    rules = {
        -- level ranges -> rank (rank index: 0 = guild master)
    },
    protected = {},          -- [rankIndex] = true: members of these ranks are never changed by rules
    allowDemote = false,     -- rules may also move people down
    remind = true,           -- tell me when members need a new rank
    log = {},
    firstSeen = {},          -- [guid or name] = time() we first saw this member in the roster ("member since")
    bank = {},               -- last known guild bank money: { money = copper, t = time() }
}

local function Prepare(g)
    for k, v in pairs(GUILD_DEFAULTS) do
        if g[k] == nil then g[k] = type(v) == "table" and {} or v end
    end
    return g
end

local function UseGuild()
    local key = GuildKey()
    if not key or not db then gdb = nil; return end
    db.guilds[key] = Prepare(db.guilds[key] or {})
    gdb = db.guilds[key]
    -- the game gives no join date: we count from the first time this version saw each member
    if not gdb.trackingSince then gdb.trackingSince = time and time() or 0 end
end

-- ------------------------------------------------------------ permissions
function ns.MyRank()
    local _, _, idx = GetGuildInfo("player")
    return idx
end
function ns.IsGuildMaster()
    return (IsGuildLeader and IsGuildLeader()) or ns.MyRank() == 0
end
function ns.CanPromote() return (not CanGuildPromote) or CanGuildPromote() end
function ns.CanDemote() return (not CanGuildDemote) or CanGuildDemote() end

-- can I move this member to that rank? (returns ok, reason)
function ns.CanSet(m, to)
    local my = ns.MyRank()
    if not my then return false, "not in a guild" end
    if not m or to == nil then return false, "?" end
    if m.rank == to then return false, "already" end
    if m.rank <= my then return false, "same or higher rank than you" end
    if to <= my then return false, "rank not below yours" end
    if to < m.rank and not ns.CanPromote() then return false, "no promote permission" end
    if to > m.rank and not ns.CanDemote() then return false, "no demote permission" end
    return true
end

-- ------------------------------------------------------------ roster
local function Now() return time and time() or 0 end
local function Clock() return GetTime and GetTime() or 0 end

-- first time we see a member (by GUID, fallback name) = "member since"
function ns.TrackFirstSeen()
    if not gdb or #ns.members == 0 then return end
    local fs = gdb.firstSeen
    local now = Now()
    for _, m in ipairs(ns.members) do
        local t
        if m.guid then
            t = fs[m.guid]
            if not t and fs[m.name] then t = fs[m.name]; fs[m.guid] = t; fs[m.name] = nil end   -- upgrade name -> GUID
            if not t then t = now; fs[m.guid] = t end
        else
            t = fs[m.name]
            if not t then t = now; fs[m.name] = t end
        end
        m.firstSeen = t
    end
end

-- days since we first saw the member (nil when unknown)
function ns.MemberDays(m)
    if not m or not m.firstSeen then return nil end
    return math.max(0, math.floor((Now() - m.firstSeen) / 86400))
end

function ns.RequestRoster()
    if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster()
    elseif GuildRoster then GuildRoster() end
end

local function LastOnlineHours(i, online)
    if online then return 0 end
    if not GetGuildRosterLastOnline then return nil end
    local y, mo, d, h = GetGuildRosterLastOnline(i)
    if not y then return nil end
    return (y * 365 + mo * 30 + d) * 24 + (h or 0)
end

function ns.Scan()
    wipe(ns.members)
    wipe(ns.ranks)
    if not IsInGuild() then return end
    local nr = GuildControlGetNumRanks and GuildControlGetNumRanks() or 0
    for r = 1, nr do ns.ranks[r - 1] = GuildControlGetRankName(r) end
    local total = GetNumGuildMembers() or 0
    for i = 1, total do
        local name, rankName, rankIndex, level, classDisplay, zone, note, onote, online, status, class,
              _, _, isMobile, _, _, guid = GetGuildRosterInfo(i)
        if name then
            ns.members[#ns.members + 1] = {
                index = i, name = name, short = Short(name), rank = rankIndex or 0, rankName = rankName or "",
                level = level or 0, classDisplay = classDisplay or "", class = class, zone = zone or "",
                note = note or "", onote = onote or "", online = online and true or false, mobile = isMobile,
                guid = guid, last = LastOnlineHours(i, online),
            }
            if rankIndex and not ns.ranks[rankIndex] then ns.ranks[rankIndex] = rankName end
        end
    end
    lastScan = GetTime and GetTime() or 0
    ns.TrackFirstSeen()
    ns.Reconcile()
end

function ns.NumRanks()
    local n = 0
    for r in pairs(ns.ranks) do if r + 1 > n then n = r + 1 end end
    return n
end
function ns.RankName(r) return ns.ranks[r] or ("Rank " .. tostring((r or 0) + 1)) end

function ns.FindMember(guid, name)
    for _, m in ipairs(ns.members) do
        if (guid and m.guid == guid) or (name and m.name == name) then return m end
    end
end

-- ------------------------------------------------------------ rules
-- rule = { on, rank, then optional conditions (a missing field = no condition, all given ones must match):
--   min, max          level range
--   class             class token ("WARRIOR") or a table { WARRIOR = true, ... }
--   fromRank          the member currently has this rank index
--   sinceMin, sinceMax  days since we first saw the member (member since)
--   offDays           offline for at least N days
--   note, onote       public / officer note contains this text (not case sensitive) }
local function Lower(s) return (s or ""):lower() end

function ns.RuleMatches(r, m)
    if not r or not r.on or r.rank == nil or not m then return false end
    local lv = m.level or 0
    if r.min and lv < r.min then return false end
    if r.max and lv > r.max then return false end
    if r.class then
        if type(r.class) == "table" then
            if not r.class[m.class or ""] then return false end
        elseif r.class ~= m.class then return false end
    end
    if r.fromRank ~= nil and m.rank ~= r.fromRank then return false end
    if r.sinceMin or r.sinceMax then
        local d = ns.MemberDays(m)
        if not d then return false end
        if r.sinceMin and d < r.sinceMin then return false end
        if r.sinceMax and d > r.sinceMax then return false end
    end
    if r.offDays then
        if m.online or not m.last or m.last < r.offDays * 24 then return false end
    end
    if r.note and r.note ~= "" and not Lower(m.note):find(Lower(r.note), 1, true) then return false end
    if r.onote and r.onote ~= "" and not Lower(m.onote):find(Lower(r.onote), 1, true) then return false end
    return true
end

local function ClassLabel(c)
    if type(c) == "table" then
        local t = {}
        for k in pairs(c) do t[#t + 1] = k:sub(1, 1) .. k:sub(2):lower() end
        table.sort(t)
        return table.concat(t, "/")
    end
    return c:sub(1, 1) .. c:sub(2):lower()
end

-- short text for the conditions of a rule ("level 15-29, Warrior, member 30+ d")
function ns.RuleConditions(r)
    local t = {}
    if r.min or r.max then t[#t + 1] = "level " .. (r.min or 1) .. "-" .. (r.max or "max") end
    if r.class then t[#t + 1] = ClassLabel(r.class) end
    if r.fromRank ~= nil then t[#t + 1] = "now " .. ns.RankName(r.fromRank) end
    if r.sinceMin or r.sinceMax then t[#t + 1] = "member " .. (r.sinceMin or 0) .. "-" .. (r.sinceMax or "any") .. " d" end
    if r.offDays then t[#t + 1] = "offline " .. r.offDays .. "+ d" end
    if r.note and r.note ~= "" then t[#t + 1] = 'note "' .. r.note .. '"' end
    if r.onote and r.onote ~= "" then t[#t + 1] = 'officer note "' .. r.onote .. '"' end
    if #t == 0 then return "everyone" end
    return table.concat(t, ", ")
end

-- which rank do the rules give this member? (m = member table; a plain level number still works)
function ns.RuleTarget(m)
    if not gdb then return nil end
    if type(m) == "number" then m = { level = m, rank = -1, note = "", onote = "" } end
    for _, r in ipairs(gdb.rules) do
        if ns.RuleMatches(r, m) then return r.rank, r end
    end
end

-- the change the rules plan for this member, if I can make it: returns to, why (or nil)
-- (same test as "Queue these changes": not protected, demotions only if allowed, rank below mine)
function ns.PlannedTarget(m)
    if not gdb or not m or gdb.protected[m.rank] then return nil end
    local to, rule = ns.RuleTarget(m)
    if to and to ~= m.rank and ns.ranks[to] and (gdb.allowDemote or to < m.rank) and ns.CanSet(m, to) then
        return to, ns.RuleConditions(rule)
    end
end

-- planned changes from the rules: { { m = member, to = rank, why = "level 30-44" } ... }
function ns.PlanRules()
    local out = {}
    if not gdb then return out end
    for _, m in ipairs(ns.members) do
        local to, why = ns.PlannedTarget(m)
        if to then out[#out + 1] = { m = m, to = to, why = why } end
    end
    table.sort(out, function(a, b) return a.m.short < b.m.short end)
    return out
end

-- ------------------------------------------------------------ queue
local function Changed()
    if ns.OnChanged then ns.OnChanged() end
end

function ns.QueueChange(m, to, why)
    if not m or to == nil then return false end
    for _, j in ipairs(ns.queue) do
        if (m.guid and j.guid == m.guid) or j.name == m.name then j.to = to; j.why = why; return true end
    end
    ns.queue[#ns.queue + 1] = { guid = m.guid, name = m.name, short = m.short, from = m.rank, to = to, why = why or "manual" }
    return true
end

function ns.ClearQueue() wipe(ns.queue); Changed() end

local function Log(text)
    if not gdb then return end
    table.insert(gdb.log, 1, { t = time and time() or 0, text = text })
    while #gdb.log > 300 do table.remove(gdb.log) end
end
ns.Log = Log

-- one rank change; must run from a click or a key press
local function SendRank(m, to)
    if C_GuildInfo and C_GuildInfo.SetGuildRankOrder and m.guid then
        return pcall(C_GuildInfo.SetGuildRankOrder, m.guid, to + 1)
    elseif SetGuildMemberRank then
        return pcall(SetGuildMemberRank, m.index, to + 1)
    end
    -- old clients: one step at a time (the job stays in the queue until it is done)
    local step
    if to < m.rank then step = (C_GuildInfo and C_GuildInfo.Promote) or GuildPromote
    else step = (C_GuildInfo and C_GuildInfo.Demote) or GuildDemote end
    if not step then return false, "no rank function on this client" end
    return pcall(step, m.name), "step"
end

-- apply the next pending change (returns what was done, or nil)
function ns.ApplyNext()
    if InCombatLockdown and InCombatLockdown() then ns.Print("not in combat."); return end
    ns.Scan()
    while #ns.queue > 0 do
        local j = table.remove(ns.queue, 1)
        local m = ns.FindMember(j.guid, j.name)
        if m and m.rank ~= j.to then
            local ok, why = ns.CanSet(m, j.to)
            if ok then
                local sent, res = SendRank(m, j.to)
                if sent then
                    if res == "step" then
                        -- old API: one step done, keep the job until the target is reached
                        table.insert(ns.queue, 1, j)
                    end
                    local text = string.format("%s: %s -> %s (%s)", m.short, ns.RankName(m.rank), ns.RankName(j.to), j.why or "manual")
                    Log(text)
                    ns.lastDone = text
                    m.rank = (res == "step") and (m.rank + ((j.to < m.rank) and -1 or 1)) or j.to
                    m.rankName = ns.RankName(m.rank)
                    ns.RequestRoster()
                    Changed()
                    return text
                else
                    ns.Print("could not change " .. m.short .. ": " .. tostring(res))
                end
            else
                ns.Print("skipped " .. (m.short or j.short) .. " (" .. tostring(why) .. ")")
            end
        end
    end
    Changed()
end

-- key binding (Bindings.xml): a key press counts as a click
-- /fg next and minimap right-click: show the next command (only the secure button may send it)
function FreeGuild_ApplyNext()
    local cmd = ns.NextCommand()
    if cmd then ns.Print("next: " .. cmd .. "  |cff888888(click \"Apply next\" or press its key)|r")
    else ns.Print("nothing left to apply.") end
end
-- ------------------------------------------------------------ secure "apply next" (/gpromote, /gdemote)
-- Forever forbids addons to change ranks; a secure macro button may run the game's own commands.
-- One click = one rank step. We do not wait for the roster: the new rank is remembered locally
-- (optimistic) so the next click goes on with the next step or member. When the real roster arrives
-- we check it, and queue the change again (with a note) if the game did not do it.
local RECON, RECON_HARD, MAX_TRIES = 6, 15, 2
local expect = {}          -- [full name] = { guid, name, short, rank = expected rank, t = time of the click, job = {...} }
ns.expect = expect
local rosterStamp = 0      -- GetTime() of the last GUILD_ROSTER_UPDATE
function ns.RosterStamp(v) if v then rosterStamp = v end return rosterStamp end

-- called by Scan: overlay our expected ranks on the fresh roster, settle the old ones
function ns.Reconcile()
    if not next(expect) then return end
    local now = Clock()
    local byName = {}
    for _, m in ipairs(ns.members) do byName[m.name] = m end
    for name, e in pairs(expect) do
        local m = byName[name]
        if not m then
            expect[name] = nil
        elseif m.rank == e.rank then
            expect[name] = nil                       -- confirmed
        else
            local age = now - e.t
            if age >= RECON and (rosterStamp > e.t or age >= RECON_HARD) then
                expect[name] = nil                   -- the game did not do it
                local job = e.job
                local tries = (job.tries or 0) + 1
                if job.to ~= m.rank and tries < MAX_TRIES and ns.ranks[job.to] then
                    table.insert(ns.queue, 1, { guid = job.guid, name = job.name, short = job.short, from = m.rank, to = job.to, why = job.why, tries = tries })
                    ns.Print(m.short .. " is still " .. ns.RankName(m.rank) .. ": the change did not go through, queued again.")
                else
                    ns.Print(m.short .. " is still " .. ns.RankName(m.rank) .. ": the change did not go through. Check your rank permissions.")
                end
                Log("not confirmed: " .. m.short .. " is " .. ns.RankName(m.rank))
            else
                m.rank = e.rank                      -- optimistic
                m.rankName = ns.RankName(e.rank)
                m.pending = true
            end
        end
    end
end

local function ScheduleReconcile()
    if not (C_Timer and C_Timer.After) then return end
    local function check()
        if next(expect) then ns.RequestRoster(); ns.Scan(); Changed() end
    end
    C_Timer.After(RECON + 0.5, check)
    C_Timer.After(RECON_HARD + 0.5, check)
end

function ns.NextCommand()
    ns.Scan()
    while #ns.queue > 0 do
        local j = ns.queue[1]
        local m = ns.FindMember(j.guid, j.name)
        if not m or m.rank == j.to then
            table.remove(ns.queue, 1)
        else
            local ok, why = ns.CanSet(m, j.to)
            if ok then
                return ((j.to < m.rank) and "/gpromote " or "/gdemote ") .. m.short, m, j
            end
            ns.Print("skipped " .. (m.short or j.short) .. " (" .. tostring(why) .. ")")
            table.remove(ns.queue, 1)
        end
    end
end

local function PreClick(self, _, down)
    self:SetAttribute("macrotext", "")
    if InCombatLockdown() then ns.Print("not in combat."); return end
    -- once per press: on key down if the game uses key-down, otherwise on release
    local useDown = GetCVarBool and GetCVarBool("ActionButtonUseKeyDown") or false
    if (down and true or false) ~= useDown then return end
    ns.Scan()
    local cmd, m, j = ns.NextCommand()
    if not cmd then ns.Print("nothing left to apply."); Changed(); return end
    local step = (j.to < m.rank) and (m.rank - 1) or (m.rank + 1)   -- one step toward the target, never past it
    self:SetAttribute("macrotext", cmd)
    local text = string.format("%s: %s -> %s (%s)", m.short, ns.RankName(m.rank), ns.RankName(step), j.why or "manual")
    Log("sent " .. text)
    ns.lastDone = text
    -- optimistic: remember the new rank now, so the next click goes on without waiting for the roster
    expect[m.name] = { guid = m.guid, name = m.name, short = m.short, rank = step, t = Clock(),
                       job = { guid = j.guid, name = j.name, short = j.short, to = j.to, why = j.why, tries = j.tries } }
    m.rank = step; m.rankName = ns.RankName(step); m.pending = true
    if step == j.to then table.remove(ns.queue, 1) end
    ns.RequestRoster()
    ScheduleReconcile()
end

function ns.MakeApplyButton(name, parent)
    local b = CreateFrame("Button", name, parent, "SecureActionButtonTemplate")
    b:SetAttribute("type", "macro")
    b:SetAttribute("macrotext", "")
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetScript("PreClick", PreClick)
    b:HookScript("PostClick", function() Changed() end)
    return b
end

-- a secure button that runs a slash command built at click time (getMacro() -> text or nil)
function ns.MakeMacroButton(name, parent, getMacro)
    local b = CreateFrame("Button", name, parent, "SecureActionButtonTemplate")
    b:SetAttribute("type", "macro")
    b:SetAttribute("macrotext", "")
    b:RegisterForClicks("AnyUp")
    b:SetScript("PreClick", function(self)
        self:SetAttribute("macrotext", "")
        if InCombatLockdown() then ns.Print("not in combat."); return end
        local ok, text = pcall(getMacro)
        if ok and text and text ~= "" then self:SetAttribute("macrotext", text) end
    end)
    return b
end

-- key binding target (Bindings.xml: CLICK FreeGuildApplyButton:LeftButton)
local keyButton = ns.MakeApplyButton("FreeGuildApplyButton", UIParent)
keyButton:SetSize(1, 1)
keyButton:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10, 10)
_G["BINDING_NAME_CLICK FreeGuildApplyButton:LeftButton"] = "Apply the next rank change"

BINDING_HEADER_FREEGUILD = "Free Guild"
BINDING_NAME_FREEGUILD_APPLYNEXT = "Apply the next rank change"
BINDING_NAME_FREEGUILD_TOGGLE = "Open / close Free Guild"

-- ------------------------------------------------------------ guild info: MOTD, info text, notes, bank
-- Everything here may be missing or protected on this client: each call is in a pcall and says why it failed.
ns.refused = {}        -- [what] = true once the game refused it from an addon

-- run a maybe-protected function; returns ok, reason ("missing" / "refused" / error text)
function ns.TryProtected(what, fn, ...)
    if type(fn) ~= "function" then return false, "missing" end
    ns.trying, ns.tryRefused = what, false
    local ok, err = pcall(fn, ...)
    ns.trying = nil
    if ns.tryRefused or (not ok and tostring(err):find("FORBIDDEN", 1, true)) then
        ns.refused[what] = true
        return false, "refused"
    end
    if not ok then return false, tostring(err) end
    return true
end

local function Call(path, name, ...)       -- C_GuildInfo.<name> or global <name>, whichever exists
    local fn = (path and C_GuildInfo and C_GuildInfo[name]) or _G[name]
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, ...)
    if ok then return a, b end
end

function ns.GetMOTD() return Call(true, "GetMOTD") or Call(false, "GetGuildRosterMOTD") or "" end
function ns.GetInfoText() return Call(false, "GetGuildInfoText") or "" end
function ns.CanEditMOTD() local v = Call(false, "CanEditMOTD"); return v == nil or v end
function ns.CanEditInfo() local v = Call(false, "CanEditGuildInfo"); return v == nil or v end
function ns.CanEditNote(officer)
    local v = Call(false, officer and "CanEditOfficerNote" or "CanEditPublicNote")
    return v == nil or v
end
function ns.RequestGuildInfo()
    if C_GuildInfo and C_GuildInfo.GuildInfo then pcall(C_GuildInfo.GuildInfo)
    elseif GuildInfo then pcall(GuildInfo) end
end

local function Explain(what, ok, why)
    if ok then return true end
    if why == "missing" then ns.Print("this client has no function to change " .. what .. ".")
    elseif why == "refused" then ns.Print("the game refuses addons to change " .. what .. ".")
    else ns.Print("could not change " .. what .. ": " .. tostring(why)) end
    return false
end

function ns.SetMOTD(text)
    local fn = (C_GuildInfo and C_GuildInfo.SetMOTD) or GuildSetMOTD
    local ok, why = ns.TryProtected("motd", fn, text)
    if ok then ns.Print("message of the day sent."); ns.Log("MOTD: " .. text); ns.RequestRoster() return true end
    if why == "refused" or why == "missing" then
        ns.Print("the game refuses addons to set the message of the day. Use the \"Set with /gmotd\" button instead.")
        ns.refused.motd = true
    else Explain("the message of the day", false, why) end
    return false
end

-- The game keeps the guild information to its own window on Forever (no slash command either): once refused,
-- Free Guild hands the text over in a copy box, to paste in the game's guild information editor.
function ns.CopyInfoForGame(text)
    local LFP = LibStub and LibStub("LibFreeProfiles-1.0", true)
    if LFP and LFP.ShowExport then
        LFP:ShowExport("Guild information: Ctrl+C, then paste in the game's window", text or "")
    end
    ns.Print("the game keeps the guild information to its own window: the text is selected, press Ctrl+C, then open the guild window > Guild Information > edit, Ctrl+V and accept.")
end

function ns.SetInfoText(text)
    if ns.refused and ns.refused.info then ns.CopyInfoForGame(text); return false end
    local fn = (C_GuildInfo and C_GuildInfo.SetGuildInfoText) or SetGuildInfoText
    local ok, why = ns.TryProtected("info", fn, text)
    if ok then ns.Print("guild information saved."); ns.Log("guild info edited"); ns.RequestGuildInfo(); return true end
    if why == "refused" then ns.CopyInfoForGame(text); return false end
    return Explain("the guild information", false, why)
end

function ns.SetNote(m, text, officer)
    if not m then return false end
    ns.Scan()
    local cur = ns.FindMember(m.guid, m.name)         -- roster indexes change: use a fresh one
    if not cur then ns.Print("member not found in the roster."); return false end
    local fn = officer and GuildRosterSetOfficerNote or GuildRosterSetPublicNote
    local ok, why = ns.TryProtected(officer and "onote" or "note", fn, cur.index, text)
    if not Explain((officer and "officer" or "public") .. " note of " .. cur.short, ok, why) then return false end
    if officer then cur.onote = text else cur.note = text end
    ns.Print((officer and "officer" or "public") .. " note of " .. cur.short .. " saved.")
    ns.RequestRoster()
    return true
end

-- gold with thousands separators: 12 345g 67s 89c
function ns.FormatMoney(copper)
    copper = math.floor(tonumber(copper) or 0)
    local g, sv, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local gs = tostring(g)
    while true do
        local n, k = gs:gsub("^(-?%d+)(%d%d%d)", "%1 %2")
        gs = n
        if k == 0 then break end
    end
    return string.format("%sg %ds %dc", gs, sv, c)
end

-- remember the guild bank money (only readable while the bank is open)
function ns.RecordBank(force)
    if not gdb or type(GetGuildBankMoney) ~= "function" then return end
    local ok, money = pcall(GetGuildBankMoney)
    if not ok or type(money) ~= "number" then return end
    local okc, positive = pcall(function() return money > 0 end)
    if not okc then return end
    if positive or force then
        gdb.bank = gdb.bank or {}
        gdb.bank.money, gdb.bank.t = money, time and time() or 0
        Changed()
    end
end
function ns.BankText()
    local b = gdb and gdb.bank
    if not (b and b.money) then return "Not known yet. Open the guild bank once." end
    return "Last known: " .. ns.FormatMoney(b.money) .. (date and (" (" .. date("%d/%m %H:%M", b.t or 0) .. ")") or "")
end

-- ------------------------------------------------------------ export / import of the rules
local LFP = LibStub and LibStub("LibFreeProfiles-1.0", true)
function ns.ExportRules()
    if not (LFP and gdb) then return end
    LFP:ShowExport("Export Free Guild rules", LFP.Encode("FreeGuild", { v = 2, rules = gdb.rules, protected = gdb.protected, allowDemote = gdb.allowDemote }))
end

-- keep only known fields with the right types (old exports have just on/min/max/rank)
local function Int(v, lo) v = tonumber(v); if v then v = math.floor(v); if lo and v < lo then v = lo end return v end end
function ns.SanitizeRule(r)
    if type(r) ~= "table" then return nil end
    local out = { on = r.on ~= false, min = Int(r.min, 1), max = Int(r.max, 1), rank = Int(r.rank, 0),
                  fromRank = Int(r.fromRank, 0), sinceMin = Int(r.sinceMin, 0), sinceMax = Int(r.sinceMax, 0), offDays = Int(r.offDays, 0) }
    if type(r.class) == "string" and r.class ~= "" then out.class = r.class:upper()
    elseif type(r.class) == "table" then
        local t = {}
        for k, v in pairs(r.class) do if type(k) == "string" and v then t[k:upper()] = true end end
        if next(t) then out.class = t end
    end
    if type(r.note) == "string" and r.note ~= "" then out.note = r.note:sub(1, 60) end
    if type(r.onote) == "string" and r.onote ~= "" then out.onote = r.onote:sub(1, 60) end
    return out
end

function ns.ImportRules()
    if not (LFP and gdb) then return end
    LFP:ShowImport("Import Free Guild rules", "", function(text)
        local ok, data = LFP.Decode("FreeGuild", text)
        if not ok then return false, data end
        if type(data.rules) ~= "table" then return false, "The text holds no rules." end
        local rules = {}
        for _, r in ipairs(data.rules) do
            local c = ns.SanitizeRule(r)
            if c and #rules < 8 then rules[#rules + 1] = c end
        end
        gdb.rules = rules
        gdb.protected = type(data.protected) == "table" and data.protected or {}
        gdb.allowDemote = data.allowDemote and true or false
        Changed()
        return true, "rules"
    end)
end

-- ------------------------------------------------------------ events
local reminded = false
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("GUILD_ROSTER_UPDATE")
f:RegisterEvent("PLAYER_GUILD_UPDATE")
f:RegisterEvent("GUILD_RANKS_UPDATE")
f:RegisterEvent("ADDON_ACTION_FORBIDDEN")
f:RegisterEvent("ADDON_ACTION_BLOCKED")
-- these may not exist on every client: a bad name must not break the addon
for _, ev in ipairs({ "GUILD_MOTD", "GUILDBANKFRAME_OPENED", "GUILDBANK_UPDATE_MONEY", "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" }) do
    pcall(f.RegisterEvent, f, ev)
end
f:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        FreeGuildDB = type(FreeGuildDB) == "table" and FreeGuildDB or {}
        db = FreeGuildDB
        db.guilds = db.guilds or {}
        db.minimap = db.minimap or { hide = false }
        return
    end
    if event == "ADDON_ACTION_FORBIDDEN" or event == "ADDON_ACTION_BLOCKED" then
        if arg1 == ADDON then
            if ns.trying then ns.tryRefused = true            -- reported by whoever called TryProtected
            else ns.Print("the game refused the change. Use the \"Apply next\" button or its key, one change per press.") end
        end
        return
    end
    if event == "GUILD_MOTD" then Changed(); return end
    if event == "GUILDBANKFRAME_OPENED" or event == "GUILDBANK_UPDATE_MONEY" or event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
        if event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
            local pit = Enum and Enum.PlayerInteractionType
            if pit and pit.GuildBanker and arg1 ~= pit.GuildBanker then return end
        end
        ns.RecordBank(event == "GUILDBANK_UPDATE_MONEY")
        if C_Timer and C_Timer.After then C_Timer.After(1, function() ns.RecordBank() end) end   -- data may arrive after the window opens
        return
    end
    if event == "PLAYER_LOGIN" then
        if SetGuildRosterShowOffline then pcall(SetGuildRosterShowOffline, true) end
        ns.RequestRoster()
    end
    if event == "GUILD_ROSTER_UPDATE" then rosterStamp = Clock() end
    UseGuild()
    if IsInGuild() then ns.Scan() end
    Changed()
    -- reminder, once per session, when rules would change someone
    if gdb and gdb.remind and not reminded and #gdb.rules > 0 and #ns.members > 0 then
        local plan = ns.PlanRules()
        if #plan > 0 then
            reminded = true
            ns.Print(#plan .. " member(s) should get a new rank by your rules. Type /fg to review.")
        end
    end
end)

-- ------------------------------------------------------------ slash
SLASH_FREEGUILD1 = "/fg"
SLASH_FREEGUILD2 = "/freeguild"
SlashCmdList.FREEGUILD = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "next" then FreeGuild_ApplyNext()
    elseif msg == "help" or msg == "?" then
        ns.Print("/fg = window, /fg next = apply the next queued rank change (bind a key to it in the game's Key Bindings, AddOns section).")
    elseif ns.ToggleConfig then ns.ToggleConfig() end
end
