local M = {}

local WIDTH = tonumber(sys.get_config("display.width"))
local HEIGHT = tonumber(sys.get_config("display.height"))

local LEFT = vmath.vector3(-WIDTH * 2, 0, 0)
local RIGHT = vmath.vector3(WIDTH * 2, 0, 0)
local TOP = vmath.vector3(0, HEIGHT * 2, 0)
local BOTTOM = vmath.vector3(0, -HEIGHT * 2, 0)

function M.instant(node, to, easing, duration, delay, url)
	msg.post(url, "transition_done")
end

local function slide_in(direction, node, to, easing, duration, delay, url)
	local from = to + direction
	gui.set_position(node, from)
	gui.animate(node, gui.PROP_POSITION, to, easing, duration, delay, function()
		msg.post(url, "transition_done")
	end)
end

function M.slide_in_left(node, to, easing, duration, delay, url)
	return slide_in(LEFT, node, to, easing, duration, delay, url)
end

function M.slide_in_right(node, to, easing, duration, delay, url)
	slide_in(RIGHT, node, to, easing, duration, delay, url)
end

function M.slide_in_top(node, to, easing, duration, delay, url)
	slide_in(TOP, node, to, easing, duration, delay, url)
end

function M.slide_in_bottom(node, to, easing, duration, delay, url)
	slide_in(BOTTOM, node, to, easing, duration, delay, url)
end


local function slide_out(direction, node, from, easing, duration, delay, url)
	local to = from + direction
	gui.set_position(node, from)
	gui.animate(node, gui.PROP_POSITION, to, easing, duration, delay, function()
		msg.post(url, "transition_done")
	end)
end

function M.slide_out_left(node, from, easing, duration, delay, url)
	slide_out(LEFT, node, from, easing, duration, delay, url)
end

function M.slide_out_right(node, from, easing, duration, delay, url)
	slide_out(RIGHT, node, from, easing, duration, delay, url)
end

function M.slide_out_top(node, from, easing, duration, delay, url)
	slide_out(TOP, node, from, easing, duration, delay, url)
end

function M.slide_out_bottom(node, from, easing, duration, delay, url)
	slide_out(BOTTOM, node, from, easing, duration, delay, url)
end

--- Create a transition for a node
-- @return Transition instance
function M.create(node)
	assert(node, "You must provide a node")

	local instance = {}
	
	local transitions = {
		[hash("transition_show_in")] = M.instant,
		[hash("transition_show_out")] = M.instant,
		[hash("transition_back_in")] = M.instant,
		[hash("transition_back_out")] = M.instant,
	}
	
	local initial_position = gui.get_position(node)
	
	-- Forward on_message calls here
	function instance.handle(message_id, message, sender)
		if transitions[message_id] then
			transitions[message_id](sender)
		end
	end
	
	-- Specify the transition function when this node is transitioned
	-- to
	-- @param fn Transition function (see slide_in_left and other above)
	-- @param easing Easing function to use
	-- @param duration Transition duration
	-- @param delay Transition delay
	function instance.show_in(fn, easing, duration, delay)
		transitions[hash("transition_show_in")] = function(url)
			fn(node, initial_position, easing, duration, delay or 0, url)
		end
		return instance
	end

	-- Specify the transition function when this node is transitioned
	-- from when showing another screen
	function instance.show_out(fn, easing, duration, delay)
		transitions[hash("transition_show_out")] = function(url)
			fn(node, initial_position, easing, duration, delay or 0, url)
		end
		return instance
	end

	--- Specify the transition function when this node is transitioned
	-- to when navigating back in the screen stack
	function instance.back_in(fn, easing, duration, delay)
		transitions[hash("transition_back_in")] = function(url)
			fn(node, initial_position, easing, duration, delay or 0, url)
		end
		return instance
	end

	--- Specify the transition function when this node is transitioned
	-- from when navigating back in the screen stack
	function instance.back_out(fn, easing, duration, delay)
		transitions[hash("transition_back_out")] = function(url)
			fn(node, initial_position, easing, duration, delay or 0, url)
		end
		return instance
	end
	
	return instance
end

return M