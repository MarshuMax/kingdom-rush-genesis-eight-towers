-- Eight towers: eight tower slots in the Tower Room, and the same eight in the in-stage build menu.
-- Edit the setting below; needs a game restart after editing.
--
-- How (traced on kr6-desktop-1.00.052):
--  * There are four separate caps on the way from the save file to the build menu, and every one of
--    them has to be lifted. 1-3 are what you would expect; 4 is the one that actually keeps the
--    in-stage menu at five, and it is not a config value anywhere.
--
--  1. GS.number_of_towers (5) is the saved team size. It has to be raised before the save is read,
--     otherwise the save scrub trims everything past the fifth entry.
--
--  2. The Tower Room wheel is a kui template (group_towers_wheel) with five buttons hard-coded,
--     button_tower_ring_sel_01..05, and the game looks them up by slot number. 06..08 are cloned
--     from the first button and laid out on an even ring. kui_db.get_table returns a fresh copy on
--     every call, so the template has to be patched on every call, not once.
--
--  3. The in-stage tower list is not the Tower Room team. When a stage is initialised the game
--     replaces slot.towers.selected with the stage's own set (level.data.level_mode_overrides
--     [mode].available_towers, or the stage default); measured: eight in the Tower Room, the stage's
--     seven in store.selected_towers. The list is forced back to the saved team every 15 frames,
--     except when the current mode names its own available_towers (Iron and friends) - then the
--     stage keeps what it asked for.
--
--  4. The one that keeps the in-stage menu at five. TowerMenu.show(entity) takes a single entity and
--     gets its list from get_tower_menu_items(entity), a local in the same closure. That function
--     returns every tower the spot can build - all 19 of them - but it only stamps `place` on the
--     first five entries of the saved team, and show() only builds a button for entries that carry a
--     `place`. At the moment it runs, GS.number_of_towers, store.selected_towers and
--     load_slot().towers.selected all read 8, so the 5 is not any of them; it lives in that stamping.
--     This mod takes over the upvalue and stamps `place` for the entries the game skipped.
--     It only adds, it never clears: the same function also serves the "tap a built tower" upgrade
--     menu, whose places belong to the game, and clearing those removes every upgrade and sell option.
--
--  5. The button positions come from data.game_gui_data.tower_menu_button_places[place]. The stock
--     table has 19 offsets but they are not an even ring (entries 1 and 6 are 20 px apart), so eight
--     of them overlap. The first eight are laid out on an even ring instead. The table must never be
--     shortened: show() indexes it by slot number, and a short table yields nil, which vclone(nil)
--     crashes on.
--
-- Notes:
--  * slot.towers.selected is only ever read here, never written. An earlier version put the old
--    snapshot back inside storage.load_slot, which also fired in the Tower Room: swapping a tower
--    there was undone by the next load_slot.
--  * The team is tracked from load_slot only outside a stage. Inside one the slot holds the stage's
--    own list, and learning that as "the team" would carry the wrong towers forward.
--  * The in-stage menu is hooked once the tower_menu view exists, which is only after a stage has
--    started, so the hook is retried while in a stage.
--  * Requires a mod loader that calls M.init(api) and provides api.log and api.when_loaded.
--    Frames are taken from love.timer.getDelta directly, so api.on_frame is not needed.
local SLOTS = 8 -- tower slots: 8, or 5 for the game's own five

-- Tower Room ring: centre (-1.76, -14.58), radius ~124, measured off the stock template, which
-- spaces its five buttons 72 degrees apart.
local RING_CX, RING_CY = -1.76, -14.58
local RING_RADIUS = 125

-- In-stage ring: the 19 stock offsets are not on one radius, so eight of them collide. Own ring.
local HUD_CX, HUD_CY = 0, -4.97
local HUD_RADIUS = 88

-- Writes 8towers.log next to the save only when the loader offers no api.log.
local FALLBACK_LOG = true
local LOGFILE = "8towers.log"

local M = {}

local function deepcopy(v)
	if type(v) ~= "table" then return v end
	local out = {}
	for k, x in pairs(v) do out[deepcopy(k)] = deepcopy(x) end
	return setmetatable(out, getmetatable(v))
end

local function find(t, id, depth)
	if type(t) ~= "table" then return nil end
	depth = (depth or 0) + 1
	if depth > 12 then return nil end
	if t.id == id then return t end
	for _, c in ipairs(t.children or {}) do
		local r = find(c, id, depth)
		if r then return r end
	end
end

local function ring_place(button, index, total)
	local angle = math.rad(270 + (index - 1) * 360 / total)
	if type(button.pos) == "table" then
		button.pos.x = RING_CX + RING_RADIUS * math.cos(angle)
		button.pos.y = RING_CY + RING_RADIUS * math.sin(angle)
	end
end

-- Grows the Tower Room wheel to SLOTS buttons. Returns nil or an error message, plus the count
-- of buttons the template already had.
local function patch_wheel(t)
	local buttons, highest = {}, 0
	for _, c in ipairs(t.children or {}) do
		if type(c.id) == "string" then
			local n = tonumber(c.id:match("^button_tower_ring_sel_(%d%d)$"))
			if n then
				buttons[n] = c
				if n > highest then highest = n end
			end
		end
	end
	if not buttons[1] then return "ring buttons not found" end

	-- The clones are full copies, child ids included: in the stock template every button's child
	-- uses the same image_tower_icon_flash_01, so lookups are relative to the button.
	local proto = buttons[1]
	for i = 1, SLOTS do
		local b = buttons[i]
		if not b then
			b = deepcopy(proto)
			b.id = string.format("button_tower_ring_sel_%02i", i)
			t.children[#t.children + 1] = b
		end
		ring_place(b, i, SLOTS)
	end
	return nil, highest
end

function M.init(api)
	if SLOTS < 5 then error("SLOTS must be at least 5") end

	local log = api.log
	local log_lines = 0
	if FALLBACK_LOG and type(log) ~= "function" then
		local function fmtmsg(fmt, ...)
			if select("#", ...) == 0 then return tostring(fmt) end
			local ok, s = pcall(string.format, fmt, ...)
			return ok and s or tostring(fmt)
		end
		log = function(fmt, ...)
			local msg = fmtmsg(fmt, ...)
			pcall(function()
				if log_lines > 400 then return end
				log_lines = log_lines + 1
				local prev = ""
				if love.filesystem.getInfo and love.filesystem.getInfo(LOGFILE) then
					prev = love.filesystem.read(LOGFILE) or ""
				end
				love.filesystem.write(LOGFILE, prev .. "[8towers] " .. msg .. "\n")
			end)
		end
	end
	if type(log) ~= "function" then log = function() end end

	-- Frames come from love.timer.getDelta rather than from the loader: a mod loader is not
	-- required to offer a frame hook, and this one is stable - the game swaps love.update and
	-- love.draw per scene, but getDelta is called from the run loop itself.
	local frames = {}
	local on_frame = function(fn)
		if type(fn) == "function" then frames[#frames + 1] = fn end
	end
	local ticks = 0
	local function pump()
		ticks = ticks + 1
		for i = 1, #frames do pcall(frames[i], ticks) end
	end
	local ok_pump = pcall(function()
		local orig = love.timer.getDelta
		if type(orig) ~= "function" then error("love.timer.getDelta unavailable") end
		love.timer.getDelta = function(...)
			pcall(pump)
			return orig(...)
		end
	end)
	if not ok_pump then
		if type(api.on_frame) == "function" then
			api.on_frame(pump)
		else
			log("no frame hook available, the mod will not work")
			return
		end
	end

	-- The saved team, and the ways to recognise it.
	local team = nil
	local function snapshot(list)
		local copy = {}
		for i, n in ipairs(list) do copy[i] = n end
		return copy
	end

	-- Modes with their own tower rules (Iron and friends) are left alone.
	local function mode_locks_towers()
		local game = package.loaded["game"]
		local store = type(game) == "table" and game.store
		if type(store) ~= "table" or type(store.level) ~= "table" then return false end
		local ov = type(store.level.data) == "table" and store.level.data.level_mode_overrides
		local ovm = type(ov) == "table" and ov[store.level_mode]
		return type(ovm) == "table" and type(ovm.available_towers) == "table"
	end

	-- 1. Raise the saved team size before the save is read.
	api.when_loaded("game_settings", function(GS)
		log("number_of_towers: %s -> %d", tostring(GS.number_of_towers), SLOTS)
		GS.number_of_towers = SLOTS
	end)

	-- 3a. Track the saved team. Read only - see the notes at the top.
	api.when_loaded("storage", function(storage)
		if storage._eight_towers_mod then return end
		storage._eight_towers_mod = true
		local game_load_slot = storage.load_slot
		storage.load_slot = function(self, ...)
			local slot = game_load_slot(self, ...)
			local d = rawget(_G, "director")
			if not (d and d.last_item_name == "game") then
				local sel = type(slot) == "table" and type(slot.towers) == "table" and slot.towers.selected
				if type(sel) == "table" and #sel > 0 then
					local changed = not team or #team ~= #sel
					if not changed then
						for i = 1, #sel do
							if team[i] ~= sel[i] then changed = true break end
						end
					end
					if changed then
						team = snapshot(sel)
						log("tower room team: %d selected (%s)", #team, table.concat(team, ", "))
					end
				end
			end
			return slot
		end
	end)

	-- 3b. Force the in-stage list back to the saved team.
	api.when_loaded("game", function(game)
		local last, firstlog = nil, false
		on_frame(function(tick)
			if tick % 15 ~= 0 then return end
			local store = game.store
			if type(store) ~= "table" or type(store.level) ~= "table" then return end
			if type(team) ~= "table" or #team == 0 then return end
			if mode_locks_towers() then return end

			local cur = store.selected_towers
			local same = type(cur) == "table" and #cur == #team
			if same then
				for i = 1, #cur do
					if cur[i] ~= team[i] then same = false break end
				end
			end
			if same then return end

			if not firstlog then
				firstlog = true
				local desc = type(cur) ~= "table" and tostring(cur)
					or string.format("%d towers [%s]", #cur, table.concat(cur, ", "))
				log("stage tower list was: %s", desc)
			end

			local copy = snapshot(team)
			store.selected_towers = copy
			local key = table.concat(copy, ",")
			if key ~= last then
				last = key
				log("in-stage tower list -> %d: %s", #copy, key)
			end
		end)
	end)

	-- 5. In-stage button positions: the first SLOTS entries on an even ring. Never shorten it.
	api.when_loaded("data.game_gui_data", function(gd)
		local places = gd.tower_menu_button_places
		if type(places) ~= "table" or #places < 1 then
			log("tower_menu_button_places not found, left as is")
			return
		end
		local original = {}
		for i = 1, #places do original[i] = places[i] end

		local built = {}
		for i = 1, math.max(#original, SLOTS) do
			if i <= SLOTS then
				local p = deepcopy(original[(i - 1) % #original + 1])
				local angle = math.rad(270 + (i - 1) * 360 / SLOTS)
				p.x = HUD_CX + HUD_RADIUS * math.cos(angle)
				p.y = HUD_CY + HUD_RADIUS * math.sin(angle)
				built[i] = p
			else
				built[i] = original[i]
			end
		end
		gd.tower_menu_button_places = built
		log("tower_menu_button_places: %d entries -> %d (first %d on an even ring)",
			#original, #built, SLOTS)
	end)

	-- 2. The Tower Room wheel. get_table hands out a fresh copy every call.
	api.when_loaded("klove.kui_db", function(kui_db)
		if kui_db._eight_towers_mod then return end
		kui_db._eight_towers_mod = true
		local reported = false
		local game_get_table = kui_db.get_table
		kui_db.get_table = function(self, name, ...)
			local t = game_get_table(self, name, ...)
			if name == "group_towers_wheel" and type(t) == "table" then
				local ok, err, highest = pcall(patch_wheel, t)
				if not reported then
					reported = true
					if not ok then
						log("group_towers_wheel failed: %s", tostring(err))
					elseif err then
						log("group_towers_wheel not patched: %s", tostring(err))
					else
						log("group_towers_wheel: %d buttons -> %d", highest, SLOTS)
					end
				end
			end
			return t
		end
		log("hooked kui_db.get_table")
	end)

	-- 4. Take over get_tower_menu_items. It is a local of TowerMenu.show, so the class has to be
	-- reached through a live tower_menu view, which only exists while a stage is running.
	local hooked_class, hooked_gtmi = nil, nil

	local function restamp(items)
		if type(team) ~= "table" or #team == 0 then return 0 end
		-- An upgrade menu is a handful of entries; the build list is all 19. Only touch that one.
		if #items < 8 then return 0 end
		local want = {}
		for i, n in ipairs(team) do want[n] = i end
		local changed = 0
		for _, it in ipairs(items) do
			if type(it) == "table" then
				local key = it.type or it.preview
				local w = key and want[key] or nil
				if w and it.place ~= w then
					it.place = w
					changed = changed + 1
				end
			end
		end
		return changed
	end

	local function hook_menu_builder()
		local d = rawget(_G, "director")
		if not d or d.last_item_name ~= "game" then return end
		local gg = package.loaded["game_gui"]
		local root = gg and gg.window
		if type(root) ~= "table" then return end
		local node = find(root, "tower_menu", 0)
		if type(node) ~= "table" then return end
		local cls = node.class
		if type(cls) ~= "table" or cls == hooked_class then return end

		local show = type(cls.__declaredMethods) == "table" and cls.__declaredMethods.show
		if type(show) ~= "function" then return end
		local upname, gtmi = debug.getupvalue(show, 2)
		if upname ~= "get_tower_menu_items" or type(gtmi) ~= "function" then
			log("TowerMenu.show upvalue 2 is %s, not get_tower_menu_items", tostring(upname))
			hooked_class = cls
			return
		end
		if gtmi == hooked_gtmi then
			hooked_class = cls
			return
		end

		local wrapper = function(entity)
			local items = gtmi(entity)
			if type(items) == "table" and not mode_locks_towers() then
				local n = restamp(items)
				if n > 0 and #team > 5 then
					log("build menu: stamped place on %d entries (%d selected)", n, #team)
				end
			end
			return items
		end
		debug.setupvalue(show, 2, wrapper)
		hooked_class = cls
		hooked_gtmi = gtmi
		log("hooked get_tower_menu_items")
	end

	-- The view only exists once a stage is running, and the class can differ per stage, so this is
	-- retried: every 30 frames until it lands, then every 300 as a safety net.
	local probe = 0
	on_frame(function()
		probe = probe + 1
		local step = hooked_class and 300 or 30
		if probe % step ~= 0 then return end
		pcall(hook_menu_builder)
	end)
end

return M
