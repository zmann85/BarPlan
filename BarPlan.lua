-- BarPlan: your action bars as a plan.
-- Save a character's bars as a named plan of its class (the window: /barplan). A new character of that class
-- picks one of its class's plans (asked at the first login, or in the window), and every spell it learns later
-- goes straight onto its planned button; a new rank replaces the old one on the same button. Macros from the
-- plan are made as the plan had them (character or general) when they're missing. A plan also keeps which addons
-- were on and the chat tabs (each tab's name, message types, channels, font size, colour, place in the dock):
-- applying it switches this character's addons and chat tabs to match (addons at a reload). A plan saved on a
-- character with its own (character-specific) keybindings keeps those too. Plans are
-- per class and account-wide; a character remembers which plan it follows.
local ADDON = ...
local BP = {}
_G.BarPlan = BP

local MAX_SLOT = 180 -- (checked with HasAction: slots this client doesn't have are simply empty)
local MC = Constants and Constants.MacroConsts
local MAX_ACCOUNT = (MC and MC.MAX_ACCOUNT_MACROS) or MAX_ACCOUNT_MACROS or 120
local MAX_CHAR = (MC and MC.MAX_CHARACTER_MACROS) or MAX_CHARACTER_MACROS or 30
local BOOK = BOOKTYPE_SPELL or "spell"

local DB, C -- BarPlanDB (account), BarPlanCharDB (this character)

local function say(msg)
    (DEFAULT_CHAT_FRAME or ChatFrame1):AddMessage("|cff66bbffBarPlan|r " .. msg)
end

---------------------------------------------------------------- spells

local function rankNum(sub)
    return tonumber(type(sub) == "string" and sub:match("(%d+)") or "") or 0
end

-- a spell's name and rank number from its ID
local function spellInfo(id)
    local name, sub
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, id)
        if ok and type(info) == "table" then name = info.name end
        if C_Spell.GetSpellSubtext then sub = C_Spell.GetSpellSubtext(id) end
    end
    if not name and GetSpellInfo then
        local n, r = GetSpellInfo(id)
        name, sub = n, sub or r
    end
    if not sub and GetSpellSubtext then sub = GetSpellSubtext(id) end
    return name, rankNum(sub)
end

-- every spell you know: name -> { id = highest rank's ID, rank = its number, ranks = { [n] = ID } }
local function scanBook()
    local book = {}
    local function add(name, sub, id)
        if not (name and id) then return end
        if IsPlayerSpell and not IsPlayerSpell(id) then return end
        local r = rankNum(sub)
        local b = book[name]
        if not b then b = { ranks = {} }; book[name] = b end
        b.ranks[r] = id
        if not b.rank or r > b.rank then b.rank, b.id = r, id end
    end
    local SB = C_SpellBook
    if SB and SB.GetSpellBookItemInfo then
        local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
        local future = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.FutureSpell
        for i = 1, 1000 do
            local ok, info = pcall(SB.GetSpellBookItemInfo, i, bank)
            if not ok or type(info) ~= "table" or not info.name then break end
            if info.itemType ~= future then add(info.name, info.subName, info.spellID or info.actionID) end
        end
    elseif GetSpellBookItemName then
        for i = 1, 1000 do
            local name, sub = GetSpellBookItemName(i, BOOK)
            if not name then break end
            local kind, id = GetSpellBookItemInfo(i, BOOK)
            if kind == "SPELL" then add(name, sub, id) end
        end
    end
    return book
end

-- the rank to put on a planned spell's button: the highest you know, or up to the one the plan keeps
local function wantedID(e, book)
    local b = book[e.name]
    if not b then return nil end
    if not e.pin then return b.id, b.rank end
    local best, br
    for r, id in pairs(b.ranks) do
        if r <= e.pin and (not br or r > br) then best, br = id, r end
    end
    return best, br
end

---------------------------------------------------------------- slots

local function hasAction(slot)
    local ok, has = pcall(HasAction, slot)
    return ok and has
end

-- what a button holds: { k = "spell", name, id, rank } / { k = "macro", name, icon, body, char } /
-- { k = "item", id, name } / { k = "other", kind, id }, or nil when it's empty
local function readSlot(slot)
    if not hasAction(slot) then return nil end
    local kind, id = GetActionInfo(slot)
    if kind == "spell" and id then
        local name, rank = spellInfo(id)
        if name then return { k = "spell", name = name, id = id, rank = rank } end
    elseif kind == "macro" then
        -- (the button's text is the macro's name; the ID is its place in the macro list)
        local mname = GetActionText and GetActionText(slot)
        local idx = (mname and GetMacroIndexByName(mname)) or 0
        if idx == 0 and id then idx = id end
        local name, icon, body = GetMacroInfo(idx)
        if name then return { k = "macro", name = name, icon = icon, body = body, char = idx > MAX_ACCOUNT } end
    elseif kind == "item" and id then
        return { k = "item", id = id, name = GetItemInfo and GetItemInfo(id) or nil }
    end
    return { k = "other", kind = kind, id = id }
end

-- a macro that only casts one spell (#showtooltip X / /cast X, a rank allowed): the plan keeps the spell, so a
-- new character gets the spell itself on that button when it learns it (no macro needed, nothing to place
-- before). Anything more (conditions, a second line) stays a macro.
local function plainSpell(body)
    if type(body) ~= "string" then return nil end
    local cast
    for line in body:gmatch("[^\r\n]+") do
        line = line:gsub("^%s+", ""):gsub("%s+$", "")
        if line == "" then
        elseif line:match("^#showtooltip") then
            local t = line:match("^#showtooltip%s+(.+)$")
            if t and t:find("[%[;]") then return nil end
        else
            local name = line:match("^/cast%s+(.+)$")
            if not name or cast or name:find("[%[;@]") then return nil end
            cast = name:gsub("%s*%(%s*[Rr]ank%s*%d+%s*%)%s*$", ""):gsub("%s+$", "")
        end
    end
    if cast and cast ~= "" and not cast:match("^%d+$") then return cast end
end

local function describe(e)
    if not e then return "nothing" end
    if e.k == "spell" then return e.name .. ((e.rank or 0) > 0 and (" (Rank " .. e.rank .. ")") or "") end
    if e.k == "macro" then return "macro " .. e.name end
    if e.k == "item" then return e.name or ("item " .. tostring(e.id)) end
    return tostring(e.kind)
end

-- the button already holds what the plan wants there (a spell: at the rank it should have)
local function holds(cur, e, book)
    if not (cur and e) or cur.k ~= e.k then return false end
    if e.k == "spell" then
        if cur.name ~= e.name then return false end
        local _, r = wantedID(e, book)
        return not r or cur.rank == r
    elseif e.k == "macro" then return cur.name == e.name
    elseif e.k == "item" then return cur.id == e.id end
    return false
end

local function cursorFull()
    return GetCursorInfo and GetCursorInfo() ~= nil
end

local function clearSlot(slot)
    ClearCursor()
    PickupAction(slot)
    ClearCursor()
end

-- a macro of the plan: yours by that name, or made from the plan when you don't have one
local function macroIndex(e, made)
    local idx = GetMacroIndexByName(e.name) or 0
    if idx > 0 then return idx end
    local nAcc, nChar = GetNumMacros()
    local char = e.char
    if char and nChar >= MAX_CHAR then return nil, "your 30 character macros are taken" end
    if not char and nAcc >= MAX_ACCOUNT then return nil, "the general macros are full" end
    local ok, newIdx = pcall(CreateMacro, e.name, e.icon or 134400, e.body or "", char and true or nil)
    if not ok or not newIdx or newIdx == 0 then return nil, "the game didn't make it" end
    if made then made[#made + 1] = e.name end
    return newIdx
end

-- put a plan entry on a button; false (and why) when it can't be there yet
local function place(slot, e, book, made)
    ClearCursor()
    if e.k == "spell" then
        local id = wantedID(e, book)
        if not id then return false end
        local pick = (C_Spell and C_Spell.PickupSpell) or PickupSpell
        pick(id)
    elseif e.k == "macro" then
        local idx, why = macroIndex(e, made)
        if not idx then return false, why end
        PickupMacro(idx)
    elseif e.k == "item" then
        local pick = (C_Item and C_Item.PickupItem) or PickupItem
        pick(e.id)
    else
        return false
    end
    if not cursorFull() then ClearCursor() return false end
    PlaceAction(slot)
    ClearCursor() -- (what was on the button before)
    return true
end


---------------------------------------------------------------- addons (which are on, per character)
-- C_AddOns where the client has it, the old globals otherwise. The old GetAddOnEnableState takes
-- (character, addon), the new one (addon, character).

local AO = C_AddOns or {}
local numAddOns = AO.GetNumAddOns or GetNumAddOns
local addOnInfo = AO.GetAddOnInfo or GetAddOnInfo
local enableAddOn = AO.EnableAddOn or EnableAddOn
local disableAddOn = AO.DisableAddOn or DisableAddOn
local saveAddOns = AO.SaveAddOns or SaveAddOns

-- the character, as the addon functions want it: C_AddOns by the character's GUID (by name it answers for
-- every character of that name - checked on WoW Forever), the old globals by name
local function me() return (AO.GetAddOnEnableState and UnitGUID("player")) or (UnitName("player")) end

-- on for this character? The addon's "DISABLED" reason is about the character you're on (as of the last
-- reload); otherwise its enable state for this character.
local function addOnOn(name, reason)
    if reason == "DISABLED" then return false end
    local state
    if AO.GetAddOnEnableState then state = AO.GetAddOnEnableState(name, me())
    elseif GetAddOnEnableState then state = GetAddOnEnableState(me(), name) end
    if type(state) == "boolean" then return state end
    return (tonumber(state) or 0) > 0
end

-- every installed addon: name -> on for this character
local function readAddOns()
    local t, n = {}, 0
    if not (numAddOns and addOnInfo) then return t, n end
    for i = 1, numAddOns() do
        local name, _, _, _, reason = addOnInfo(i)
        if name then t[name] = addOnOn(name, reason); n = n + 1 end
    end
    return t, n
end

-- switch this character's addons to a plan's list: { on = n, off = n, missing = { names } }, or nil when the
-- plan has none. Addons the plan doesn't know (installed after it was saved) stay as they are; BarPlan stays on.
local function applyAddOns(list)
    if type(list) ~= "table" or not (enableAddOn and disableAddOn) then return nil end
    local installed = readAddOns()
    local r = { on = 0, off = 0, missing = {} }
    for name, want in pairs(list) do
        if name ~= ADDON then
            local have = installed[name]
            if have == nil then
                if want then r.missing[#r.missing + 1] = name end
            elseif have ~= want then
                if want then enableAddOn(name, me()); r.on = r.on + 1
                else disableAddOn(name, me()); r.off = r.off + 1 end
            end
        end
    end
    if (r.on + r.off) > 0 and saveAddOns then saveAddOns() end
    table.sort(r.missing)
    return r
end

local function addOnCount(list)
    local on, all = 0, 0
    for _, v in pairs(list or {}) do all = all + 1; if v then on = on + 1 end end
    return on, all
end

---------------------------------------------------------------- chat tabs
-- The game's chat windows: 1 General and 2 Combat Log always exist; 3 on are the tabs you add (Voice is 3 by
-- default). A plan keeps every window that has a name and is shown or docked; applying it sets windows 1 and 2
-- up as kept, finds the others by name (opening a new tab when there's none) and closes added tabs the plan
-- doesn't have. Window positions stay as they are (your UI places the chat).

local MAX_CHAT = NUM_CHAT_WINDOWS or 10

local function chatWindow(i)
    local name, size, r, g, b, a, shown, locked, docked, uninteractable = GetChatWindowInfo(i)
    if not name or name == "" then return nil end
    if i > 2 and not shown and not (docked and docked ~= 0) then return nil end
    local w = { name = name, size = size, color = { r, g, b, a }, shown = shown and true or false,
                locked = locked and true or false, docked = tonumber(docked) or 0,
                uninteractable = uninteractable and true or false, messages = {}, channels = {} }
    for _, m in ipairs({ GetChatWindowMessages(i) }) do w.messages[#w.messages + 1] = m end
    local ch = { GetChatWindowChannels(i) }
    for k = 1, #ch, 2 do if ch[k] then w.channels[#w.channels + 1] = ch[k] end end
    return w
end

local function readChat()
    if not GetChatWindowInfo then return nil end
    local t = {}
    for i = 1, MAX_CHAT do
        local ok, w = pcall(chatWindow, i)
        if ok and w then w.index = i; t[#t + 1] = w end
    end
    return t
end

local function frameByName(name)
    for i = 3, MAX_CHAT do
        local n, _, _, _, _, _, shown, _, docked = GetChatWindowInfo(i)
        if n == name and (shown or (docked and docked ~= 0)) then return _G["ChatFrame" .. i], i end
    end
end

-- one window as the plan has it
local function setupWindow(frame, w)
    if w.name and FCF_SetWindowName then FCF_SetWindowName(frame, w.name) end
    if w.size and FCF_SetChatWindowFontSize then FCF_SetChatWindowFontSize(nil, frame, w.size) end
    local c = w.color
    if c and c[1] then
        if FCF_SetWindowColor then FCF_SetWindowColor(frame, c[1], c[2], c[3]) end
        if FCF_SetWindowAlpha and c[4] then FCF_SetWindowAlpha(frame, c[4]) end
    end
    if ChatFrame_RemoveAllMessageGroups then
        ChatFrame_RemoveAllMessageGroups(frame)
        for _, m in ipairs(w.messages or {}) do ChatFrame_AddMessageGroup(frame, m) end
    end
    if ChatFrame_RemoveAllChannels then
        ChatFrame_RemoveAllChannels(frame)
        for _, ch in ipairs(w.channels or {}) do ChatFrame_AddChannel(frame, ch) end
    end
    if FCF_SetLocked then FCF_SetLocked(frame, w.locked and 1 or nil) end
    if FCF_SetUninteractable then FCF_SetUninteractable(frame, w.uninteractable and true or false) end
end

-- set this character's chat tabs up from a plan's: { set = n, made = n, closed = n }, or nil when it has none
local function applyChat(list)
    if type(list) ~= "table" or not GetChatWindowInfo then return nil end
    local r = { set = 0, made = 0, closed = 0 }
    local want, frames = {}, {}
    for _, w in ipairs(list) do
        local frame
        if w.index == 1 or w.index == 2 then
            frame = _G["ChatFrame" .. w.index]
        else
            want[w.name] = true
            frame = frameByName(w.name)
            if not frame and FCF_OpenNewWindow then
                local ok, f = pcall(FCF_OpenNewWindow, w.name)
                if ok then frame = f or frameByName(w.name); if frame then r.made = r.made + 1 end end
            end
        end
        if frame then
            if pcall(setupWindow, frame, w) then r.set = r.set + 1 end
            frames[#frames + 1] = { frame = frame, w = w }
        end
    end
    -- added tabs the plan doesn't have (shown or in the dock, under a name the plan doesn't know)
    local mine = {}
    for _, x in ipairs(frames) do mine[x.frame] = true end
    for i = 3, MAX_CHAT do
        local n, _, _, _, _, _, shown, _, docked = GetChatWindowInfo(i)
        local frame = _G["ChatFrame" .. i]
        if frame and not mine[frame] and n and n ~= "" and not want[n] and (shown or (docked and docked ~= 0)) then
            if FCF_Close and pcall(FCF_Close, frame) then r.closed = r.closed + 1 end
        end
    end
    -- the dock in the plan's order
    table.sort(frames, function(a, b) return (a.w.docked or 0) < (b.w.docked or 0) end)
    for _, x in ipairs(frames) do
        if (x.w.docked or 0) > 0 and FCF_DockFrame and x.frame ~= DEFAULT_CHAT_FRAME then
            pcall(FCF_DockFrame, x.frame, x.w.docked, false)
        end
    end
    if FCF_SelectDockFrame and DEFAULT_CHAT_FRAME then pcall(FCF_SelectDockFrame, DEFAULT_CHAT_FRAME) end
    return r
end

local function chatNames(list)
    local t = {}
    for _, w in ipairs(list or {}) do t[#t + 1] = w.name end
    return table.concat(t, ", ")
end

---------------------------------------------------------------- keybindings
-- Only a character with its own keybindings (the "character specific" box) has some to keep: the plan holds
-- every key and what it does, and applying it gives the new character those as its own set. A plan saved on
-- a character using the account-wide keys gives the new character the account-wide keys. Keys are read by
-- asking each key what it does (that covers macro, spell and button clicks too, which the game's command list
-- doesn't): every key of a keyboard and mouse with every modifier, and every key the command list knows.

local ACCOUNT_SET, CHAR_SET = ACCOUNT_BINDINGS or 1, CHARACTER_BINDINGS or 2

local function keyUniverse()
    local base = {}
    for c in ("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"):gmatch(".") do base[#base + 1] = c end
    for i = 1, 12 do base[#base + 1] = "F" .. i end
    for i = 0, 9 do base[#base + 1] = "NUMPAD" .. i end
    for _, k in ipairs({ "NUMPADDIVIDE", "NUMPADMULTIPLY", "NUMPADMINUS", "NUMPADPLUS", "NUMPADDECIMAL",
        "SPACE", "TAB", "ENTER", "BACKSPACE", "INSERT", "DELETE", "HOME", "END", "PAGEUP", "PAGEDOWN",
        "UP", "DOWN", "LEFT", "RIGHT", "NUMLOCK", "CAPSLOCK", "PRINTSCREEN", "PAUSE", "ESCAPE",
        "BUTTON1", "BUTTON2", "BUTTON3", "BUTTON4", "BUTTON5", "MOUSEWHEELUP", "MOUSEWHEELDOWN",
        "`", "-", "=", "[", "]", "\\", ";", "'", ",", ".", "/",
        "ß", "´", "^", "ü", "ö", "ä", "+", "#", "<" }) do base[#base + 1] = k end
    local mods = { "", "SHIFT-", "CTRL-", "ALT-", "CTRL-SHIFT-", "ALT-SHIFT-", "ALT-CTRL-", "ALT-CTRL-SHIFT-" }
    local seen, keys = {}, {}
    local function add(k) if k and k ~= "" and not seen[k] then seen[k] = true; keys[#keys + 1] = k end end
    for _, m in ipairs(mods) do for _, b in ipairs(base) do add(m .. b) end end
    if GetNumBindings and GetBinding then
        for i = 1, GetNumBindings() do
            local t = { GetBinding(i) }
            for k = 3, #t do add(t[k]) end
        end
    end
    return keys
end

local function charBindings()
    return GetCurrentBindingSet and GetCurrentBindingSet() == CHAR_SET
end

-- { set = CHAR_SET, keys = { [key] = action } } for a character with its own, { set = ACCOUNT_SET } otherwise
local function readBindings()
    if not GetBindingAction then return nil end
    if not charBindings() then return { set = ACCOUNT_SET } end
    local keys = {}
    for _, k in ipairs(keyUniverse()) do
        local a = GetBindingAction(k)
        if a and a ~= "" then keys[k] = a end
    end
    return { set = CHAR_SET, keys = keys }
end

-- this character's own keybindings on or off (the game's "character specific" box): on copies the keys you have
-- now into its own set, off goes back to the account-wide keys
function BP.setCharBindings(on)
    if InCombatLockdown() then say("keybindings can't change in combat") return end
    if not SaveBindings then return end
    if on then
        if not charBindings() then SaveBindings(CHAR_SET) end
    elseif charBindings() then
        if LoadBindings then LoadBindings(ACCOUNT_SET) end
        SaveBindings(ACCOUNT_SET)
    end
    if BP.refreshUI then BP.refreshUI() end
end

-- give this character the plan's keybindings: { set = n, changed = n }, or nil when the plan has none
local function applyBindings(b)
    if type(b) ~= "table" or not (SetBinding and SaveBindings) then return nil end
    local r = { set = b.set, changed = 0 }
    if b.set == CHAR_SET and type(b.keys) == "table" then
        local keys = keyUniverse()
        local seen = {}
        for _, k in ipairs(keys) do seen[k] = true end
        for k in pairs(b.keys) do if not seen[k] then keys[#keys + 1] = k end end
        for _, k in ipairs(keys) do
            local want = b.keys[k]
            local cur = GetBindingAction(k)
            if cur == "" then cur = nil end
            if want ~= cur then
                if want then SetBinding(k, want) else SetBinding(k) end
                r.changed = r.changed + 1
            end
        end
        SaveBindings(CHAR_SET) -- (this character's own set from now on)
    elseif b.set == ACCOUNT_SET and charBindings() then
        -- back to the account-wide keys (loaded first, so the account set isn't overwritten with this one's)
        if LoadBindings then LoadBindings(ACCOUNT_SET) end
        SaveBindings(ACCOUNT_SET)
        r.changed = 1
    end
    return r
end

---------------------------------------------------------------- plans (per class)
-- BarPlanDB.classes[CLASS] = { plans = { [name] = plan }, default = name }
-- plan = { slots = { [slot] = entry }, addons = { [addon] = on }, chat = { window, ... },
--         bindings = { set = 1|2, keys = { [key] = action } }, from = "Name-Realm",
--         level = n, made = "date" }

local function classTag()
    local _, class = UnitClass("player")
    return class
end
local function className()
    return (UnitClass("player"))
end
local function bucket(class)
    class = class or classTag()
    local b = DB.classes[class]
    if not b then b = { plans = {} }; DB.classes[class] = b end
    return b
end
local function count(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

-- your class's plans, by name
function BP.planNames()
    local t = {}
    for name in pairs(bucket().plans) do t[#t + 1] = name end
    table.sort(t, function(a, b) return a:lower() < b:lower() end)
    return t
end
function BP.plan(name) return name and bucket().plans[name] end
function BP.defaultName() local b = bucket(); return b.plans[b.default or ""] and b.default or nil end

-- the plan this character follows, else the one new characters of the class get
function BP.planFor()
    local b = bucket()
    if C.plan and b.plans[C.plan] then return b.plans[C.plan], C.plan end
    local d = BP.defaultName()
    if d then return b.plans[d], d end
end

function BP.setDefault(name)
    local b = bucket()
    if b.plans[name] then b.default = name end
end

function BP.delete(name)
    local b = bucket()
    if not b.plans[name] then return false end
    b.plans[name] = nil
    if b.default == name then b.default = nil end
    if C.plan == name then C.plan = nil end
    return true
end

-- save this character's bars as plan <name> of its class
function BP.record(name)
    name = name and name:gsub("^%s+", ""):gsub("%s+$", "") or ""
    if name == "" then name = className() end
    local book = scanBook()
    local slots, n, pinned, skipped, spellMacros = {}, 0, 0, 0, 0
    for slot = 1, MAX_SLOT do
        local cur = readSlot(slot)
        if cur and cur.k == "macro" then
            local sp = plainSpell(cur.body)
            if sp then cur = { k = "spell", name = sp, rank = 0, fromMacro = cur.name } end
        end
        if cur and cur.k ~= "other" then
            if cur.k == "spell" and not cur.fromMacro then
                -- a lower rank than you know on purpose (a cheap rank): kept at that rank
                local b = book[cur.name]
                if b and cur.rank > 0 and cur.rank < b.rank then cur.pin = cur.rank; pinned = pinned + 1 end
                cur.id = nil
            elseif cur.k == "spell" then
                cur.fromMacro = nil
                spellMacros = spellMacros + 1
            end
            slots[slot] = cur
            n = n + 1
        elseif cur then
            skipped = skipped + 1
        end
    end
    local b = bucket()
    local was = b.plans[name]
    local addons = readAddOns()
    local chat = readChat()
    local binds = readBindings()
    b.plans[name] = { slots = slots, addons = addons, chat = chat, bindings = binds, from = UnitName("player") .. "-" .. (GetRealmName() or ""),
                      level = UnitLevel("player"), made = date("%Y-%m-%d %H:%M") }
    if not BP.defaultName() then b.default = name end
    C.plan = name
    C.placed = {}
    for s, e in pairs(slots) do C.placed[s] = e.name or e.id end
    local aOn, aAll = addOnCount(addons)
    say(string.format("%s \"%s\": %d buttons, %d of %d addons on, chat tabs %s%s%s.%s", was and "replaced" or "saved", name, n, aOn, aAll,
        (chat and chatNames(chat) or "(not readable)") .. (binds and (binds.set == CHAR_SET
            and (", " .. count(binds.keys) .. " keybindings of its own") or ", account-wide keybindings") or ""),
        (pinned > 0 and (", " .. pinned .. " spells kept at a lower rank") or "")
            .. (spellMacros > 0 and (", " .. spellMacros .. " single-spell macros kept as their spell") or ""),
        skipped > 0 and (" (" .. skipped .. " buttons of a kind it can't place left out)") or "",
        b.default == name and (" New " .. className() .. "s get it.") or ""))
    if BP.refreshUI then BP.refreshUI() end
    return name
end

-- set this character's bars up from a plan of its class: what you can have now goes on, spells you haven't
-- learned wait for you, and buttons the plan has empty are cleared
function BP.apply(name)
    if InCombatLockdown() then say("not in combat - try again after the fight") return end
    local plan
    if name and name ~= "" then plan = BP.plan(name) else plan, name = BP.planFor() end
    if not plan then
        say(name and ("your class has no plan called \"" .. name .. "\"") or "no plan for your class yet - save one on a character whose bars are done")
        return
    end
    local book = scanBook()
    local placed, waiting, cleared, made, failed = 0, {}, 0, {}, {}
    C.plan, C.placed, C.off, C.asked = name, {}, nil, true
    for slot = 1, MAX_SLOT do
        local e = plan.slots[slot]
        local cur = readSlot(slot)
        if e then
            if holds(cur, e, book) then
                C.placed[slot] = e.name or e.id
            else
                local ok, why = place(slot, e, book, made)
                if ok then
                    placed = placed + 1
                    C.placed[slot] = e.name or e.id
                else
                    if cur then clearSlot(slot); cleared = cleared + 1 end
                    if e.k == "spell" then waiting[#waiting + 1] = e.name
                    else failed[#failed + 1] = describe(e) .. (why and (" (" .. why .. ")") or "") end
                end
            end
        elseif cur then
            clearSlot(slot)
            cleared = cleared + 1
        end
    end
    say(string.format("bars set up from \"%s\": %d placed, %d cleared%s; %d spells go on as you learn them.",
        name, placed, cleared, #made > 0 and (", " .. #made .. " macros made") or "", #waiting))
    if #failed > 0 then say("couldn't place: " .. table.concat(failed, ", ")) end
    local ok, ct = true, false
    if DB.opts.chat then ok, ct = pcall(applyChat, plan.chat) end
    if ct == false then -- (switched off in the window)
    elseif not ok then say("chat tabs couldn't be set up: " .. tostring(ct))
    elseif not ct then say("this plan has no chat tabs yet - save it again on its character to keep them.")
    else
        say(string.format("chat tabs set up as the plan's (%s)%s%s.", chatNames(plan.chat),
            ct.made > 0 and (", " .. ct.made .. " opened") or "", ct.closed > 0 and (", " .. ct.closed .. " closed") or ""))
    end
    if DB.opts.keys then
        local okb, kb = pcall(applyBindings, plan.bindings)
        if not okb then say("keybindings couldn't be set up: " .. tostring(kb))
        elseif not kb then say("this plan has no keybindings yet - save it again on its character to keep them.")
        elseif kb.set == CHAR_SET then say("keybindings set up as the plan's (this character's own; " .. kb.changed .. " keys changed).")
        elseif kb.changed > 0 then say("this character uses the account-wide keybindings again, as the plan's character did.") end
    end
    local a = DB.opts.addons and applyAddOns(plan.addons)
    if a == false then -- (switched off in the window)
    elseif not a then
        say("this plan has no addon list yet - save it again on its character to keep which addons are on.")
    else
        if #a.missing > 0 then say("addons of the plan you don't have installed: " .. table.concat(a.missing, ", ")) end
        if (a.on + a.off) > 0 then
            say(string.format("addons switched to the plan's: %d on, %d off - they change at the next reload.", a.on, a.off))
            if BP.askReload then BP.askReload(a) end
        end
    end
    if BP.refreshUI then BP.refreshUI() end
end

-- a spell you just learned (or a new rank): onto its planned button when that's empty or holds an older rank.
-- A button you emptied yourself after the plan filled it stays empty; one you put something else on is yours.
local pending = false
function BP.fill()
    if not (C and C.plan) or C.off then return end
    local plan = BP.plan(C.plan)
    if not plan then return end
    if InCombatLockdown() then pending = true return end
    pending = false
    local book = scanBook()
    local news, fresh = {}, {}
    for slot, e in pairs(plan.slots) do
        if e.k == "spell" and book[e.name] then
            local cur = readSlot(slot)
            local _, r = wantedID(e, book)
            if not cur then
                if C.placed[slot] ~= e.name and place(slot, e, book) then
                    C.placed[slot] = e.name
                    fresh[e.name] = true
                    news[#news + 1] = describe({ k = "spell", name = e.name, rank = r })
                end
            elseif cur.k == "spell" and cur.name == e.name and r and cur.rank < r then
                if place(slot, e, book) then news[#news + 1] = describe({ k = "spell", name = e.name, rank = r }) end
            end
        end
    end
    -- (a spell the game itself put on a free button as you learned it: its place is the plan's)
    if next(fresh) then
        for slot = 1, MAX_SLOT do
            if not plan.slots[slot] then
                local cur = readSlot(slot)
                if cur and cur.k == "spell" and fresh[cur.name] then clearSlot(slot) end
            end
        end
    end
    if #news > 0 then say("on your bars: " .. table.concat(news, ", ")) end
    if #news > 0 and BP.refreshUI then BP.refreshUI() end
end

-- the plan's spells you don't know yet: { { slot, name }, ... } by slot
function BP.waiting(plan)
    local book = scanBook()
    local t = {}
    for slot, e in pairs(plan and plan.slots or {}) do
        if e.k == "spell" and not book[e.name] then t[#t + 1] = { slot, e.name } end
    end
    table.sort(t, function(a, b) return a[1] < b[1] end)
    return t
end

function BP.planInfo(name)
    local p = BP.plan(name)
    if not p then return "" end
    local who = tostring(p.from or "?"):match("^[^-]+") or tostring(p.from)
    local aOn = addOnCount(p.addons)
    return string.format("Saved on %s at level %s, %s  ·  %d buttons  ·  %s", who, tostring(p.level), tostring(p.made),
        count(p.slots), p.addons and (aOn .. " addons on") or "no addon list")
        .. (p.chat and ("  ·  " .. #p.chat .. " chat tabs") or "")
        .. (p.bindings and (p.bindings.set == CHAR_SET and ("  ·  own keybindings") or "  ·  account keybindings") or "")
end

function BP.status()
    local plan, name = BP.planFor()
    if not plan then say("no plan for your class yet - save one on a character whose bars are done (/barplan).") return end
    say(string.format("plan \"%s\" (%s)%s", name, BP.planInfo(name),
        C.plan == name and (C.off and "; filling is off" or "; this character follows it") or "; not applied here yet"))
    if plan.addons then
        local installed, diff = readAddOns(), {}
        for a, want in pairs(plan.addons) do
            if a ~= ADDON and installed[a] ~= nil and installed[a] ~= want then diff[#diff + 1] = a .. (want and " (on)" or " (off)") end
        end
        table.sort(diff)
        if #diff > 0 then say("addons not as the plan has them: " .. table.concat(diff, ", ")) end
    end
    local w = BP.waiting(plan)
    if #w > 0 then
        local t = {}
        for i, x in ipairs(w) do if i <= 25 then t[#t + 1] = x[2] .. " (" .. x[1] .. ")" end end
        say(#w .. " spells to learn: " .. table.concat(t, ", ") .. (#w > 25 and ", ..." or ""))
    end
end

---------------------------------------------------------------- the window
-- In Itinerary's look (flat, a thin accent line, the same font and colours - Itinerary's color scheme when it's
-- installed). Only BarPlan's own frames: nothing of the game's shared UI (popups, dropdown menus) is touched,
-- so nothing of the game's protected UI gets blamed on BarPlan.

local W, PAD = 440, 18
local function IT() return rawget(_G, "ItineraryAPI") end
local function accent()
    local it = IT()
    if it and it.accent then
        local ok, r, g, b = pcall(it.accent)
        if ok and r then return r, g, b end
    end
    local e = rawget(_G, "EllesmereUI") and EllesmereUI.ELLESMERE_GREEN
    if e and e.r then return e.r, e.g, e.b end
    return 0.05, 0.82, 0.62
end
local function themed(fn, r, g, b)
    local it = IT()
    if it and it[fn] then
        local ok, r2, g2, b2 = pcall(it[fn], 1)
        if ok and r2 then return r2, g2, b2 end
    end
    return r, g, b
end
local function bgColor() return themed("themeBg", 0.077, 0.068, 0.058) end
local function btnColor() return themed("themeBtn", 0.075, 0.113, 0.141) end
local function onAccent()
    local it = IT()
    if it and it.theme then
        local ok, t = pcall(it.theme)
        if ok and type(t) == "table" and t.onAccent then return t.onAccent[1], t.onAccent[2], t.onAccent[3] end
    end
    return 0.05, 0.05, 0.05
end
local function fontPath()
    local E = rawget(_G, "EllesmereUI")
    if E and E.GetFontPath then
        local ok, path = pcall(E.GetFontPath)
        if ok and path then return path end
    end
    return STANDARD_TEXT_FONT
end
local function addEdges(frame, r, g, b, a)
    local edges = {}
    local px = 1 / ((frame.GetEffectiveScale and frame:GetEffectiveScale()) or 1)
    local function edge() local t = frame:CreateTexture(nil, "BORDER"); t:SetColorTexture(r, g, b, a); edges[#edges + 1] = t; return t end
    local t = edge(); t:SetPoint("TOPLEFT"); t:SetPoint("TOPRIGHT"); t:SetHeight(px)
    local bt = edge(); bt:SetPoint("BOTTOMLEFT"); bt:SetPoint("BOTTOMRIGHT"); bt:SetHeight(px)
    local l = edge(); l:SetPoint("TOPLEFT"); l:SetPoint("BOTTOMLEFT"); l:SetWidth(px)
    local rt = edge(); rt:SetPoint("TOPRIGHT"); rt:SetPoint("BOTTOMRIGHT"); rt:SetWidth(px)
    function edges:SetColor(r2, g2, b2, a2) for _, e in ipairs(self) do e:SetColorTexture(r2, g2, b2, a2) end end
    return edges
end
local function text(parent, size, r, g, b, a)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(fontPath(), size, "")
    fs:SetTextColor(r, g, b, a or 1)
    fs:SetJustifyH("LEFT")
    return fs
end
local function panelBg(frame, a)
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    local r, g, b = bgColor()
    bg:SetColorTexture(r, g, b, a or 0.97)
    addEdges(frame, 1, 1, 1, 0.15)
    return bg
end

-- a flat button like Itinerary's switch segments and chips: lit (accent) when active
local function flat(parent, label, w, h)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w or 74, h or 22)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.edges = addEdges(b, 1, 1, 1, 0.18)
    b.text = text(b, 12, 1, 1, 1, 0.5)
    b.text:SetPoint("LEFT", 4, 0)
    b.text:SetPoint("RIGHT", -4, 0)
    b.text:SetJustifyH("CENTER")
    b.text:SetText(label or "")
    function b:SetLabel(t) self.text:SetText(t) end
    function b:Paint()
        local ar, ag, ab = accent()
        if self.off then
            self.bg:SetColorTexture(btnColor()); self.bg:SetAlpha(0.6); self.edges:SetColor(1, 1, 1, 0.08)
            self.text:SetTextColor(1, 1, 1, 0.2)
        elseif self.active then
            self.bg:SetColorTexture(ar, ag, ab, 0.9); self.bg:SetAlpha(1); self.edges:SetColor(ar, ag, ab, 1)
            local r, g, bb = onAccent(); self.text:SetTextColor(r, g, bb, 1)
        else
            self.bg:SetColorTexture(btnColor()); self.bg:SetAlpha(1); self.edges:SetColor(1, 1, 1, 0.18)
            self.text:SetTextColor(1, 1, 1, self.hover and 0.85 or 0.5)
        end
    end
    function b:SetActive(on) self.active = on and true or false; self:Paint() end
    function b:SetUsable(on) self.off = not on; self:SetEnabled(on and true or false); self:Paint() end
    b:SetScript("OnEnter", function(self)
        self.hover = true; self:Paint()
        if self.tip then GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine(self.tip, 1, 1, 1, true); GameTooltip:Show() end
    end)
    b:SetScript("OnLeave", function(self) self.hover = false; self:Paint(); GameTooltip:Hide() end)
    b:Paint()
    return b
end

-- two segments, one lit: { "On", "Off" } -> onPick(true / false)
local function switch(parent, labels, onPick)
    local s = CreateFrame("Frame", nil, parent)
    s:SetSize(74 * 2 - 1, 22)
    s.a = flat(s, labels[1]); s.a:SetPoint("LEFT")
    s.b = flat(s, labels[2]); s.b:SetPoint("LEFT", s.a, "RIGHT", -1, 0)
    s.a:SetScript("OnClick", function() onPick(true) end)
    s.b:SetScript("OnClick", function() onPick(false) end)
    function s:Set(on) self.value = on and true or false; self.a:SetActive(on); self.b:SetActive(not on) end
    function s:SetUsable(on) self.a:SetUsable(on); self.b:SetUsable(on); if on then self:Set(self.value) end end
    return s
end


-- a dropdown of our own: a flat box with the choice, a list under it
local function dropdown(parent, width, onPick)
    local dd = flat(parent, "", width, 22)
    dd.text:SetJustifyH("LEFT")
    dd.text:SetPoint("LEFT", 8, 0)
    dd.text:SetPoint("RIGHT", -22, 0)
    -- (a small chevron of two strokes)
    dd.arrow = {}
    for k, side in ipairs({ -1, 1 }) do
        local t = dd:CreateTexture(nil, "ARTWORK")
        t:SetColorTexture(1, 1, 1, 0.55)
        t:SetSize(7, 1.5)
        t:SetPoint("CENTER", dd, "RIGHT", -12 + side * 2.4, -1)
        if t.SetRotation then t:SetRotation(math.rad(side * -45)) end
        dd.arrow[k] = t
    end
    dd.list = CreateFrame("Frame", nil, dd)
    dd.list:SetPoint("TOPLEFT", dd, "BOTTOMLEFT", 0, -2)
    dd.list:SetWidth(width)
    dd.list:SetFrameStrata("FULLSCREEN_DIALOG")
    panelBg(dd.list, 0.99)
    dd.list:Hide()
    dd.rows = {}
    function dd:SetItems(items, selected)
        self.items, self.value = items, selected
        self.text:SetText(selected or (#items == 0 and "no plans yet" or "choose a plan"))
        self.text:SetTextColor(1, 1, 1, selected and 0.9 or 0.35)
        local ar, ag, ab = accent()
        for i, it in ipairs(items) do
            local r = self.rows[i]
            if not r then
                r = CreateFrame("Button", nil, self.list)
                r:SetSize(width - 2, 20)
                r:SetPoint("TOPLEFT", 1, -1 - (i - 1) * 20)
                r.hl = r:CreateTexture(nil, "BACKGROUND")
                r.hl:SetAllPoints()
                r.hl:SetColorTexture(ar, ag, ab, 0.2)
                r.hl:Hide()
                r.text = text(r, 12, 1, 1, 1, 0.8)
                r.text:SetPoint("LEFT", 8, 0)
                r:SetScript("OnEnter", function(row) row.hl:Show() end)
                r:SetScript("OnLeave", function(row) row.hl:Hide() end)
                r:SetScript("OnClick", function(row)
                    dd.list:Hide()
                    dd.value = row.item
                    dd.text:SetText(row.item)
                    if onPick then onPick(row.item) end
                end)
                self.rows[i] = r
            end
            r.item = it
            r.text:SetText(it)
            if it == selected then r.text:SetTextColor(ar, ag, ab, 1) else r.text:SetTextColor(1, 1, 1, 0.8) end
            r:Show()
        end
        for i = #items + 1, #self.rows do self.rows[i]:Hide() end
        self.list:SetHeight(math.max(1, #items) * 20 + 2)
    end
    dd:SetScript("OnClick", function(self)
        if self.list:IsShown() or not self.items or #self.items == 0 then self.list:Hide() else self.list:Show() end
    end)
    dd:SetScript("OnHide", function(self) self.list:Hide() end)
    return dd
end

local function editBox(parent, w)
    local e = CreateFrame("EditBox", nil, parent)
    e:SetSize(w, 22)
    e:SetFont(fontPath(), 12, "")
    e:SetTextColor(1, 1, 1, 0.9)
    e:SetTextInsets(8, 8, 0, 0)
    e:SetAutoFocus(false)
    local bg = e:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.35)
    e.edges = addEdges(e, 1, 1, 1, 0.18)
    e:SetScript("OnEditFocusGained", function(self) local r, g, b = accent(); self.edges:SetColor(r, g, b, 0.9) end)
    e:SetScript("OnEditFocusLost", function(self) self.edges:SetColor(1, 1, 1, 0.18) end)
    return e
end

local function header(frame, titleText, descText)
    local r, g, b = accent()
    local top = frame:CreateTexture(nil, "ARTWORK")
    top:SetColorTexture(r, g, b, 0.9)
    top:SetPoint("TOPLEFT", 1, -1); top:SetPoint("TOPRIGHT", -1, -1); top:SetHeight(2)
    local eyebrow = text(frame, 12, r, g, b, 0.9)
    eyebrow:SetPoint("TOPLEFT", PAD, -16)
    eyebrow:SetText("BARPLAN")
    local title = text(frame, 19, 1, 1, 1, 1)
    title:SetPoint("TOPLEFT", eyebrow, "BOTTOMLEFT", 0, -4)
    title:SetText(titleText or "")
    local desc = text(frame, 12, 1, 1, 1, 0.45)
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    desc:SetWidth((frame:GetWidth() or W) - PAD * 2)
    desc:SetWordWrap(true)
    desc:SetText(descText or "")
    local close = CreateFrame("Button", nil, frame)
    close:SetSize(24, 24)
    close:SetPoint("TOPRIGHT", -8, -8)
    local x = text(close, 18, 1, 1, 1, 0.5)
    x:SetPoint("CENTER")
    x:SetJustifyH("CENTER")
    x:SetText("×")
    close:SetScript("OnEnter", function() x:SetTextColor(1, 1, 1, 0.9) end)
    close:SetScript("OnLeave", function() x:SetTextColor(1, 1, 1, 0.5) end)
    close:SetScript("OnClick", function() frame:Hide() end)
    return title, desc, eyebrow, close
end

-- The window is laid out top to bottom from its contents (wrapped lines measured), so nothing overlaps and the
-- window is as tall as it needs to be.
local function strH(fs, fallback)
    local h = fs.GetStringHeight and fs:GetStringHeight()
    if type(h) ~= "number" or h <= 0 then h = fallback or 14 end
    return math.ceil(h)
end
local CTRL_W = 2 * 74 - 1 -- (an On/Off switch)
local function at(el, parent, x, y) el:ClearAllPoints(); el:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y) end
local function atRight(el, parent, y) el:ClearAllPoints(); el:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -PAD, -y) end
local function newDivider(parent)
    local d = parent:CreateTexture(nil, "ARTWORK")
    d:SetColorTexture(1, 1, 1, 0.08)
    d:SetHeight(1)
    return d
end
local function placeDivider(d, parent, y)
    d:ClearAllPoints()
    d:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, -y)
    d:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -PAD, -y)
end
-- a row's title and its grey line; narrow when a control sits on the right
local function rowText(parent, title, narrow)
    local t = text(parent, 13, 1, 1, 1, 0.92)
    t:SetText(title)
    local d = text(parent, 11, 1, 1, 1, 0.45)
    d:SetWidth(W - PAD * 2 - (narrow and (CTRL_W + 16) or 0))
    d:SetWordWrap(true)
    return t, d
end

-- what Apply does besides the bars, as the options are set
local function alsoText()
    local o, t = DB.opts, {}
    if o.addons then t[#t + 1] = "addons" end
    if o.chat then t[#t + 1] = "chat tabs" end
    if o.keys then t[#t + 1] = "keybindings" end
    if #t == 0 then return nil end
    local list = #t == 1 and t[1] or (table.concat(t, ", ", 1, #t - 1) .. " and " .. t[#t])
    return "your " .. list .. " are switched to the plan's"
end

local win
local function build()
    win = CreateFrame("Frame", "BarPlanFrame", UIParent)
    win:SetSize(W, 500)
    local pos = DB.pos
    if pos then win:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else win:SetPoint("CENTER", 0, 60) end
    win:SetFrameStrata("DIALOG")
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    win:SetMovable(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", function()
        win:StopMovingOrSizing()
        local p, _, rp, x, y = win:GetPoint()
        DB.pos = { p, rp, x, y }
    end)
    tinsert(UISpecialFrames, "BarPlanFrame") -- Escape closes it (as Itinerary's settings)
    panelBg(win)
    win.title, win.desc, win.eyebrow = header(win, "", "Save your bars, which addons are on, your chat tabs and keybindings as a plan of your class. A new character picks one and gets the same bars, and (as set below) addons, chat tabs and keybindings; the spells it learns go onto their buttons.")
    win.divs = {}
    for i = 1, 7 do win.divs[i] = newDivider(win) end

    -- this character
    win.charHead, win.charDesc = rowText(win, "This character")
    win.fillHead, win.fillDesc = rowText(win, "Learned spells onto their buttons", true)
    win.fillDesc:SetText("New spells and ranks go where the plan has them.")
    win.fill = switch(win, { "On", "Off" }, function(on)
        C.off = not on or nil
        if on then BP.fill() end
        BP.refreshUI()
    end)

    -- your class's plans
    win.plansHead, win.plansDesc = rowText(win, "Plans")
    win.dd = dropdown(win, 220, function(name) win.sel = name; win.applyArmed, win.delArmed = nil, nil; BP.refreshUI() end)
    win.apply = flat(win, "Apply", 84)
    win.apply:SetScript("OnClick", function()
        if not win.sel then return end
        -- (a second click: it clears what the plan doesn't have)
        if not win.applyArmed then win.applyArmed = true; BP.refreshUI() return end
        win.applyArmed = nil
        BP.apply(win.sel)
    end)
    win.del = flat(win, "Delete", 84)
    win.del:SetScript("OnClick", function()
        if not win.sel then return end
        if not win.delArmed then win.delArmed = true; BP.refreshUI() return end
        win.delArmed = nil
        local n = win.sel
        if BP.delete(n) then say("deleted \"" .. n .. "\"") end
        win.sel = nil
        BP.refreshUI()
    end)
    win.info = text(win, 11, 1, 1, 1, 0.45)
    win.info:SetWidth(W - PAD * 2)
    win.info:SetWordWrap(true)
    win.offerHead, win.offerDesc = rowText(win, "", true)
    win.offerDesc:SetText("New characters of your class are asked at their first login.")
    win.offer = switch(win, { "Yes", "No" }, function(on)
        local b = bucket()
        if not win.sel then return end
        if on then b.default = win.sel elseif b.default == win.sel then b.default = nil end
        BP.refreshUI()
    end)
    
    -- what Apply sets up besides the bars
    win.optAddHead, win.optAddDesc = rowText(win, "Addons", true)
    win.optAddDesc:SetText("Apply switches this character's addons to the ones the plan had on (at the next reload).")
    win.optAdd = switch(win, { "On", "Off" }, function(on) DB.opts.addons = on; win.applyArmed = nil; BP.refreshUI() end)
    win.optChatHead, win.optChatDesc = rowText(win, "Chat tabs", true)
    win.optChatDesc:SetText("Apply sets this character's chat tabs up as the plan's: names, message types, channels, order.")
    win.optChat = switch(win, { "On", "Off" }, function(on) DB.opts.chat = on; win.applyArmed = nil; BP.refreshUI() end)
    win.optKeysHead, win.optKeysDesc = rowText(win, "Keybindings", true)
    win.optKeysDesc:SetText("Apply gives this character the plan's keybindings: its own set when the plan's character had one, the account-wide keys otherwise.")
    win.optKeys = switch(win, { "On", "Off" }, function(on) DB.opts.keys = on; win.applyArmed = nil; BP.refreshUI() end)
    win.charKeysHead, win.charKeysDesc = rowText(win, "Character specific keybindings", true)
    win.charKeys = switch(win, { "On", "Off" }, function(on) BP.setCharBindings(on) end)

    -- save your bars
    win.saveHead, win.saveDesc = rowText(win, "Save your bars")
    win.saveDesc:SetText("Every button of your bars (spells, macros, items), which addons are on, your chat tabs and keybindings, under a name.")
    win.name = editBox(win, 220)
    win.name:SetMaxLetters(40)
    win.name:SetScript("OnEnterPressed", function(self) self:ClearFocus(); win.save:Click() end)
    win.name:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    win.name:SetScript("OnTextChanged", function() if win.saveArmed then win.saveArmed = nil; BP.refreshUI() end end)
    win.save = flat(win, "Save", 84)
    win.save:SetScript("OnClick", function()
        local n = (win.name:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if n == "" then n = className() end
        -- (a plan of that name already: a second click replaces it)
        if BP.plan(n) and not win.saveArmed then win.saveArmed = true; BP.refreshUI() return end
        win.saveArmed = nil
        win.sel = BP.record(n)
        BP.refreshUI()
    end)
    win.saveNote = text(win, 11, 1, 1, 1, 0.45)
    win.saveNote:SetWidth(W - PAD * 2)
    win.saveNote:SetWordWrap(true)

    -- minimap button
    win.miniHead, win.miniDesc = rowText(win, "Minimap button", true)
    win.miniDesc:SetText("Click it to open this window.")
    win.mini = switch(win, { "Show", "Hide" }, function(on) BP.setMinimap(on) end)

    win.hint = text(win, 11, 1, 1, 1, 0.3)
    win.hint:SetWidth(W - PAD * 2)
    win.hint:SetWordWrap(true)
    win.hint:SetText("Plans are per class and shared by all your characters. Applying one changes this character only: its bars, and its addons, chat tabs and keybindings when those are on. Drag the window anywhere; Escape closes it.")
    win:SetScript("OnShow", function() BP.refreshUI() end)
    win:Hide()
end

-- top to bottom: each part below the one before, the window's height from the last
local function layout()
    local y = 16
    at(win.eyebrow, win, PAD, y); y = y + strH(win.eyebrow, 12) + 4
    at(win.title, win, PAD, y); y = y + strH(win.title, 19) + 6
    at(win.desc, win, PAD, y); y = y + strH(win.desc, 28) + 14
    local d = 0
    local function div() d = d + 1; placeDivider(win.divs[d], win, y); y = y + 1 end
    -- a row: title, grey line, a control on the right next to the title
    local function row(head, desc, ctrl)
        y = y + 12
        local top = y
        if head:GetText() and head:GetText() ~= "" then at(head, win, PAD, y); y = y + strH(head, 13) + 3 end
        at(desc, win, PAD, y); y = y + strH(desc, 11)
        if ctrl then atRight(ctrl, win, top); y = math.max(y, top + 22) end
    end
    div()
    row(win.charHead, win.charDesc)
    y = y + 2
    row(win.fillHead, win.fillDesc, win.fill)
    y = y + 12; div()
    row(win.plansHead, win.plansDesc)
    y = y + 8
    at(win.dd, win, PAD, y)
    atRight(win.del, win, y)
    win.apply:ClearAllPoints(); win.apply:SetPoint("RIGHT", win.del, "LEFT", -6, 0)
    y = y + 22 + 6
    at(win.info, win, PAD, y); y = y + strH(win.info, 11) + 2
    row(win.offerHead, win.offerDesc, win.offer)
    y = y + 12; div()
    row(win.optAddHead, win.optAddDesc, win.optAdd)
    y = y + 2
    row(win.optChatHead, win.optChatDesc, win.optChat)
    y = y + 2
    row(win.optKeysHead, win.optKeysDesc, win.optKeys)
    y = y + 2
    row(win.charKeysHead, win.charKeysDesc, win.charKeys)
    y = y + 12; div()
    row(win.saveHead, win.saveDesc)
    y = y + 8
    at(win.name, win, PAD, y)
    win.save:ClearAllPoints(); win.save:SetPoint("LEFT", win.name, "RIGHT", 6, 0)
    y = y + 22
    if (win.saveNote:GetText() or "") ~= "" then y = y + 6; at(win.saveNote, win, PAD, y); y = y + strH(win.saveNote, 11); win.saveNote:Show() else win.saveNote:Hide() end
    y = y + 12; div()
    row(win.miniHead, win.miniDesc, win.mini)
    y = y + 12; div()
    y = y + 10
    at(win.hint, win, PAD, y); y = y + strH(win.hint, 26) + 14
    win:SetHeight(y)
end

function BP.refreshUI()
    if not (win and win:IsShown()) then return end
    local cls = className()
    win.title:SetText(cls .. " bars")
    local names = BP.planNames()
    local have = {}
    for _, n in ipairs(names) do have[n] = true end
    if not (win.sel and have[win.sel]) then win.sel = (C.plan and have[C.plan] and C.plan) or BP.defaultName() or names[1] end
    -- this character
    local follows = C.plan and have[C.plan]
    if follows then
        local w = BP.waiting(BP.plan(C.plan))
        win.charDesc:SetText("Follows " .. C.plan .. (#w > 0 and (" - " .. #w .. " of its spells still to learn") or " - all its spells learned"))
    else
        win.charDesc:SetText("Doesn't follow a plan yet - pick one below and click Apply.")
    end
    win.fill:Set(not C.off)
    win.fill:SetUsable(follows == true)
    -- plans
    win.plansDesc:SetText(#names > 0 and ("Your " .. cls .. " plans. Apply sets this character's bars up from the one chosen.")
        or ("No " .. cls .. " plan yet: save your bars below on a character whose bars are done."))
    win.dd:SetItems(names, win.sel)
    local also = alsoText()
    win.info:SetText(win.applyArmed and ("Click Apply again: your bars become the plan's" .. (also and ", buttons it has empty are cleared, and " .. also .. "." or " and buttons it has empty are cleared."))
        or (win.delArmed and "Click Delete again to delete it." or (win.sel and BP.planInfo(win.sel) or "")))
    win.apply:SetUsable(win.sel ~= nil and not InCombatLockdown())
    win.apply:SetLabel(win.applyArmed and "Sure?" or "Apply")
    win.apply:SetActive(win.applyArmed)
    win.del:SetUsable(win.sel ~= nil)
    win.del:SetLabel(win.delArmed and "Sure?" or "Delete")
    win.del:SetActive(win.delArmed)
    win.offerHead:SetText("Offer it to new " .. cls .. "s")
    win.offer:Set(win.sel ~= nil and BP.defaultName() == win.sel)
    win.offer:SetUsable(win.sel ~= nil)
    -- save
    if (win.name:GetText() or "") == "" and not win.name:HasFocus() then win.name:SetText(C.plan or cls) end
    local n = (win.name:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
    win.save:SetLabel(win.saveArmed and "Replace?" or "Save")
    win.save:SetActive(win.saveArmed)
    win.saveNote:SetText(win.saveArmed and ("\"" .. n .. "\" exists - click Replace? to put these bars in it.") or "")
    win.optAdd:Set(DB.opts.addons)
    win.optChat:Set(DB.opts.chat)
    win.optKeys:Set(DB.opts.keys)
    local own = charBindings() and true or false
    win.charKeysDesc:SetText(own and "This character uses its own keybindings (as the game's \"character specific\" box). Off: back to the account-wide keys."
        or "This character uses the account-wide keybindings. On: its own set, starting as a copy of the keys you have now.")
    win.charKeys:Set(own)
    win.charKeys:SetUsable(not InCombatLockdown())
    win.mini:Set(not DB.minimap.hide)
    layout()
end

function BP.toggle()
    if not win then build() end
    if win:IsShown() then win:Hide() else win.applyArmed, win.delArmed, win.saveArmed = nil, nil, nil; win:Show() end
end

-- the question at a new character's first login: the class's plans in a dropdown, the offered one chosen
local ask
local function askApply(name)
    if not ask then
        ask = CreateFrame("Frame", "BarPlanAsk", UIParent)
        ask:SetSize(W, 200)
        ask:SetPoint("TOP", UIParent, "TOP", 0, -160)
        ask:SetFrameStrata("DIALOG")
        ask:EnableMouse(true)
        panelBg(ask)
        ask.title, ask.desc, ask.eyebrow = header(ask, "", "")
        ask.dd = dropdown(ask, 220, function(n) ask.plan = n end)
        ask.yes = flat(ask, "Set up my bars", 130)
        ask.yes:SetActive(true)
        ask.yes:SetScript("OnClick", function() ask:Hide(); BP.apply(ask.plan) end)
        ask.no = flat(ask, "Not now", 90)
        ask.no:SetScript("OnClick", function() ask:Hide(); C.asked = true; say("not now - the minimap button or /barplan when you want it") end)
    end
    ask.plan = name
    ask.title:SetText("Set up your " .. className() .. " bars?")
    local also = alsoText()
    ask.desc:SetText("What your character knows goes on now, the rest as it learns it. Buttons the plan has empty are cleared"
        .. (also and (", and " .. also) or "") .. ".")
    ask.dd:SetItems(BP.planNames(), name)
    local y = 16
    at(ask.eyebrow, ask, PAD, y); y = y + strH(ask.eyebrow, 12) + 4
    at(ask.title, ask, PAD, y); y = y + strH(ask.title, 19) + 6
    at(ask.desc, ask, PAD, y); y = y + strH(ask.desc, 28) + 14
    at(ask.dd, ask, PAD, y); y = y + 22 + 12
    at(ask.yes, ask, PAD, y)
    ask.no:ClearAllPoints(); ask.no:SetPoint("LEFT", ask.yes, "RIGHT", 6, 0)
    y = y + 22 + 16
    ask:SetHeight(y)
    ask:Show()
end
BP.askApply = askApply

-- after an apply switched addons: they change at a reload, offered here (a click, as the game wants for it)
local rel
function BP.askReload(a)
    if not rel then
        rel = CreateFrame("Frame", "BarPlanReload", UIParent)
        rel:SetSize(W, 160)
        rel:SetPoint("TOP", UIParent, "TOP", 0, -160)
        rel:SetFrameStrata("DIALOG")
        rel:EnableMouse(true)
        panelBg(rel)
        rel.title, rel.desc, rel.eyebrow = header(rel, "Reload for your addons?", "")
        rel.yes = flat(rel, "Reload now", 130)
        rel.yes:SetActive(true)
        rel.yes:SetScript("OnClick", function() ReloadUI() end)
        rel.no = flat(rel, "Later", 90)
        rel.no:SetScript("OnClick", function() rel:Hide(); say("your addons change at the next reload or login") end)
    end
    rel.desc:SetText(string.format("The plan's addons are set for this character (%d switched on, %d off). They take effect when the interface reloads.", a.on, a.off))
    local y = 16
    at(rel.eyebrow, rel, PAD, y); y = y + strH(rel.eyebrow, 12) + 4
    at(rel.title, rel, PAD, y); y = y + strH(rel.title, 19) + 6
    at(rel.desc, rel, PAD, y); y = y + strH(rel.desc, 28) + 14
    at(rel.yes, rel, PAD, y)
    rel.no:ClearAllPoints(); rel.no:SetPoint("LEFT", rel.yes, "RIGHT", 6, 0)
    y = y + 22 + 16
    rel:SetHeight(y)
    rel:Show()
end

---------------------------------------------------------------- the minimap button
-- (LibDBIcon: dragged around the minimap, collected by minimap button bags; BarPlanDB.minimap keeps its place)
local ICON = "Interface\\Icons\\INV_Misc_Note_01"
local function setupMinimap()
    local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
    local DBIcon = LibStub and LibStub("LibDBIcon-1.0", true)
    if not (LDB and DBIcon) or DBIcon:IsRegistered("BarPlan") then return end
    local obj = LDB:NewDataObject("BarPlan", {
        type = "launcher", text = "BarPlan", icon = ICON,
        OnClick = function() BP.toggle() end,
        OnTooltipShow = function(tt)
            tt:AddLine("BarPlan")
            if C.plan and BP.plan(C.plan) then
                local w = BP.waiting(BP.plan(C.plan))
                tt:AddLine("Follows |cff66bbff" .. C.plan .. "|r" .. (#w > 0 and (" - " .. #w .. " spells to learn") or ""), 1, 1, 1)
            else
                tt:AddLine("No plan for this character yet", 0.7, 0.7, 0.7)
            end
            tt:AddLine("|cffffffffClick|r open the window", 0.7, 0.7, 0.7)
            tt:AddLine("|cffffffffDrag|r move the button", 0.7, 0.7, 0.7)
        end,
    })
    DBIcon:Register("BarPlan", obj, DB.minimap)
end
function BP.setMinimap(show)
    local DBIcon = LibStub and LibStub("LibDBIcon-1.0", true)
    DB.minimap.hide = not show or nil
    if DBIcon then if show then DBIcon:Show("BarPlan") else DBIcon:Hide("BarPlan") end end
    if BP.refreshUI then BP.refreshUI() end
end

---------------------------------------------------------------- events, commands

local f = CreateFrame("Frame")
-- (each on its own: a client that doesn't know an event name throws, and the rest of the file wouldn't run -
-- WoW Forever has no LEARNED_SPELL_IN_TAB)
for _, e in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB",
                     "LEARNED_SPELL_IN_SKILL_LINE", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "UPDATE_BINDINGS" }) do
    pcall(f.RegisterEvent, f, e)
end
local soon = false
local function fillSoon()
    if soon then return end
    soon = true
    C_Timer.After(0.5, function() soon = false; BP.fill() end)
end
f:SetScript("OnEvent", function(_, event, arg)
    if event == "ADDON_LOADED" and arg == ADDON then
        BarPlanDB = BarPlanDB or {}
        BarPlanDB.classes = BarPlanDB.classes or {}
        -- (1.0: plans by name with their class inside)
        if BarPlanDB.plans then
            for name, p in pairs(BarPlanDB.plans) do
                if p.class then
                    local b = BarPlanDB.classes[p.class] or { plans = {} }
                    BarPlanDB.classes[p.class] = b
                    b.plans[name] = p
                    p.class = nil
                end
            end
            for class, name in pairs(BarPlanDB.default or {}) do
                if BarPlanDB.classes[class] and BarPlanDB.classes[class].plans[name] then BarPlanDB.classes[class].default = name end
            end
            BarPlanDB.plans, BarPlanDB.default = nil, nil
        end
        BarPlanDB.minimap = BarPlanDB.minimap or {}
        BarPlanDB.opts = BarPlanDB.opts or {}
        if BarPlanDB.opts.addons == nil then BarPlanDB.opts.addons = true end
        if BarPlanDB.opts.chat == nil then BarPlanDB.opts.chat = true end
        if BarPlanDB.opts.keys == nil then BarPlanDB.opts.keys = true end
        BarPlanCharDB = BarPlanCharDB or {}
        BarPlanCharDB.placed = BarPlanCharDB.placed or {}
        DB, C = BarPlanDB, BarPlanCharDB
    elseif event == "PLAYER_LOGIN" then
        pcall(setupMinimap)
        -- a character without a plan of its own: offer the class's plans once
        C_Timer.After(3, function()
            if C.plan or C.asked then fillSoon() return end
            local plan, name = BP.planFor()
            if not plan and #BP.planNames() > 0 then name = BP.planNames()[1] end
            if name and not InCombatLockdown() then askApply(name) end
        end)
    elseif event == "UPDATE_BINDINGS" then
        if BP.refreshUI and DB then BP.refreshUI() end
    elseif event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_REGEN_DISABLED" then
        if event == "PLAYER_REGEN_ENABLED" and pending then fillSoon() end
        if BP.refreshUI then BP.refreshUI() end
    elseif (event == "SPELLS_CHANGED" or event == "LEARNED_SPELL_IN_TAB" or event == "LEARNED_SPELL_IN_SKILL_LINE") and DB then
        fillSoon()
    end
end)

SLASH_BARPLAN1, SLASH_BARPLAN2 = "/barplan", "/bplan"
SlashCmdList.BARPLAN = function(msg)
    local cmd, arg = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    if cmd == "" then BP.toggle()
    elseif cmd == "record" or cmd == "save" then BP.record(arg)
    elseif cmd == "apply" then BP.apply(arg)
    elseif cmd == "list" then
        local names = BP.planNames()
        if #names == 0 then say("no " .. className() .. " plans yet") end
        for _, n in ipairs(names) do say(n .. " - " .. BP.planInfo(n) .. (BP.defaultName() == n and " (offered to new characters)" or "")) end
    elseif cmd == "use" then
        if not BP.plan(arg) then say("your class has no plan called \"" .. arg .. "\"") return end
        BP.setDefault(arg)
        say("new " .. className() .. "s are offered \"" .. arg .. "\"")
    elseif cmd == "delete" then
        if BP.delete(arg) then say("deleted \"" .. arg .. "\"") else say("your class has no plan called \"" .. arg .. "\"") end
        if BP.refreshUI then BP.refreshUI() end
    elseif cmd == "off" then C.off = true; say("learned spells aren't put on the bars any more (/barplan on)")
    elseif cmd == "on" then C.off = nil; say("learned spells go on their buttons again"); BP.fill()
    elseif cmd == "addons" or cmd == "chat" or cmd == "keys" then
        local key = cmd
        if arg == "on" then DB.opts[key] = true elseif arg == "off" then DB.opts[key] = false end
        say(({ addons = "addons", chat = "chat tabs", keys = "keybindings" })[key] .. " with Apply: " .. (DB.opts[key] and "on" or "off"))
        if BP.refreshUI then BP.refreshUI() end
    elseif cmd == "status" then BP.status()
    elseif cmd == "minimap" then BP.setMinimap(DB.minimap.hide and true or false); say(DB.minimap.hide and "minimap button hidden" or "minimap button shown")
    else
        say("/barplan - the window: save your bars as a plan, pick and apply one")
        say("/barplan save [name] - save this character's bars as a plan of its class (default name: your class)")
        say("/barplan apply [name] - set this character's bars up from a plan of its class")
        say("/barplan addons on|off, chat on|off, keys on|off - whether Apply also sets up addons / chat tabs / keybindings")
        say("/barplan status / list / use <name> / delete <name> / off / on / minimap")
    end
end
