local M = {}

local screens = {}

local stack = {}

local CONTEXT = hash("monarch_context")
local PROXY_LOADED = hash("proxy_loaded")
local PROXY_UNLOADED = hash("proxy_unloaded")

local RELEASE_INPUT_FOCUS = hash("release_input_focus")
local ACQUIRE_INPUT_FOCUS = hash("acquire_input_focus")
local ASYNC_LOAD = hash("async_load")
local UNLOAD = hash("unload")
local ENABLE = hash("enable")

M.TRANSITION = {}
M.TRANSITION.DONE = hash("transition_done")
M.TRANSITION.SHOW_IN = hash("transition_show_in")
M.TRANSITION.SHOW_OUT = hash("transition_show_out")
M.TRANSITION.BACK_IN = hash("transition_back_in")
M.TRANSITION.BACK_OUT = hash("transition_back_out")

M.FOCUS = {}
M.FOCUS.GAINED = hash("monarch_focus_gained")
M.FOCUS.LOST = hash("monarch_focus_lost")


local function log(...) end

function M.debug()
	log = print
end

-- use a lookup table for so we don't have to do "return (type(s) == "string" and hash(s) or s)"
-- every time
local hash_lookup = {}
local function tohash(s)
	hash_lookup[s] = hash_lookup[s] or (type(s) == "string" and hash(s) or s)
	return hash_lookup[s]
end


local function screen_from_proxy(proxy)
	for _, screen in pairs(screens) do
		if screen.proxy == proxy then
			return screen
		end
	end
end

local function screen_from_script()
	local url = msg.url()
	for _, screen in pairs(screens) do
		if screen.script == url then
			return screen
		end
	end
end


--- Check if a screen exists in the current screen stack
-- @param id (string|hash)
-- @return true of the screen is in the stack
function M.in_stack(id)
	assert(id, "You must provide a screen id")
	id = tohash(id)
	for i = 1, #stack do
		if stack[i].id == id then
			return true
		end
	end
	return false
end


--- Check if a screen is at the top of the stack
-- (primarily used for unit tests, but could have a usecase outside tests)
-- @param id (string|hash)
-- @return true if the screen is at the top of the stack
function M.is_top(id)
	assert(id, "You must provide a screen id")
	id = tohash(id)
	local top = stack[#stack]
	return top and top.id == id or false
end


--- Register a new screen
-- This is done automatically by the screen.script. It is expected that the
-- caller of this function is a script component attached to the same game
-- object as the proxy. This is required since monarch will acquire and
-- release input focus of the game object where the proxy is attached.
-- @param id Unique id of the screen
-- @param proxy URL to the collection proxy containing the screen
-- @param settings Settings table for screen. Accepted values:
-- 		* popup - true the screen is a popup
--		* popup_on_popup - true if this popup can be shown on top of
--		  another popup or false if an underlying popup should be closed
-- 		* transition_url - URL to a script that is responsible for the
--		  screen transitions
-- 		* focus_url - URL to a script that is to be notified of focus
--		  lost/gained events
function M.register(id, proxy, settings)
	assert(id, "You must provide a screen id")
	id = tohash(id)
	assert(not screens[id], ("There is already a screen registered with id %s"):format(tostring(id)))
	assert(proxy, "You must provide a collection proxy URL")
	local url = msg.url(proxy)
	screens[id] = {
		id = id,
		proxy = proxy,
		script = msg.url(),
		popup = settings and settings.popup,
		popup_on_popup = settings and settings.popup_on_popup,
		transition_url = settings and settings.transition_url,
		focus_url = settings and settings.focus_url,
	}
end

--- Unregister a screen
-- This is done automatically by the screen.script
-- @param id Id of the screen to unregister
function M.unregister(id)
	assert(id, "You must provide a screen id")
	id = tohash(id)
	assert(screens[id], ("There is no screen registered with id %s"):format(tostring(id)))
	screens[id] = nil
end

local function acquire_input(screen)
	log("change_context()", screen.id)
	if not screen.input then
		msg.post(screen.script, ACQUIRE_INPUT_FOCUS)
		screen.input = true
	end
end

local function release_input(screen)
	log("change_context()", screen.id)
	if screen.input then
		msg.post(screen.script, RELEASE_INPUT_FOCUS)
		screen.input = false
	end
end

local function change_context(screen)
	log("change_context()", screen.id)
	screen.wait_for = CONTEXT
	msg.post(screen.script, CONTEXT)
	coroutine.yield()
	screen.wait_for = nil
end

local function unload(screen)
	log("unload()", screen.id)
	screen.wait_for = PROXY_UNLOADED
	msg.post(screen.proxy, UNLOAD)
	coroutine.yield()
	screen.loaded = false
	screen.wait_for = nil
end

local function async_load(screen)
	log("async_load()", screen.id)
	screen.wait_for = PROXY_LOADED
	msg.post(screen.proxy, ASYNC_LOAD)
	coroutine.yield()
	msg.post(screen.proxy, ENABLE)
	screen.loaded = true
	screen.wait_for = nil
end

local function transition(screen, message_id)
	log("transition()", screen.id)
	screen.wait_for = M.TRANSITION.DONE
	msg.post(screen.transition_url, message_id)
	coroutine.yield()
	screen.wait_for = nil
end

local function focus_gained(screen, previous_screen)
	log("focus_gained()", screen.id)
	if screen.focus_url then
		msg.post(screen.focus_url, M.FOCUS.GAINED, {id = previous_screen and previous_screen.id})
	end
end

local function focus_lost(screen, next_screen)
	log("focus_lost()", screen.id)
	if screen.focus_url then
		msg.post(screen.focus_url, M.FOCUS.LOST, {id = next_screen and next_screen.id})
	end
end

local function disable(screen, next_screen)
	log("disable()", screen.id)
	local co
	co = coroutine.create(function()
		screen.co = co
		change_context(screen)
		release_input(screen)
		focus_lost(screen, next_screen)
		screen.co = nil
		if cb then cb() end
	end)
	coroutine.resume(co)
end

local function enable(screen, previous_screen)
	log("enable()", screen.id)
	local co
	co = coroutine.create(function()
		screen.co = co
		change_context(screen)
		acquire_input(screen)
		focus_gained(screen, previous_screen)
		screen.co = nil
		if cb then cb() end
	end)
	coroutine.resume(co)
end

local function show_out(screen, next_screen, cb)
	log("show_out()", screen.id)
	local co
	co = coroutine.create(function()
		screen.co = co
		change_context(screen)
		release_input(screen)
		focus_lost(screen, next_screen)
		-- if the next screen is a popup we want the current screen to stay visible below the popup
		-- if the next screen isn't a popup the current one should be unloaded and transitioned out
		local next_is_popup = next_screen and not next_screen.popup
		local current_is_popup = screen.popup
		if (next_is_popup and not current_is_popup) or (current_is_popup) then
			transition(screen, M.TRANSITION.SHOW_OUT)
			unload(screen)
		end
		screen.co = nil
		if cb then cb() end
	end)
	coroutine.resume(co)
end

local function show_in(screen, previous_screen, reload, cb)
	log("show_in()", screen.id)
	local co
	co = coroutine.create(function()
		screen.co = co
		change_context(screen)
		if reload and screen.loaded then
			log("show_in() reloading", screen.id)
			unload(screen)
		end
		-- if the screen has been preloaded we need to enable it
		if screen.preloaded then
			log("show_in() screen was preloaded", screen.id)
			msg.post(screen.proxy, ENABLE)
			screen.loaded = true
			screen.preloaded = false
		-- the screen could be loaded if the previous screen was a popup
		-- and the popup asked to show this screen again
		-- in that case we shouldn't attempt to load it again
		elseif not screen.loaded then
			log("show_in() loading screen", screen.id)
			async_load(screen)
		end
		stack[#stack + 1] = screen
		transition(screen, M.TRANSITION.SHOW_IN)
		acquire_input(screen)
		focus_gained(screen, previous_screen)
		screen.co = nil
		if cb then cb() end
	end)
	coroutine.resume(co)
end

local function back_in(screen, previous_screen, cb)
	log("back_in()", screen.id)
	local co
	co = coroutine.create(function()
		screen.co = co
		change_context(screen)
		if screen.preloaded then
			log("back_in() screen was preloaded", screen.id)
			msg.post(screen.proxy, ENABLE)
			screen.preloaded = false
			screen.loaded = true
		elseif not screen.loaded then
			log("back_in() loading screen", screen.id)
			async_load(screen)
		end
		if previous_screen and not previous_screen.popup then
			transition(screen, M.TRANSITION.BACK_IN)
		end
		acquire_input(screen)
		focus_gained(screen, previous_screen)
		screen.co = nil
		if cb then cb() end
	end)
	coroutine.resume(co)
end

local function back_out(screen, next_screen, cb)
	log("back_out()", screen.id)
	local co
	co = coroutine.create(function()
		screen.co = co
		change_context(screen)
		release_input(screen)
		focus_lost(screen, next_screen)
		transition(screen, M.TRANSITION.BACK_OUT)
		unload(screen)
		screen.co = nil
		if cb then cb() end
	end)
	coroutine.resume(co)
end


--- Get data associated with a screen
-- @param id (string|hash) Id of the screen to get data for
-- @return Data associated with the screen
function M.data(id)
	assert(id, "You must provide a screen id")
	id = tohash(id)
	assert(screens[id], ("There is no screen registered with id %s"):format(tostring(id)))
	return screens[id].data
end

--- Checks to see if a screen id is registered
-- @param id (string|hash) Id of the screen to check if is registered
-- @return True or False if the screen id is registered or not
function M.screen_exists(id)
	assert(id, "You must provide a screen id")
	id = tohash(id)
	return screens[id] ~= nil
end

--- Show a new screen
-- @param id (string|hash) - Id of the screen to show
-- @param options (table) - Table with options when showing the screen (can be nil). Valid values:
-- 		* clear - Set to true if the stack should be cleared down to an existing instance of the screen
-- 		* reload - Set to true if screen should be reloaded if it already exists in the stack and is loaded.
--				  This would be the case if doing a show() from a popup on the screen just below the popup.
-- @param data (*) - Optional data to set on the screen. Can be retrieved by the data() function
-- @param cb (function) - Optional callback to invoke when screen is shown
function M.show(id, options, data, cb)
	assert(id, "You must provide a screen id")
	id = tohash(id)
	assert(screens[id], ("There is no screen registered with id %s"):format(tostring(id)))

	local screen = screens[id]
	screen.data = data

	log("show()", screen.id)

	-- manipulate the current top
	-- close popup if needed
	-- transition out
	local top = stack[#stack]
	if top then
		-- keep top popup visible if new screen can be shown on top of a popup
		if top.popup and screen.popup_on_popup then
			disable(top, screen)
		else
			-- close all popups
			while top.popup do
				stack[#stack] = nil
				show_out(top, screen)
				top = stack[#stack]
			end
			-- unload and transition out from top
			-- unless we're showing the same screen as is already visible
			if top and top.id ~= screen.id then
				show_out(top, screen)
			end
		end
	end

	-- if the screen we want to show is in the stack
	-- already and the clear flag is set then we need
	-- to remove every screen on the stack up until and
	-- including the screen itself
	if options and options.clear then
		log("show() clearing")
		while M.in_stack(id) do
			table.remove(stack)
		end
	end

	-- show screen
	show_in(screen, top, options and options.reload, cb)
end


-- Go back to the previous screen in the stack
-- @param data (*) - Optional data to set for the previous screen
-- @param cb (function) - Optional callback to invoke when the previous screen is visible again
function M.back(data, cb)
	local screen = table.remove(stack)
	if screen then
		log("back()", screen.id)
		local top = stack[#stack]
		-- if we go back to the same screen we need to first hide it
		-- and wait until it is hidden before we show it again
		if top and screen.id == top.id then
			back_out(screen, top, function()
				if data then
					top.data = data
				end
				back_in(top, screen, cb)
			end)
		else
			back_out(screen, top)
			if top then
				if data then
					top.data = data
				end
				back_in(top, screen, cb)
			end
		end
	elseif cb then
		cb()
	end
end

--- Preload a screen. This will load but not enable and show a screen. Useful for "heavier" screens
-- that you wish to show without any delay.
-- @param id (string|hash) - Id of the screen to preload
-- @param cb (function) - Optional callback to invoke when screen is loaded
function M.preload(id, cb)
	assert(id, "You must provide a screen id")
	id = tohash(id)
	assert(screens[id], ("There is no screen registered with id %s"):format(tostring(id)))

	local screen = screens[id]
	local co
	co = coroutine.create(function()
		screen.co = co
		change_context(screen)
		screen.wait_for = PROXY_LOADED
		msg.post(screen.proxy, ASYNC_LOAD)
		coroutine.yield()
		screen.preloaded = true
		screen.wait_for = nil
		if cb then cb() end
	end)
	coroutine.resume(co)
end


function M.on_message(message_id, message, sender)
	if message_id == PROXY_LOADED then
		local screen = screen_from_proxy(sender)
		assert(screen, "Unable to find screen for loaded proxy")
		if screen.wait_for == PROXY_LOADED then
			assert(coroutine.resume(screen.co))
		end
	elseif message_id == PROXY_UNLOADED then
		local screen = screen_from_proxy(sender)
		assert(screen, "Unable to find screen for unloaded proxy")
		if screen.wait_for == PROXY_UNLOADED then
			assert(coroutine.resume(screen.co))
		end
	elseif message_id == CONTEXT then
		local screen = screen_from_script()
		assert(screen, "Unable to find screen for current script url")
		if screen.wait_for == CONTEXT then
			assert(coroutine.resume(screen.co))
		end
	elseif message_id == M.TRANSITION.DONE then
		local screen = screen_from_script()
		assert(screen, "Unable to find screen for current script url")
		if screen.wait_for == M.TRANSITION.DONE then
			assert(coroutine.resume(screen.co))
		end
	end
end

--- Get a list of ids for the current screen stack
-- (primarily used for unit testing, but could have uses outside testing)
-- @return Table with screen ids. First entry is at the bottom of the
-- stack and the last value is at the top (and currently visible)
function M.get_stack()
	local s = {}
	for k,v in pairs(stack) do
		s[k] = v.id
	end
	return s
end

function M.dump_stack()
	local s = ""
	for i, screen in ipairs(stack) do
		s = s .. ("%d = %s\n"):format(i, tostring(screen.id))
	end
	return s
end

return M
