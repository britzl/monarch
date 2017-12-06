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
-- @param id
-- @return true of the screen is in the stack
function M.in_stack(id)
	for i = 1, #stack do
		if stack[i].id == id then
			return true
		end
	end
	return false
end


--- Check if a screen is at the top of the stack
-- (primarily used for unit tests, but could have a usecase outside tests)
-- @param id
-- @return true if the screen is at the top of the stack
function M.is_top(id)
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
-- @param popup true the screen is a popup
-- @param transition_url Optional URL to a script that is
-- responsible for the screen transitions
-- @param focus_url Optional URL to a script that is to be notified of
-- focus lost/gained events
function M.register(id, proxy, popup, transition_url, focus_url)
	assert(not screens[id], ("There is already a screen registered with id %s"):format(tostring(id)))
	assert(proxy, "You must provide a collection proxy URL")
	local url = msg.url(proxy)
	screens[id] = {
		id = id,
		proxy = proxy,
		script = msg.url(),
		popup = popup,
		transition_url = transition_url,
		focus_url = focus_url,
	}
end

--- Unregister a screen
-- This is done automatically by the screen.script
-- @param id Id of the screen to unregister
function M.unregister(id)
	assert(screens[id], ("There is no screen registered with id %s"):format(tostring(id)))
	screens[id] = nil
end

local function show_out(screen, next_screen, cb)
	local co
	co = coroutine.create(function()
		screen.co = co
		msg.post(screen.script, RELEASE_INPUT_FOCUS)
		screen.input = false

		if screen.focus_url then
			msg.post(screen.focus_url, M.FOCUS.LOST, {id = next_screen.id})
		end
				
		msg.post(screen.script, CONTEXT)
		coroutine.yield()
		-- if the next screen is a popup we want the current screen to stay visible below the popup
		-- if the next screen isn't a popup the current one should be unloaded and transitioned out
		local next_is_popup = next_screen and not next_screen.popup
		local current_is_popup = screen.popup
		if (next_is_popup and not current_is_popup) or (current_is_popup) then
			msg.post(screen.transition_url, M.TRANSITION.SHOW_OUT)
			coroutine.yield()
			msg.post(screen.proxy, UNLOAD)
			coroutine.yield()
			screen.loaded = false
		end
		screen.co = nil
		if cb then cb() end
	end)
	coroutine.resume(co)
end

local function show_in(screen, previous_screen, reload, cb)
	local co
	co = coroutine.create(function()
		screen.co = co
		msg.post(screen.script, CONTEXT)
		coroutine.yield()

		if reload and screen.loaded then
			msg.post(screen.proxy, UNLOAD)
			coroutine.yield()
			screen.loaded = false
		end
	
		-- the screen could be loaded if the previous screen was a popup
		-- and the popup asked to show this screen again
		-- in that case we shouldn't attempt to load it again
		if not screen.loaded then
			msg.post(screen.proxy, ASYNC_LOAD)
			coroutine.yield()
			msg.post(screen.proxy, ENABLE)
			screen.loaded = true
		end
		stack[#stack + 1] = screen
		msg.post(screen.transition_url, M.TRANSITION.SHOW_IN)
		coroutine.yield()

		if not screen.input then
			msg.post(screen.script, ACQUIRE_INPUT_FOCUS)
			screen.input = true
		end
		
		if screen.focus_url then
			msg.post(screen.focus_url, M.FOCUS.GAINED, {id = previous_screen and previous_screen.id})
		end
		screen.co = nil
		if cb then cb() end
	end)
	coroutine.resume(co)
end

local function back_in(screen, previous_screen, cb)
	local co
	co = coroutine.create(function()
		screen.co = co
		msg.post(screen.script, CONTEXT)
		coroutine.yield()
		if not screen.loaded then
			msg.post(screen.proxy, ASYNC_LOAD)
			coroutine.yield()
			msg.post(screen.proxy, ENABLE)
			screen.loaded = true
		end
		if previous_screen and not previous_screen.popup then
			msg.post(screen.transition_url, M.TRANSITION.BACK_IN)
			coroutine.yield()
		end

		if not screen.input then
			msg.post(screen.script, ACQUIRE_INPUT_FOCUS)
			screen.input = true
		end

		if screen.focus_url then
			msg.post(screen.focus_url, M.FOCUS.GAINED, {id = previous_screen.id})
		end
		screen.co = nil
		if cb then cb() end
	end)
	coroutine.resume(co)
end

local function back_out(screen, next_screen, cb)
	local co
	co = coroutine.create(function()
		screen.co = co
		msg.post(screen.script, RELEASE_INPUT_FOCUS)
		screen.input = false
		if screen.focus_url then
			msg.post(screen.focus_url, M.FOCUS.LOST, {id = next_screen and next_screen.id})
		end
		msg.post(screen.script, CONTEXT)
		coroutine.yield()
		msg.post(screen.transition_url, M.TRANSITION.BACK_OUT)
		coroutine.yield()
		msg.post(screen.proxy, UNLOAD)
		coroutine.yield()
		screen.loaded = false
		screen.co = nil
		if cb then cb() end
	end)
	coroutine.resume(co)
end


--- Get data associated with a screen
-- @param id Id of the screen to get data for
-- @return Data associated with the screen
function M.data(id)
	assert(id, "You must provide a screen id")
	assert(screens[id], ("There is no screen registered with id %s"):format(tostring(id)))
	return screens[id].data
end

--- Checks to see if a screen id is registered
-- @param id Id of the screen to check if is registered
-- @return True or False if the screen id is registered or not
function M.screen_exists(id)
	return screens[id] ~= nil
end

--- Show a new screen
-- @param id Id of the screen to show
-- @param options Table with options when showing the screen (can be nil). Valid values:
-- 		* clear - Set to true if the stack should be cleared down to an existing instance of the screen
-- 		* reload - Set to true if screen should be reloaded if it already exists in the stack and is loaded.
--				  This would be the case if doing a show() from a popup on the screen just below the popup.
-- @param data Optional data to set on the screen. Can be retrieved by the data() function
-- @param cb Optional callback to invoke when screen is shown
function M.show(id, options, data, cb)
	assert(id, "You must provide a screen id")
	assert(screens[id], ("There is no screen registered with id %s"):format(tostring(id)))

	local screen = screens[id]
	screen.data = data

	-- manipulate the current top
	-- close popup if needed
	-- transition out
	local top = stack[#stack]
	if top then
		-- if top is popup then close it
		if top.popup then
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

	-- if the screen we want to show is in the stack
	-- already and the clear flag is set then we need
	-- to remove every screen on the stack up until and
	-- including the screen itself
	if options and options.clear then
		while M.in_stack(id) do
			table.remove(stack)
		end
	end

	-- show screen
	show_in(screen, top, options and options.reload, cb)
end


-- Go back to the previous screen in the stack
-- @param data Optional data to set for the previous screen
-- @param cb Optional callback to invoke when the previous screen is visible again
function M.back(data, cb)
	local screen = table.remove(stack)
	if screen then
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


function M.on_message(message_id, message, sender)
	if message_id == PROXY_LOADED then
		local screen = screen_from_proxy(sender)
		assert(screen, "Unable to find screen for loaded proxy")
		assert(coroutine.resume(screen.co))
	elseif message_id == PROXY_UNLOADED then
		local screen = screen_from_proxy(sender)
		assert(screen, "Unable to find screen for unloaded proxy")
		assert(coroutine.resume(screen.co))
	elseif message_id == CONTEXT then
		local screen = screen_from_script()
		assert(screen, "Unable to find screen for current script url")
		assert(coroutine.resume(screen.co))
	elseif message_id == M.TRANSITION.DONE then
		local screen = screen_from_script()
		assert(screen, "Unable to find screen for current script url")
		assert(coroutine.resume(screen.co))
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
