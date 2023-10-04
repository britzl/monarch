local callback_tracker = require "monarch.utils.callback_tracker"
local async = require "monarch.utils.async"

local M = {}

local WAITFOR_COWAIT = hash("waitfor_cowait")
local WAITFOR_CONTEXT = hash("waitfor_monarch_context")
local WAITFOR_PROXY_LOADED = hash("waitfor_proxy_loaded")
local WAITFOR_PROXY_UNLOADED = hash("waitfor_proxy_unloaded")
local WAITFOR_TRANSITION_DONE = hash("waitfor_transition_done")

local MSG_CONTEXT = hash("monarch_context")
local MSG_PROXY_LOADED = hash("proxy_loaded")
local MSG_PROXY_UNLOADED = hash("proxy_unloaded")
local MSG_LAYOUT_CHANGED = hash("layout_changed")
local MSG_RELEASE_INPUT_FOCUS = hash("release_input_focus")
local MSG_ACQUIRE_INPUT_FOCUS = hash("acquire_input_focus")
local MSG_ASYNC_LOAD = hash("async_load")
local MSG_UNLOAD = hash("unload")
local MSG_ENABLE = hash("enable")
local MSG_DISABLE = hash("disable")


local DEPRECATED = hash("__DEPRECATED__")

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
M.SCREEN_TRANSITION_FAILED = hash("monarch_screen_transition_failed")

local WAIT_FOR_TRANSITION = true
local DO_NOT_WAIT_FOR_TRANSITION = false

-- all registered screens
local screens = {}

-- the current stack of screens
local stack = {}

-- transition listeners
local transition_listeners = {}

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

local function pcallfn(fn, ...)
	if fn then
		local ok, err = pcall(fn, ...)
		if not ok then print(err) end
	end
end

local function assign(to, from)
	if not from then
		return to
	end
	for k, v in pairs(from) do
		to[k] = v
	end
	return to
end

local function cowait(screen, delay)
	log("cowait()", screen.id, delay)
	local co = coroutine.running()
	assert(co, "You must run this from within a coroutine")
	screen.wait_for = WAITFOR_COWAIT
	timer.delay(delay, false, function()
		screen.wait_for = nil
		assert(coroutine.resume(co))
	end)
	coroutine.yield()
end



local queue = {}

local function queue_error(message)
	log("queue() error - clearing queue")
	print(message)
	while next(queue) do
		table.remove(queue)
	end
end

local process_queue
process_queue = function()
	if M.is_busy() then
		log("queue() busy")
		return
	end
	local action = table.remove(queue, 1)
	if not action then
		log("queue() empty")
		return
	end
	log("queue() next action", action)
	local ok, err = pcall(action, process_queue, queue_error)
	if not ok then
		queue_error(err)
	end
end

local function queue_action(action)
	log("queue() adding", action)
	table.insert(queue, action)
	process_queue()
end


local function notify_transition_listeners(message_id, message)
	log("notify_transition_listeners()", message_id)
	for _,url in pairs(transition_listeners) do
		msg.post(url, message_id, message or {})
	end
end

local function find_screen(url_to_find)
	local function find(url)
		for _,screen in pairs(screens) do
			if screen.script == url or screen.proxy == url then
				return screen
			end
		end
	end
	return find(msg.url()) or find(url_to_find)
end

local function find_transition_screen(url_to_find)
	local function find(url)
		for _,screen in pairs(screens) do
			if screen.transition_url == url or screen.script == url or screen.proxy == url then
				return screen
			end
		end
	end
	return find(msg.url()) or find(url_to_find)
end

local function find_focus_screen(url_to_find)
	local function find(url)
		for _,screen in pairs(screens) do
			if screen.focus_url == url or screen.script == url or screen.proxy == url then
				return screen
			end
		end
	end
	return find(msg.url()) or find(url_to_find)
end

local function find_post_receiver_screen(url_to_find)
	local function find(url)
		for _,screen in pairs(screens) do
			if screen.receiver_url == url or screen.script == url or screen.proxy == url then
				return screen
			end
		end
	end
	return find(msg.url()) or find(url_to_find)
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
	return screens[id].visible
end


--- Check if a screen is a popup
-- @param id Screen id
-- @return true if the screen is a popup
function M.is_popup(id)
	assert(id, "You must provide a screen id")
	id = tohash(id)
	assert(screens[id], ("There is no screen registered with id %s"):format(tostring(id)))
	return screens[id].popup
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
		screen_keeps_input_focus_when_below_popup = settings and settings.screen_keeps_input_focus_when_below_popup or false,
		others_keep_input_focus_when_below_screen = settings and settings.others_keep_input_focus_when_below_screen or false,
		preload_listeners = {},
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
--		* timestep_below_popup - Timestep to set on proxy when below a popup
--		* screen_keeps_input_focus_when_below_popup - If this screen should
--		  keep input focus when below a popup
--		* others_keep_input_focus_when_below_screen - If screens below this
--		  screen should keep input focus
--		* auto_preload - true if the screen should be automatically preloaded
function M.register_proxy(id, proxy, settings)
	assert(proxy, "You must provide a collection proxy URL")
	local screen = register(id, settings)
	screen.proxy = proxy
	screen.transition_url = settings and settings.transition_url
	screen.focus_url = settings and settings.focus_url
	screen.receiver_url = settings and settings.receiver_url
	screen.auto_preload = settings and settings.auto_preload
	if screen.transition_url.fragment == DEPRECATED then
		screen.transition_url = nil
	end
	if screen.focus_url.fragment == DEPRECATED then
		screen.focus_url = nil
	end
	if screen.receiver_url.fragment == DEPRECATED then
		screen.receiver_url = nil
	end
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
--		* screen_keeps_input_focus_when_below_popup - If this screen should
--		  keep input focus when below a popup
--		* others_keep_input_focus_when_below_screen - If screens below this
--		  screen should keep input focus
--		* auto_preload - true if the screen should be automatically preloaded
function M.register_factory(id, factory, settings)
	assert(factory, "You must provide a collection factory URL")
	local screen = register(id, settings)
	screen.factory = factory
	screen.transition_id = settings and settings.transition_id
	screen.focus_id = settings and settings.focus_id
	screen.auto_preload = settings and settings.auto_preload

	if screen.transition_id == DEPRECATED then
		screen.transition_id = nil
	end
	if screen.focus_id == DEPRECATED then
		screen.focus_id = nil
	end
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
	log("unregister()", id)
	local screen = screens[id]
	screens[id] = nil
	-- remove screen from stack
	for i = #stack, 1, -1 do
		if stack[i].id == id then
			table.remove(stack, i)
		end
	end
	screen.unregistered = true
	if screen.wait_for then
		assert(coroutine.resume(screen.co))
	end
end

local function acquire_input(screen)
	log("acquire_input()", screen.id)
	if not screen.input then
		if screen.proxy then
			msg.post(screen.script, MSG_ACQUIRE_INPUT_FOCUS)
		elseif screen.factory then
			for id,instance in pairs(screen.factory_ids) do
				msg.post(instance, MSG_ACQUIRE_INPUT_FOCUS)
			end
		end
		screen.input = true
	end
end

local function release_input(screen, next_screen)
	log("release_input()", screen.id)
	if screen.input then
		local next_is_popup = next_screen and next_screen.popup

		local keep_if_next_is_popup = next_is_popup and screen.screen_keeps_input_focus_when_below_popup
		local keep_when_below_next = next_screen and next_screen.others_keep_input_focus_when_below_screen

		local release_focus = not keep_if_next_is_popup and not keep_when_below_next
		if release_focus then
			if screen.proxy then
				msg.post(screen.script, MSG_RELEASE_INPUT_FOCUS)
			elseif screen.factory then
				for id,instance in pairs(screen.factory_ids) do
					msg.post(instance, MSG_RELEASE_INPUT_FOCUS)
				end
			end
			screen.input = false
		end
	end
end

local function change_context(screen)
	log("change_context()", screen.id)
	screen.wait_for = WAITFOR_CONTEXT
	msg.post(screen.script, MSG_CONTEXT, { id = screen.id })
	coroutine.yield()
	screen.wait_for = nil
end

local function unload(screen, force)
	if screen.unregistered then return end
	if screen.proxy then
		log("unload() proxy", screen.id)
		if screen.auto_preload and not force then
			if screen.loaded then
				msg.post(screen.proxy, MSG_DISABLE)
				screen.loaded = false
			end
			screen.preloaded = true
		else
			screen.wait_for = WAITFOR_PROXY_UNLOADED
			msg.post(screen.proxy, MSG_UNLOAD)
			coroutine.yield()
			screen.loaded = false
			screen.preloaded = false
			screen.wait_for = nil
		end
	elseif screen.factory then
		log("unload() factory", screen.id)
		for id, instance in pairs(screen.factory_ids) do
			go.delete(instance)
		end
		screen.factory_ids = nil
		if screen.auto_preload and not force then
			screen.loaded = false
			screen.preloaded = true
		else
			collectionfactory.unload(screen.factory)
			screen.loaded = false
			screen.preloaded = false
		end
	end
	-- we need to wait here in case the unloaded screen contained any screens
	-- if this is the case we need to let these sub-screens have their final()
	-- functions called so that they have time to call unregister()
	cowait(screen, 0)
	cowait(screen, 0)
end


local function preload(screen)
	log("preload() preloading screen", screen.id)
	assert(screen.co, "You must assign a coroutine to the screen")

	if screen.preloaded then
		log("preload() screen already preloaded", screen.id)
		return true
	end

	screen.preloading = true
	if screen.proxy then
		log("preload() proxy")
		local missing_resources = collectionproxy.missing_resources(screen.proxy)
		if #missing_resources > 0 then
			local error_message = ("preload() collection proxy %s is missing resources"):format(tostring(screen.id))
			log(error_message)
			screen.preloading = false
			return false, error_message
		end
		screen.wait_for = WAITFOR_PROXY_LOADED
		msg.post(screen.proxy, MSG_ASYNC_LOAD)
		coroutine.yield()
		screen.wait_for = nil
		if screen.unregistered then
			return false, "Screen was unregistered while loading"
		end
	elseif screen.factory then
		log("preload() factory")
		if collectionfactory.get_status(screen.factory) == collectionfactory.STATUS_UNLOADED then
			collectionfactory.load(screen.factory, function(self, url, result)
				assert(coroutine.resume(screen.co))
			end)
			coroutine.yield()
			if screen.unregistered then
				return false, "Screen was unregistered while loading"
			end
		end

		if collectionfactory.get_status(screen.factory) ~= collectionfactory.STATUS_LOADED then
			local error_message = ("preload() error while loading factory resources for screen %s"):format(tostring(screen.id))
			log(error_message)
			screen.preloading = false
			return false, error_message
		end
	end
	log("preload() preloading done", screen.id)
	screen.preloaded = true
	screen.preloading = false
	return true
end

local function load(screen)
	log("load()", screen.id)
	assert(screen.co, "You must assign a coroutine to the screen")

	if screen.loaded then
		log("load() screen already loaded", screen.id)
		return true
	end

	local ok, err = preload(screen)
	if not ok then
		log("load() screen wasn't preloaded", screen.id)
		return false, err
	end

	if screen.proxy then
		msg.post(screen.proxy, MSG_ENABLE)
	elseif screen.factory then
		screen.factory_ids = collectionfactory.create(screen.factory)
		if screen.transition_id then
			screen.transition_url = screen.factory_ids[screen.transition_id]
		end
		screen.focus_url = screen.factory_ids[screen.focus_id]
	end
	screen.loaded = true
	screen.preloaded = false
	return true
end

local function transition(screen, message_id, message, wait)
	log("transition()", screen.id)
	if screen.unregistered then return end
	if screen.transition_url then
		screen.wait_for = WAITFOR_TRANSITION_DONE
		msg.post(screen.transition_url, message_id, message)
		if wait then
			coroutine.yield()
		end
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
	if screen.unregistered then return end
	if screen.focus_url then
		msg.post(screen.focus_url, M.FOCUS.LOST, { id = next_screen and next_screen.id })
		-- if there's no transition on the screen losing focus and it gets
		-- unloaded this will happen before the focus_lost message reaches
		-- the focus_url
		-- we add a delay to ensure the message queue has time to be processed
		cowait(screen, 0)
		cowait(screen, 0)
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

local function run_coroutine(screen, done_cb, fn)
	local co
	co = coroutine.create(function()
		screen.co = co
		-- don't pcall the function!
		-- it may contain a call to for instance change_context()
		-- this will result in a yield across metamethod/C call boundary
		fn()
		screen.co = nil
		pcallfn(done_cb)
	end)
	assert(coroutine.resume(co))
end

local function disable(screen, next_screen)
	log("disable()", screen.id)
	run_coroutine(screen, nil, function()
		change_context(screen)
		release_input(screen, next_screen)
		focus_lost(screen, next_screen)
		if next_screen and next_screen.popup then
			change_timestep(screen)
		else
			reset_timestep(screen)
		end
	end)
end

local function enable(screen, previous_screen)
	log("enable()", screen.id)
	run_coroutine(screen, nil, function()
		change_context(screen)
		acquire_input(screen)
		focus_gained(screen, previous_screen)
		reset_timestep(screen)
	end)
end

local function show_out(screen, next_screen, wait_for_transition, cb)
	log("show_out()", screen.id)
	assert(wait_for_transition ~= nil)
	-- make sure the screen is loaded. scenario:
	-- show A - stack [A]
	--   - show_in for A
	-- show B with no_stack = true - stack [A]
	--   - show_in for B and show_out for A
	-- show C
	--   - show_in for C and show_out for A again!
	if not screen.loaded then
		log("show_out() screen was not loaded")
		cb()
		return
	end
	run_coroutine(screen, cb, function()
		active_transition_count = active_transition_count + 1
		notify_transition_listeners(M.SCREEN_TRANSITION_OUT_STARTED, { screen = screen.id, next_screen = next_screen.id })
		change_context(screen)
		release_input(screen, next_screen)
		focus_lost(screen, next_screen)
		reset_timestep(screen)
		-- if the next screen is a popup we want the current screen to stay visible below the popup
		-- if the next screen isn't a popup the current one should be unloaded and transitioned out
		local next_is_popup = next_screen and next_screen.popup
		local current_is_popup = screen.popup
		if (not next_is_popup and not current_is_popup) or (current_is_popup) then
			transition(screen, M.TRANSITION.SHOW_OUT, { next_screen = next_screen.id }, wait_for_transition)
			screen.visible = false
			unload(screen)
		elseif next_is_popup then
			change_timestep(screen)
		end
		active_transition_count = active_transition_count - 1
		notify_transition_listeners(M.SCREEN_TRANSITION_OUT_FINISHED, { screen = screen.id, next_screen = next_screen.id })
	end)
end

local function show_in(screen, previous_screen, reload, add_to_stack, wait_for_transition, cb)
	log("show_in()", screen.id, wait_for_transition)
	assert(wait_for_transition ~= nil)
	run_coroutine(screen, cb, function()
		active_transition_count = active_transition_count + 1
		notify_transition_listeners(M.SCREEN_TRANSITION_IN_STARTED, { screen = screen.id, previous_screen = previous_screen and previous_screen.id })
		change_context(screen)
		if reload and screen.loaded then
			log("show_in() reloading", screen.id)
			unload(screen, reload)
		end
		if add_to_stack then
			stack[#stack + 1] = screen
		end
		local ok, err = load(screen)
		if not ok then
			log("show_in()", err)
			if add_to_stack then
				stack[#stack] = nil
			end
			active_transition_count = active_transition_count - 1
			notify_transition_listeners(M.SCREEN_TRANSITION_FAILED, { screen = screen.id })
			return
		end
		-- wait one frame so that the init() of any script have time to run before starting transitions
		cowait(screen, 0)
		reset_timestep(screen)
		transition(screen, M.TRANSITION.SHOW_IN, { previous_screen = previous_screen and previous_screen.id }, wait_for_transition)
		screen.visible = true
		acquire_input(screen)
		focus_gained(screen, previous_screen)
		active_transition_count = active_transition_count - 1
		notify_transition_listeners(M.SCREEN_TRANSITION_IN_FINISHED, { screen = screen.id, previous_screen = previous_screen and previous_screen.id })
	end)
end

local function back_in(screen, previous_screen, wait_for_transition, cb)
	log("back_in()", screen.id)
	assert(wait_for_transition ~= nil)
	run_coroutine(screen, cb, function()
		active_transition_count = active_transition_count + 1
		notify_transition_listeners(M.SCREEN_TRANSITION_IN_STARTED, { screen = screen.id, previous_screen = previous_screen and previous_screen.id })
		change_context(screen)
		local ok, err = load(screen)
		if not ok then
			log("back_in()", err)
			active_transition_count = active_transition_count - 1
			notify_transition_listeners(M.SCREEN_TRANSITION_FAILED, { screen = screen.id })
			return
		end
		-- wait one frame so that the init() of any script have time to run before starting transitions
		cowait(screen, 0)
		reset_timestep(screen)
		if previous_screen and not previous_screen.popup then
			transition(screen, M.TRANSITION.BACK_IN, { previous_screen = previous_screen.id }, wait_for_transition)
		end
		screen.visible = true
		acquire_input(screen)
		focus_gained(screen, previous_screen)
		active_transition_count = active_transition_count - 1
		notify_transition_listeners(M.SCREEN_TRANSITION_IN_FINISHED, { screen = screen.id, previous_screen = previous_screen and previous_screen.id })
	end)
end

local function back_out(screen, next_screen, wait_for_transition, cb)
	log("back_out()", screen.id)
	assert(wait_for_transition ~= nil)
	run_coroutine(screen, cb, function()
		active_transition_count = active_transition_count + 1
		notify_transition_listeners(M.SCREEN_TRANSITION_OUT_STARTED, { screen = screen.id, next_screen = next_screen and next_screen.id })
		change_context(screen)
		release_input(screen, next_screen)
		focus_lost(screen, next_screen)
		transition(screen, M.TRANSITION.BACK_OUT, { next_screen = next_screen and next_screen.id }, wait_for_transition)
		if next_screen and screen.popup then
			reset_timestep(next_screen)
		end
		screen.visible = false
		unload(screen)
		active_transition_count = active_transition_count - 1
		notify_transition_listeners(M.SCREEN_TRANSITION_OUT_FINISHED, { screen = screen.id, next_screen = next_screen and next_screen.id })
	end)
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
-- 		* sequential - Set to true to wait for the previous screen to show itself out before starting the
--				   show in transition even when transitioning to a different scene ID.
-- 		* no_stack - Set to true to load the screen without adding it to the screen stack.
-- 		* pop - The number of screens to pop from the stack before adding the new one.
-- @param data (*) - Optional data to set on the screen. Can be retrieved by the data() function
-- @param cb (function) - Optional callback to invoke when screen is shown
function M.show(id, options, data, cb)
	assert(id, "You must provide a screen id")
	id = tohash(id)
	assert(screens[id], ("There is no screen registered with id %s"):format(tostring(id)))

	queue_action(function(action_done, action_error)
		local screen = screens[id]
		if not screen then
			action_error(("show() there is no longer a screen with id %s"):format(tostring(id)))
			return
		end
		screen.data = data

		local co
		co = coroutine.create(function()

			local callbacks = callback_tracker()

			local top = stack[#stack]
			-- a screen can ignore the stack by setting the no_stack to true
			local add_to_stack = not options or not options.no_stack
			if add_to_stack and top then
				-- manipulate the current top
				-- close popup(s) if needed
				-- transition out
				local pop = options and options.pop or 0
				local is_not_popup = not screen.popup
				local pop_all_popups = is_not_popup -- pop all popups when transitioning screens

				-- keep top popup visible if new screen can be shown on top of a popup
				if top.popup and screen.popup and screen.popup_on_popup then
					disable(top, screen)
				else
					pop_all_popups = true
				end

				-- close popups, one by one, either all of them or the number specified by options.pop
				while top and top.popup do
					if not pop_all_popups then
						if pop <= 0 then break end
						pop = pop - 1
					end
					stack[#stack] = nil
					async(function(await, resume)
						await(show_out, top, screen, WAIT_FOR_TRANSITION, resume)
					end)
					top = stack[#stack]
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

				-- pop screens off the stack
				if is_not_popup then
					for i = 1, pop do
						local stack_top = #stack
						if stack_top < 1 then break end
						stack[stack_top] = nil
					end
				end
			end

			-- wait until preloaded if it is already preloading
			-- this can typically happen if you do a show() on app start for a
			-- screen that has Preload set to true
			if M.is_preloading(id) then
				M.when_preloaded(id, function()
					assert(coroutine.resume(co))
				end)
				coroutine.yield()
			end

			-- showing and hiding the same screen?
			local same_screen = top and top.id == screen.id
			if same_screen or (options and options.sequential) then
				if top then
					async(function(await, resume)
						await(show_out, top, screen, WAIT_FOR_TRANSITION, resume)
					end)
				end
				show_in(screen, top, options and options.reload, add_to_stack, WAIT_FOR_TRANSITION, callbacks.track())
			else
				-- show screen
				show_in(screen, top, options and options.reload, add_to_stack, WAIT_FOR_TRANSITION, callbacks.track())
				if add_to_stack and top and not top.popup then
					show_out(top, screen, WAIT_FOR_TRANSITION, callbacks.track())
				end
			end

			callbacks.when_done(function()
				pcallfn(cb)
				pcallfn(action_done)
			end)
		end)
		assert(coroutine.resume(co))
	end)
	return true -- return true for legacy reasons (before queue existed)
end


--- Replace the top of the stack with a new screen
-- @param id (string|hash) - Id of the screen to show
-- @param options (table) - Table with options when showing the screen (can be nil). Valid values:
-- 		* clear - Set to true if the stack should be cleared down to an existing instance of the screen
-- 		* reload - Set to true if screen should be reloaded if it already exists in the stack and is loaded.
--				   This would be the case if doing a show() from a popup on the screen just below the popup.
-- 		* no_stack - Set to true to load the screen without adding it to the screen stack.
-- @param data (*) - Optional data to set on the screen. Can be retrieved by the data() function
-- @param cb (function) - Optional callback to invoke when screen is shown
function M.replace(id, options, data, cb)
	return M.show(id, assign({ pop = 1 }, options), data, cb)
end


-- Hide a screen. The screen must either be at the top of the stack or
-- visible but not added to the stack (through the no_stack option)
-- @param id (string|hash) - Id of the screen to .hide
-- @param cb (function) - Optional callback to invoke when the screen is hidden
-- @return true if successfully hiding, false if busy or for some other reason unable to hide the screen
function M.hide(id, cb)
	assert(id, "You must provide a screen id")
	id = tohash(id)
	assert(screens[id], ("There is no screen registered with id %s"):format(tostring(id)))

	if M.in_stack(id) then
		if not M.is_top(id) then
			log("hide() you can only hide the screen at the top of the stack", id)
			return false
		end
		return M.back(id, cb)
	else
		log("hide() queuing action", id)
		queue_action(function(action_done, action_error)
			log("hide()", id)
			local callbacks = callback_tracker()
			if M.is_visible(id) then
				local screen = screens[id]
				if not screen then
					action_error(("hide() there is no longer a screen with id %s"):format(tostring(id)))
					return
				end
				back_out(screen, nil, WAIT_FOR_TRANSITION, callbacks.track())
			end
			callbacks.when_done(function()
				pcallfn(cb)
				pcallfn(action_done)
			end)
		end)
	end
	return true
end




-- Clear stack completely. Any visible screens will be hidden by navigating back out
-- from them.
-- @param cb (function) - Optional callback to invoke when the stack has been cleared
function M.clear(cb)
	log("clear() queuing action")

	queue_action(function(action_done, action_error)
		async(function(await, resume)
			local top = stack[#stack]
			while top and top.visible do
				stack[#stack] = nil
				await(back_out, top, stack[#stack - 1], WAIT_FOR_TRANSITION, resume)
				top = stack[#stack]
			end

			while stack[#stack] do
				table.remove(stack)
			end

			pcallfn(cb)
			pcallfn(action_done)
		end)
	end)
end


-- Go back to the previous screen in the stack.
-- @param options (table) - Table with options when backing out from the screen (can be nil).
--		Valid values:
-- 		* sequential - Set to true to wait for the current screen to hide itself out before starting the
--				   back in transition even when transitioning to a different scene ID.

-- @param data (*) - Optional data to set for the previous screen
-- @param cb (function) - Optional callback to invoke when the previous screen is visible again
function M.back(options, data, cb)
	log("back() queuing action")
	-- backwards compatibility with old version M.back(data, cb)
	-- case when back(data, cb)
	if type(data) == "function" then
		cb = data
		data = options
		options = nil
	-- case when back(data, nil)
	elseif options ~= nil and data == nil and cb == nil then
		data = options
		options = nil
	end

	queue_action(function(action_done)
		local callbacks = callback_tracker()
		local screen = table.remove(stack)
		if screen then
			log("back()", screen.id)
			local top = stack[#stack]
			-- if we go back to the same screen we need to first hide it
			-- and wait until it is hidden before we show it again
			local same_screen = top and top.id == screen.id
			if same_screen or (options and options.sequential) then
				local back_cb = callbacks.track()
				back_out(screen, top, WAIT_FOR_TRANSITION, function()
					if data then
						top.data = data
					end
					back_in(top, screen, WAIT_FOR_TRANSITION, back_cb)
				end)
			else
				if top then
					if data then
						top.data = data
					end
					-- if the screen we are backing out from is a popup and the screen we go
					-- back to is not a popup we need to let the popup completely hide before 
					-- we start working on the screen we go back to
					-- we do this to ensure that we do not reset the times step of the screen
					-- we go back to until it is no longer obscured by the popup
					if screen.popup and not top.popup then
						local back_cb = callbacks.track()
						back_out(screen, top, WAIT_FOR_TRANSITION, function()
							back_in(top, screen, WAIT_FOR_TRANSITION, back_cb)
						end)
					else
						back_in(top, screen, WAIT_FOR_TRANSITION, callbacks.track())
						back_out(screen, top, WAIT_FOR_TRANSITION, callbacks.track())
					end
				else
					back_out(screen, top, WAIT_FOR_TRANSITION, callbacks.track())
				end
			end
		end

		callbacks.when_done(function()
			pcallfn(cb)
			pcallfn(action_done)
		end)
	end)

	return true -- return true for legacy reasons (before queue existed)
end


--- Check if a screen is preloading via monarch.preload() or automatically
-- via the Preload screen option
-- @param id Screen id
-- @return true if preloading
function M.is_preloading(id)
	assert(id, "You must provide a screen id")
	id = tohash(id)
	assert(screens[id], ("There is no screen registered with id %s"):format(tostring(id)))
	local screen = screens[id]
	return screen.preloading
end
function M.is_preloaded(id)
	assert(id, "You must provide a screen id")
	id = tohash(id)
	assert(screens[id], ("There is no screen registered with id %s"):format(tostring(id)))
	local screen = screens[id]
	return screen.preloaded
end

--- Invoke a callback when a specific screen has been preloaded
-- This is mainly useful on app start when wanting to show a screen that
-- has the Preload flag set (since it will immediately start to load which
-- would prevent a call to monarch.show from having any effect).
function M.when_preloaded(id, cb)
	assert(id, "You must provide a screen id")
	id = tohash(id)
	assert(screens[id], ("There is no screen registered with id %s"):format(tostring(id)))
	local screen = screens[id]
	if screen.preloaded or screen.loaded then
		pcallfn(cb, id)
	else
		screen.preload_listeners[#screen.preload_listeners + 1] = cb
	end
end


--- Preload a screen. This will load but not enable and show a screen. Useful for "heavier" screens
-- that you wish to show without any delay.
-- @param id (string|hash) - Id of the screen to preload
-- @param options (table)
-- @param cb (function) - Optional callback to invoke when screen is loaded
function M.preload(id, options, cb)
	assert(id, "You must provide a screen id")
	id = tohash(id)
	assert(screens[id], ("There is no screen registered with id %s"):format(tostring(id)))

	-- support old function signature (id, cb)
	if type(options) == "function" and not cb then
		cb = options
		options = nil
	end

	log("preload() queuing action", id)
	queue_action(function(action_done, action_error)
		log("preload()", id)

		local screen = screens[id]
		if not screen then
			action_error(("preload() there is no longer a screen with id %s"):format(tostring(id)))
			return
		end

		-- keep_loaded is an option for monarch.preload()
		-- use it to get the same behavior as the auto preload checkbox
		screen.auto_preload = screen.auto_preload or options and options.keep_loaded

		if screen.preloaded or screen.loaded then
			pcallfn(cb)
			pcallfn(action_done)
			return
		end

		local function when_preloaded()
			-- invoke any listeners added using monarch.when_preloaded()
			while #screen.preload_listeners > 0 do
				pcallfn(table.remove(screen.preload_listeners), id)
			end
			-- invoke the normal callback
			pcallfn(cb)
			pcallfn(action_done)
		end
		run_coroutine(screen, when_preloaded, function()
			change_context(screen)
			local ok, err = preload(screen)
			if not ok then
				action_error(err)
			end
		end)
	end)
	return true -- return true for legacy reasons (before queue existed)
end


--- Unload a preloaded monarch screen
-- @param id (string|hash) - Id of the screen to unload
-- @param cb (function) - Optional callback to invoke when screen is unloaded
function M.unload(id, cb)
	assert(id, "You must provide a screen id")
	id = tohash(id)
	assert(screens[id], ("There is no screen registered with id %s"):format(tostring(id)))

	log("unload() queuing action", id)
	queue_action(function(action_done, action_error)
		if M.is_visible(id) then
			action_error("unload() you can't unload a visible screen")
			return
		end

		log("unload()", id)
		local screen = screens[id]
		if not screen then
			action_error(("unload() there is no longer a screen with id %s"):format(tostring(id)))
			return
		end

		if not screen.preloaded and not screen.loaded then
			log("unload() screen is not loaded", tostring(id))
			pcallfn(cb)
			pcallfn(action_done)
			return
		end

		local function when_unloaded()
			pcallfn(cb)
			pcallfn(action_done)
		end
		run_coroutine(screen, when_unloaded, function()
			change_context(screen)
			unload(screen, true)
		end)
	end)
	return true -- return true for legacy reasons (before queue existed)
end


--- Post a message to a screen (using msg.post)
-- @param id (string|hash) Id of the screen to send message to
-- @param message_id (string|hash) Id of the message to send
-- @param message (table|nil) Optional message data to send
-- @return result (boolean) true if successful
-- @return error (string|nil) Error message if unable to send message
function M.post(id, message_id, message)
	assert(id, "You must provide a screen id")
	if not M.is_visible(id) then
		return false, "Unable to post message to screen if it isn't visible"
	end

	assert(message_id, "You must provide a message_id")
	id = tohash(id)
	assert(screens[id], ("There is no screen registered with id %s"):format(tostring(id)))

	local screen = screens[id]
	if screen.receiver_url then
		log("post() sending message to", screen.receiver_url)
		msg.post(screen.receiver_url, message_id, message)
	else
		return false, "Unable to post message since screen has no receiver url specified. Set one using monarch.on_post()."
	end
	return true
end


function M.on_message(message_id, message, sender)
	if message_id == MSG_PROXY_LOADED then
		local screen = find_screen(sender)
		assert(screen, "Unable to find screen for loaded proxy")
		if screen.wait_for == WAITFOR_PROXY_LOADED then
			assert(coroutine.resume(screen.co))
		end
	elseif message_id == MSG_PROXY_UNLOADED then
		local screen = find_screen(sender)
		assert(screen, "Unable to find screen for unloaded proxy")
		if screen.wait_for == WAITFOR_PROXY_UNLOADED then
			assert(coroutine.resume(screen.co))
		end
	elseif message_id == MSG_CONTEXT then
		local screen = find_screen(sender)
		assert(screen, "Unable to find screen for current script url")
		if screen.wait_for == WAITFOR_CONTEXT then
			assert(coroutine.resume(screen.co))
		end
	elseif message_id == M.TRANSITION.DONE then
		local screen = find_transition_screen(sender)
		assert(screen, "Unable to find screen for transition")
		if screen.wait_for == WAITFOR_TRANSITION_DONE then
			assert(coroutine.resume(screen.co))
		end
	elseif message_id == M.TRANSITION.SHOW_IN
	or message_id == M.TRANSITION.SHOW_OUT
	or message_id == M.TRANSITION.BACK_IN
	or message_id == M.TRANSITION.BACK_OUT
	then
		local screen = find_transition_screen(sender)
		assert(screen, "Unable to find screen for transition")
		if screen.transition_fn then
			screen.transition_fn(message_id, message, sender)
		end
	elseif message_id == MSG_LAYOUT_CHANGED then
		local screen = find_screen(sender)
		if screen and screen.transition_fn then
			screen.transition_fn(message_id, message, sender)
		end
	elseif message_id == M.FOCUS.GAINED
	or message_id == M.FOCUS.LOST
	then
		local screen = find_focus_screen(sender)
		assert(screen, "Unable to find screen for focus change")
		if screen.focus_fn then
			screen.focus_fn(message_id, message, sender)
		end
	else
		local screen = find_post_receiver_screen(sender)
		if screen and screen.receiver_fn then
			screen.receiver_fn(message_id, message, sender)
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


--- Set the timestep to apply for a screen when below a popup
-- @param id (string|hash) Id of the screen to change timestep setting for
-- @param timestep (number) Timestep to apply
function M.set_timestep_below_popup(id, timestep)
	assert(id, "You must provide a screen id")
	assert(timestep, "You must provide a timestep")
	id = tohash(id)
	assert(screens[id], ("There is no screen registered with id %s"):format(tostring(id)))
	screens[id].timestep_below_popup = timestep
end


---
-- Set a function to call when a transition should be started
-- The function will receive (message_id, message, sender)
-- IMPORTANT! You must call monarch.on_message() from the same script as
-- this function was called
-- @param id Screen id to associate transition with
-- @param fn Transition handler function
function M.on_transition(id, fn)
	assert(id, "You must provide a screen id")
	assert(fn, "You must provide a transition function")
	id = tohash(id)
	assert(screens[id], ("There is no screen registered with id %s"):format(tostring(id)))
	local screen = screens[id]
	screen.transition_url = msg.url()
	screen.transition_fn = fn
end

---
-- Set a function to call when a screen gains or loses focus
-- The function will receive (message_id, message, sender)
-- IMPORTANT! You must call monarch.on_message() from the same script as
-- this function was called
-- @param id Screen id to associate focus listener function with
-- @param fn Focus listener function
function M.on_focus_changed(id, fn)
	assert(id, "You must provide a screen id")
	assert(fn, "You must provide a focus change function")
	id = tohash(id)
	assert(screens[id], ("There is no screen registered with id %s"):format(tostring(id)))
	local screen = screens[id]
	screen.focus_url = msg.url()
	screen.focus_fn = fn
end

---
-- Set either a function to be called when msg.post() is called on a specific
-- screen or a URL where the message is sent.
-- IMPORTANT! If you provide a function you must also make sure to call
-- monarch.on_message(message_id, message, sender) from the same script as
-- this function was called.
-- @param id Screen id to associate the message listener function with
-- @param fn_or_url The function to call or URL to send message to
function M.on_post(id, fn_or_url)
	assert(id, "You must provide a screen id")
	id = tohash(id)
	assert(screens[id], ("There is no screen registered with id %s"):format(tostring(id)))
	local screen = screens[id]

	local t = type(fn_or_url)
	if t == "function" then
		screen.receiver_fn = fn_or_url
		screen.receiver_url = msg.url()
	elseif t == "userdata" or t == "string" then
		screen.receiver_fn = nil
		screen.receiver_url = fn_or_url
	else
		screen.receiver_fn = nil
		screen.receiver_url = msg.url()
	end
end

local function url_to_key(url)
	return (url.socket or hash("")) .. (url.path or hash("")) .. (url.fragment or hash(""))
end


--- Add a listener to be notified of when screens are shown or hidden
-- @param url The url to notify, nil for current url
function M.add_listener(url)
	url = url or msg.url()
	transition_listeners[url_to_key(url)] = url
end


--- Remove a previously added listener
-- @param url The url to remove, nil for current url
function M.remove_listener(url)
	url = url or msg.url()
	transition_listeners[url_to_key(url)] = nil
end


function M.dump_stack()
	local s = ""
	for i, screen in ipairs(stack) do
		s = s .. ("%d = %s\n"):format(i, tostring(screen.id))
	end
	return s
end

function M.queue_size()
	return #queue
end


return M
