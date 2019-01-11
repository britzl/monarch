local callback_tracker = require "monarch.utils.callback_tracker"

local M = {}

local CONTEXT = hash("monarch_context")
local PROXY_LOADED = hash("proxy_loaded")
local PROXY_UNLOADED = hash("proxy_unloaded")

local RELEASE_INPUT_FOCUS = hash("release_input_focus")
local ACQUIRE_INPUT_FOCUS = hash("acquire_input_focus")
local ASYNC_LOAD = hash("async_load")
local UNLOAD = hash("unload")
local ENABLE = hash("enable")
local DISABLE = hash("disable")

-- transition messages
M.TRANSITION = {}
M.TRANSITION.DONE = hash("transition_done")
M.TRANSITION.SHOW_IN = hash("transition_show_in")
M.TRANSITION.SHOW_OUT = hash("transition_show_out")
M.TRANSITION.BACK_IN = hash("transition_back_in")
M.TRANSITION.BACK_OUT = hash("transition_back_out")

-- focus messages
M.FOCUS = {}
M.FOCUS.GAINED = hash("monarch_focus_gained")
M.FOCUS.LOST = hash("monarch_focus_lost")

-- listener messages
M.SCREEN_TRANSITION_IN_STARTED = hash("monarch_screen_transition_in_started")
M.SCREEN_TRANSITION_IN_FINISHED = hash("monarch_screen_transition_in_finished")
M.SCREEN_TRANSITION_OUT_STARTED = hash("monarch_screen_transition_out_started")
M.SCREEN_TRANSITION_OUT_FINISHED = hash("monarch_screen_transition_out_finished")


-- all registered screens
local screens = {}

-- the current stack of screens
local stack = {}

-- navigation listeners
local listeners = {}

-- the number of active transitions
-- monarch is considered busy while there are active transitions
local active_transition_count = 0


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

local function notify_listeners(message_id, message)
	log("notify_listeners()", message_id)
	for _,url in pairs(listeners) do
		msg.post(url, message_id, message or {})
	end
end

local function screen_from_proxy(proxy)
	for _,screen in pairs(screens) do
		if screen.proxy == proxy then
			return screen
		end
	end
end

local function screen_from_script()
	local url = msg.url()
	for _,screen in pairs(screens) do
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


--- Check if a screen is visible
-- @param id (string|hash)
-- @return true if the screen is visible
function M.is_visible(id)
	assert(id, "You must provide a screen id")
	id = tohash(id)
	assert(screens[id], ("There is no screen registered with id %s"):format(tostring(id)))
	return screens[id].loaded
end


local function register(id, settings)
	assert(id, "You must provide a screen id")
	id = tohash(id)
	assert(not screens[id], ("There is already a screen registered with id %s"):format(tostring(id)))
	screens[id] = {
		id = id,
		script = msg.url(),
		popup = settings and settings.popup,
		popup_on_popup = settings and settings.popup_on_popup,
		timestep_below_popup = settings and settings.timestep_below_popup or 1,
	}
	return screens[id]
end

--- Register a new screen contained in a collection proxy
-- This is done automatically by the screen_proxy.script. It is expected that
-- the caller of this function is a script component attached to the same game
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
--		* timestep_below_popup - Timestep to set on proxy when below a popup
--		* auto_preload - true if the screen should be automatically preloaded
function M.register_proxy(id, proxy, settings)
	assert(proxy, "You must provide a collection proxy URL")
	local screen = register(id, settings)
	screen.proxy = proxy
	screen.transition_url = settings and settings.transition_url
	screen.focus_url = settings and settings.focus_url
	screen.auto_preload = settings and settings.auto_preload
	if screen.auto_preload then
		M.preload(id)
	end
end
M.register = M.register_proxy


--- Register a new screen contained in a collection factory
-- This is done automatically by the screen_factory.script. It is expected that
-- the caller of this function is a script component attached to the same game
-- object as the factory. This is required since monarch will acquire and
-- release input focus of the game object where the factory is attached.
-- @param id Unique id of the screen
-- @param factory URL to the collection factory containing the screen
-- @param settings Settings table for screen. Accepted values:
-- 		* popup - true the screen is a popup
--		* popup_on_popup - true if this popup can be shown on top of
--		  another popup or false if an underlying popup should be closed
-- 		* transition_id - Id of the game object in the collection that is responsible
--		  for the screen transitions
-- 		* focus_id - Id of the game object in the collection that is to be notified
--		  of focus lost/gained events
--		* auto_preload - true if the screen should be automatically preloaded
function M.register_factory(id, factory, settings)
	assert(factory, "You must provide a collection factory URL")
	local screen = register(id, settings)
	screen.factory = factory
	screen.transition_id = settings and settings.transition_id
	screen.focus_id = settings and settings.focus_id
	screen.auto_preload = settings and settings.auto_preload
	if screen.auto_preload then
		M.preload(id)
	end
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
		if screen.proxy then
			msg.post(screen.script, ACQUIRE_INPUT_FOCUS)
		elseif screen.factory then
			for id,instance in pairs(screen.factory_ids) do
				msg.post(instance, ACQUIRE_INPUT_FOCUS)
			end
		end
		screen.input = true
	end
end

local function release_input(screen)
	log("change_context()", screen.id)
	if screen.input then
		if screen.proxy then
			msg.post(screen.script, RELEASE_INPUT_FOCUS)
		elseif screen.factory then
			for id,instance in pairs(screen.factory_ids) do
				msg.post(instance, RELEASE_INPUT_FOCUS)
			end
		end
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

	if screen.proxy then
		if screen.auto_preload then
			msg.post(screen.proxy, DISABLE)
			screen.loaded = false
			screen.preloaded = true
		else
			screen.wait_for = PROXY_UNLOADED
			msg.post(screen.proxy, UNLOAD)
			coroutine.yield()
			screen.loaded = false
			screen.preloaded = false
			screen.wait_for = nil
		end
	elseif screen.factory then
		for id, instance in pairs(screen.factory_ids) do
			go.delete(instance)
		end
		screen.factory_ids = nil
		if screen.auto_preload then
			screen.loaded = false
			screen.preloaded = true
		else
			collectionfactory.unload(screen.factory)
			screen.loaded = false
			screen.preloaded = false
		end
	end
end


local function preload(screen)
	log("preload() preloading screen", screen.id)
	assert(screen.co, "You must assign a coroutine to the screen")

	if screen.preloaded then
		log("preload() screen already preloaded", screen.id)
		return
	end

	if screen.proxy then
		screen.wait_for = PROXY_LOADED
		msg.post(screen.proxy, ASYNC_LOAD)
		coroutine.yield()
	elseif screen.factory then
		if collectionfactory.get_status(screen.factory) == collectionfactory.STATUS_UNLOADED then
			collectionfactory.load(screen.factory, function(self, url, result)
				assert(coroutine.resume(screen.co))
			end)
			coroutine.yield()
		end

		if collectionfactory.get_status(screen.factory) ~= collectionfactory.STATUS_LOADED then
			log("preload() error loading factory resources")
			return
		end
	end
	screen.preloaded = true
end

local function load(screen)
	log("load()", screen.id)
	assert(screen.co, "You must assign a coroutine to the screen")

	if screen.loaded then
		log("load() screen already loaded", screen.id)
		return
	end

	preload(screen)

	if not screen.preloaded then
		log("load() screen wasn't preloaded", screen.id)
		return
	end

	if screen.proxy then
		msg.post(screen.proxy, ENABLE)
	elseif screen.factory then
		screen.factory_ids = collectionfactory.create(screen.factory)
		screen.transition_url = screen.factory_ids[screen.transition_id]
		screen.focus_url = screen.factory_ids[screen.focus_id]
	end
	screen.loaded = true
	screen.preloaded = false
end

local function transition(screen, message_id, message)
	log("transition()", screen.id)
	if screen.transition_url then
		screen.wait_for = M.TRANSITION.DONE
		msg.post(screen.transition_url, message_id, message)
		coroutine.yield()
		screen.wait_for = nil
	else
		log("transition() no transition url - ignoring")
	end
end

local function focus_gained(screen, previous_screen)
	log("focus_gained()", screen.id)
	if screen.focus_url then
		msg.post(screen.focus_url, M.FOCUS.GAINED, { id = previous_screen and previous_screen.id })
	else
		log("focus_gained() no focus url - ignoring")
	end
end

local function focus_lost(screen, next_screen)
	log("focus_lost()", screen.id)
	if screen.focus_url then
		msg.post(screen.focus_url, M.FOCUS.LOST, { id = next_screen and next_screen.id })
	else
		log("focus_lost() no focus url - ignoring")
	end
end

local function change_timestep(screen)
	if screen.proxy then
		screen.changed_timestep = true
		msg.post(screen.proxy, "set_time_step", { mode = 0, factor = screen.timestep_below_popup })
	end
end

local function reset_timestep(screen)
	if screen.proxy and screen.changed_timestep then
		msg.post(screen.proxy, "set_time_step", { mode = 0, factor = 1 })
		screen.changed_timestep = false
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
		if next_screen and next_screen.popup then
			change_timestep(screen)
		else
			reset_timestep(screen)
		end
		screen.co = nil
		if cb then cb() end
	end)
	assert(coroutine.resume(co))
end

local function enable(screen, previous_screen)
	log("enable()", screen.id)
	local co
	co = coroutine.create(function()
		screen.co = co
		change_context(screen)
		acquire_input(screen)
		focus_gained(screen, previous_screen)
		reset_timestep(screen)
		screen.co = nil
		if cb then cb() end
	end)
	assert(coroutine.resume(co))
end

local function show_out(screen, next_screen, cb)
	log("show_out()", screen.id)
	local co
	co = coroutine.create(function()
		active_transition_count = active_transition_count + 1
		notify_listeners(M.SCREEN_TRANSITION_OUT_STARTED, { screen = screen.id, next_screen = next_screen.id })
		screen.co = co
		change_context(screen)
		release_input(screen)
		focus_lost(screen, next_screen)
		reset_timestep(screen)
		-- if the next screen is a popup we want the current screen to stay visible below the popup
		-- if the next screen isn't a popup the current one should be unloaded and transitioned out
		local next_is_popup = next_screen and next_screen.popup
		local current_is_popup = screen.popup
		if (not next_is_popup and not current_is_popup) or (current_is_popup) then
			transition(screen, M.TRANSITION.SHOW_OUT, { next_screen = next_screen.id })
			unload(screen)
		elseif next_is_popup then
			change_timestep(screen)
		end
		screen.co = nil
		active_transition_count = active_transition_count - 1
		if cb then cb() end
		notify_listeners(M.SCREEN_TRANSITION_OUT_FINISHED, { screen = screen.id, next_screen = next_screen.id })
	end)
	coroutine.resume(co)
end

local function show_in(screen, previous_screen, reload, cb)
	log("show_in()", screen.id)
	local co
	co = coroutine.create(function()
		active_transition_count = active_transition_count + 1
		notify_listeners(M.SCREEN_TRANSITION_IN_STARTED, { screen = screen.id, previous_screen = previous_screen and previous_screen.id })
		screen.co = co
		change_context(screen)
		if reload and screen.loaded then
			log("show_in() reloading", screen.id)
			unload(screen)
		end
		load(screen)
		stack[#stack + 1] = screen
		reset_timestep(screen)
		transition(screen, M.TRANSITION.SHOW_IN, { previous_screen = previous_screen and previous_screen.id })
		acquire_input(screen)
		focus_gained(screen, previous_screen)
		screen.co = nil
		active_transition_count = active_transition_count - 1
		if cb then cb() end
		notify_listeners(M.SCREEN_TRANSITION_IN_FINISHED, { screen = screen.id, previous_screen = previous_screen and previous_screen.id })
	end)
	coroutine.resume(co)
end

local function back_in(screen, previous_screen, cb)
	log("back_in()", screen.id)
	local co
	co = coroutine.create(function()
		active_transition_count = active_transition_count + 1
		notify_listeners(M.SCREEN_TRANSITION_IN_STARTED, { screen = screen.id, previous_screen = previous_screen and previous_screen.id })
		screen.co = co
		change_context(screen)
		load(screen)
		reset_timestep(screen)
		if previous_screen and not previous_screen.popup then
			transition(screen, M.TRANSITION.BACK_IN, { previous_screen = previous_screen.id })
		end
		acquire_input(screen)
		focus_gained(screen, previous_screen)
		screen.co = nil
		active_transition_count = active_transition_count - 1
		if cb then cb() end
		notify_listeners(M.SCREEN_TRANSITION_IN_FINISHED, { screen = screen.id, previous_screen = previous_screen and previous_screen.id })
	end)
	coroutine.resume(co)
end

local function back_out(screen, next_screen, cb)
	log("back_out()", screen.id)
	local co
	co = coroutine.create(function()
		notify_listeners(M.SCREEN_TRANSITION_OUT_STARTED, { screen = screen.id, next_screen = next_screen and next_screen.id })
		active_transition_count = active_transition_count + 1
		screen.co = co
		change_context(screen)
		release_input(screen)
		focus_lost(screen, next_screen)
		if next_screen and screen.popup then
			reset_timestep(next_screen)
		end
		transition(screen, M.TRANSITION.BACK_OUT, { next_screen = next_screen and next_screen.id })
		unload(screen)
		screen.co = nil
		active_transition_count = active_transition_count - 1
		if cb then cb() end
		notify_listeners(M.SCREEN_TRANSITION_OUT_FINISHED, { screen = screen.id, next_screen = next_screen and next_screen.id })
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


--- Check if Monarch is busy hiding and or showing a screen
-- @return true if busy
function M.is_busy()
	return active_transition_count > 0
end


--- Show a new screen
-- @param id (string|hash) - Id of the screen to show
-- @param options (table) - Table with options when showing the screen (can be nil). Valid values:
-- 		* clear - Set to true if the stack should be cleared down to an existing instance of the screen
-- 		* reload - Set to true if screen should be reloaded if it already exists in the stack and is loaded.
--				   This would be the case if doing a show() from a popup on the screen just below the popup.
-- @param data (*) - Optional data to set on the screen. Can be retrieved by the data() function
-- @param cb (function) - Optional callback to invoke when screen is shown
-- @return success True if screen is successfully shown, false if busy performing another operation
function M.show(id, options, data, cb)
	assert(id, "You must provide a screen id")
	if M.is_busy() then
		log("show() monarch is busy, ignoring request")
		return false
	end

	local callbacks = callback_tracker()

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
				show_out(top, screen, callbacks.track())
				top = stack[#stack]
			end
			-- unload and transition out from top
			-- unless we're showing the same screen as is already visible
			if top and top.id ~= screen.id then
				show_out(top, screen, callbacks.track())
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
	show_in(screen, top, options and options.reload, callbacks.track())

	if cb then callbacks.when_done(cb) end

	return true
end


-- Go back to the previous screen in the stack
-- @param data (*) - Optional data to set for the previous screen
-- @param cb (function) - Optional callback to invoke when the previous screen is visible again
-- @return true if successfully going back, false if busy performing another operation
function M.back(data, cb)
	if M.is_busy() then
		log("back() monarch is busy, ignoring request")
		return false
	end

	local callbacks = callback_tracker()

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
				back_in(top, screen, callbacks.track())
			end)
		else
			back_out(screen, top)
			if top then
				if data then
					top.data = data
				end
				back_in(top, screen, callbacks.track())
			end
		end
	end

	if cb then callbacks.when_done(cb) end

	return true
end


--- Preload a screen. This will load but not enable and show a screen. Useful for "heavier" screens
-- that you wish to show without any delay.
-- @param id (string|hash) - Id of the screen to preload
-- @param cb (function) - Optional callback to invoke when screen is loaded
function M.preload(id, cb)
	if M.is_busy() then
		log("preload() monarch is busy, ignoring request")
		return false
	end

	assert(id, "You must provide a screen id")
	id = tohash(id)
	assert(screens[id], ("There is no screen registered with id %s"):format(tostring(id)))

	local screen = screens[id]
	log("preload()", screen.id)
	if screen.preloaded or screen.loaded then
		if cb then cb() end
		return true
	end
	local co
	co = coroutine.create(function()
		screen.co = co
		change_context(screen)
		preload(screen)
		if cb then cb() end
	end)
	assert(coroutine.resume(co))
	return true
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


--- Get the screen on top of the stack
-- @param offset Optional offset from the top of the stack, (eg -1 for the previous screen)
-- @return Id of the requested screen
function M.top(offset)
	local screen = stack[#stack + (offset or 0)]
	return screen and screen.id
end


--- Get the screen at the bottom of the stack
-- @param offset Optional offset from the bottom of the stack
-- @return Id of the requested screen
function M.bottom(offset)
	local screen = stack[1 + (offset or 0)]
	return screen and screen.id
end

local function url_to_key(url)
	return (url.socket or hash("")) .. (url.path or hash("")) .. (url.fragment or hash(""))
end


--- Add a listener to be notified of when screens are shown or hidden
-- @param url The url to notify, nil for current url
function M.add_listener(url)
	url = url or msg.url()
	listeners[url_to_key(url)] = url
end


--- Remove a previously added listener
-- @param url The url to remove, nil for current url
function M.remove_listener(url)
	url = url or msg.url()
	listeners[url_to_key(url)] = nil
end


function M.dump_stack()
	local s = ""
	for i, screen in ipairs(stack) do
		s = s .. ("%d = %s\n"):format(i, tostring(screen.id))
	end
	return s
end

return M
