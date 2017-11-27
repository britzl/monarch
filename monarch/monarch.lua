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

M.FOCUS_GAINED = hash("monarch_focus_gained")
M.FOCUS_LOST = hash("monarch_focus_lost")


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

local function in_stack(id)
	for i = 1, #stack do
		if stack[i].id == id then
			return true
		end
	end
	return false
end

function M.register(id, proxy, popup, transition_url, focus_url)
	assert(not screens[id], ("There is already a screen registered with id %s"):format(tostring(id)))
	screens[id] = {
		id = id,
		proxy = proxy,
		script = msg.url(),
		popup = popup,
		transition_url = transition_url,
		focus_url = focus_url,
	}
end

function M.unregister(id)
	assert(screens[id], ("There is no screen registered with id %s"):format(tostring(id)))
	screens[id] = nil
end

local function show_out(screen, next_screen, cb)
	local co
	co = coroutine.create(function()
		screen.co = co
		msg.post(screen.script, RELEASE_INPUT_FOCUS)
		msg.post(screen.script, CONTEXT)
		coroutine.yield()
		if not next_screen.popup then
			msg.post(screen.transition_url, M.TRANSITION.SHOW_OUT)
			coroutine.yield()
			msg.post(screen.proxy, UNLOAD)
			coroutine.yield()
			screen.loaded = false
		end
		if screen.focus_url then
			msg.post(screen.focus_url, M.FOCUS_LOST, {id = next_screen.id})
		end
		screen.co = nil
		if cb then cb() end
	end)
	coroutine.resume(co)
end

local function show_in(screen, reload, cb)
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
		msg.post(screen.script, ACQUIRE_INPUT_FOCUS)
		if screen.focus_url then
			msg.post(screen.focus_url, M.FOCUS_GAINED, {id = screen.id})
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
		if not previous_screen.popup then
			msg.post(screen.proxy, ASYNC_LOAD)
			coroutine.yield()
			msg.post(screen.proxy, ENABLE)
			screen.loaded = true
			msg.post(screen.transition_url, M.TRANSITION.BACK_IN)
			coroutine.yield()
		end
		msg.post(screen.script, ACQUIRE_INPUT_FOCUS)
		if screen.focus_url then
			msg.post(screen.focus_url, M.FOCUS_GAINED, {id = previous_screen.id})
		end
		screen.co = nil
		if cb then cb() end
	end)
	coroutine.resume(co)
end

local function back_out(screen, cb)
	local co
	co = coroutine.create(function()
		screen.co = co
		msg.post(screen.script, RELEASE_INPUT_FOCUS)
		msg.post(screen.script, CONTEXT)
		coroutine.yield()
		msg.post(screen.transition_url, M.TRANSITION.BACK_OUT)
		coroutine.yield()
		msg.post(screen.proxy, UNLOAD)
		coroutine.yield()
		screen.loaded = false
		if screen.focus_url then
			msg.post(screen.focus_url, M.FOCUS_LOST, {id = screen.id})
		end
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
-- 		* reload - Set to true if screen should be reloaded if it already exists in the stack and is loaded
--				  This would be the case if doing a show() from a popup on the screen just below the popup.
-- @param data Optional data to set on the screen. Can be retrieved by the data() function
-- @ param cb Optional callback to invoke when screen is shown
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
		if top and top.id ~= screen.id then
			show_out(top, screen)
		end
	end

	-- if the screen we want to show is in the stack
	-- already and the clear flag is set then we need
	-- to remove every screen on the stack up until and
	-- including the screen itself
	if options and options.clear then
		while in_stack(id) do
			table.remove(stack)
		end
	end

	-- show screen
	show_in(screen, options and options.reload, cb)
end


-- Go back to the previous screen in the stack
-- @param data Optional data to set for the previous screen
-- @param cb Optional callback to invoke when the previous screen is visible again
function M.back(data, cb)
	local screen = table.remove(stack)
	if screen then
		back_out(screen, cb)
		local top = stack[#stack]
		if top then
			if data then
				screen.data = data
			end
			back_in(top, screen)
		end
	elseif cb then
		cb()
	end
end


function M.on_message(message_id, message, sender)
	if message_id == PROXY_LOADED then
		local screen = screen_from_proxy(sender)
		assert(screen, "Unable to find screen for loaded proxy")
		coroutine.resume(screen.co)
	elseif message_id == PROXY_UNLOADED then
		local screen = screen_from_proxy(sender)
		assert(screen, "Unable to find screen for unloaded proxy")
		coroutine.resume(screen.co)
	elseif message_id == CONTEXT then
		local screen = screen_from_script()
		assert(screen, "Unable to find screen for current script url")
		coroutine.resume(screen.co)
	elseif message_id == M.TRANSITION.DONE then
		local screen = screen_from_script()
		assert(screen, "Unable to find screen for current script url")
		coroutine.resume(screen.co)
	end
end

function M.dump_stack()
	local s = ""
	for i, screen in ipairs(stack) do
		s = s .. ("%d = %s\n"):format(i, tostring(screen.id))
	end
	return s
end

return M
