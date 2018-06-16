local monarch = require "monarch.monarch"
local easings = require "monarch.transitions.easings"

local M = {}

local WIDTH = nil
local HEIGHT = nil
local LEFT = nil
local RIGHT = nil
local TOP = nil
local BOTTOM = nil

local ZERO_SCALE = vmath.vector3(0, 0, 1)

local LAYOUT_CHANGED = hash("layout_changed")

-- Notify the transition system that the window size has changed
-- @param width
-- @param height
function M.window_resized(width, height)
	WIDTH = width
	HEIGHT = height
	LEFT = vmath.vector3(-WIDTH * 2, 0, 0)
	RIGHT = vmath.vector3(WIDTH * 2, 0, 0)
	TOP = vmath.vector3(0, HEIGHT * 2, 0)
	BOTTOM = vmath.vector3(0, - HEIGHT * 2, 0)
end

M.window_resized(tonumber(sys.get_config("display.width")), tonumber(sys.get_config("display.height")))


function M.instant(node, to, easing, duration, delay, cb)
	cb()
end

local function slide_in(direction, node, to, easing, duration, delay, cb)
	local from = to + direction
	gui.set_position(node, from)
	gui.animate(node, gui.PROP_POSITION, to, easing, duration, delay, cb)
end

function M.slide_in_left(node, to, easing, duration, delay, cb)
	return slide_in(LEFT, node, to.pos, easing, duration, delay, cb)
end

function M.slide_in_right(node, to, easing, duration, delay, cb)
	slide_in(RIGHT, node, to.pos, easing, duration, delay, cb)
end

function M.slide_in_top(node, to, easing, duration, delay, cb)
	slide_in(TOP, node, to.pos, easing, duration, delay, cb)
end

function M.slide_in_bottom(node, to, easing, duration, delay, cb)
	slide_in(BOTTOM, node, to.pos, easing, duration, delay, cb)
end


local function slide_out(direction, node, from, easing, duration, delay, cb)
	local to = from + direction
	gui.set_position(node, from)
	gui.animate(node, gui.PROP_POSITION, to, easing, duration, delay, cb)
end

function M.slide_out_left(node, from, easing, duration, delay, cb)
	slide_out(LEFT, node, from.pos, easing, duration, delay, cb)
end

function M.slide_out_right(node, from, easing, duration, delay, cb)
	slide_out(RIGHT, node, from.pos, easing, duration, delay, cb)
end

function M.slide_out_top(node, from, easing, duration, delay, cb)
	slide_out(TOP, node, from.pos, easing, duration, delay, cb)
end

function M.slide_out_bottom(node, from, easing, duration, delay, cb)
	slide_out(BOTTOM, node, from.pos, easing, duration, delay, cb)
end

function M.scale_in(node, to, easing, duration, delay, cb)
	gui.set_scale(node, ZERO_SCALE)
	gui.animate(node, gui.PROP_SCALE, to.scale, easing, duration, delay, cb)
end

function M.scale_out(node, from, easing, duration, delay, cb)
	gui.set_scale(node, from.scale)
	gui.animate(node, gui.PROP_SCALE, ZERO_SCALE, easing, duration, delay, cb)
end

--- Create a transition for a node
-- @return Transition instance
function M.create(node)
	assert(node, "You must provide a node")

	local instance = {}

	local transitions = {}

	local current_transition = nil
	
	local initial_data = {}
	initial_data.pos = gui.get_position(node)
	initial_data.scale = gui.get_scale(node)

	local function create_transition(fn, easing, duration, delay)
		return {
			fn = fn,
			easing = easing,
			duration = duration,
			delay = delay,
			in_progress = false,
			urls = {},
			id = nil
		}
	end

	local function finish_transition(transition)
		transition.in_progress = false
		local message = { transition = transition.id }
		while #transition.urls > 0 do
			local url = table.remove(transition.urls)
			msg.post(url, monarch.TRANSITION.DONE, message)
		end
	end

	local function start_transition(transition, transition_id, url)
		table.insert(transition.urls, url)
		if not transition.in_progress then
			table.insert(transition.urls, msg.url())
			transition.in_progress = true
			transition.id = transition_id
			current_transition = transition
			transition.fn(node, initial_data, transition.easing, transition.duration, transition.delay or 0, function()
				finish_transition(transition)
			end)
		end
	end

	-- Forward on_message calls here
	function instance.handle(message_id, message, sender)
		if message_id == LAYOUT_CHANGED then
			initial_data.pos = gui.get_position(node)
			-- replay the current transition if the layout changes
			-- this will ensure that things are still hidden if they
			-- were transitioned out
			if current_transition then
				current_transition.fn(node, initial_data, current_transition.easing, 0, 0)
				if current_transition.in_progress then
					finish_transition(current_transition)
				end
			end
		else
			local transition = transitions[message_id]
			if transition then
				start_transition(transition, message_id, sender)
			end
		end
	end
	
	-- Specify the transition function when this node is transitioned
	-- to
	-- @param fn Transition function (see slide_in_left and other above)
	-- @param easing Easing function to use
	-- @param duration Transition duration
	-- @param delay Transition delay
	function instance.show_in(fn, easing, duration, delay)
		transitions[monarch.TRANSITION.SHOW_IN] = create_transition(fn, easing, duration, delay)
		return instance
	end

	-- Specify the transition function when this node is transitioned
	-- from when showing another screen
	function instance.show_out(fn, easing, duration, delay)
		transitions[monarch.TRANSITION.SHOW_OUT] = create_transition(fn, easing, duration, delay)
		return instance
	end

	--- Specify the transition function when this node is transitioned
	-- to when navigating back in the screen stack
	function instance.back_in(fn, easing, duration, delay)
		transitions[monarch.TRANSITION.BACK_IN] = create_transition(fn, easing, duration, delay)
		return instance
	end

	--- Specify the transition function when this node is transitioned
	-- from when navigating back in the screen stack
	function instance.back_out(fn, easing, duration, delay)
		transitions[monarch.TRANSITION.BACK_OUT] = create_transition(fn, easing, duration, delay)
		return instance
	end

	-- set default transitions (instant)
	instance.show_in(M.instant)
	instance.show_out(M.instant)
	instance.back_in(M.instant)
	instance.back_out(M.instant)
	
	return instance
end


--- Create transition where the screen slides in from the right when shown and out
-- to the left when hidden (and the reverse when going back)
-- @param node
-- @param duration
-- @param delay Optional. Defaults to 0
-- @param easing Optional. A constant from monarch.transitions.easing
-- @return Transition instance
function M.in_right_out_left(node, duration, delay, easing)
	assert(node, "You must provide a node")
	assert(duration, "You must provide a duration")
	easing = easing or easings.QUAD()
	return M.create(node)
	.show_in(M.slide_in_right, easing.OUT, duration, delay or 0)
	.show_out(M.slide_out_left, easing.IN, duration, delay or 0)
	.back_in(M.slide_in_left, easing.OUT, duration, delay or 0)
	.back_out(M.slide_out_right, easing.IN, duration, delay or 0)
end


function M.in_left_out_right(node, duration, delay, easing)
	assert(node, "You must provide a node")
	assert(duration, "You must provide a duration")
	easing = easing or easings.QUAD()
	return M.create(node)
	.show_in(M.slide_in_left, easing.OUT, duration, delay or 0)
	.show_out(M.slide_out_right, easing.IN, duration, delay or 0)
	.back_in(M.slide_in_right, easing.OUT, duration, delay or 0)
	.back_out(M.slide_out_left, easing.IN, duration, delay or 0)
end


function M.in_right_out_right(node, duration, delay, easing)
	assert(node, "You must provide a node")
	assert(duration, "You must provide a duration")
	easing = easing or easings.QUAD()
	return M.create(node)
	.show_in(M.slide_in_right, easing.OUT, duration, delay or 0)
	.show_out(M.slide_out_right, easing.IN, duration, delay or 0)
	.back_in(M.slide_in_right, easing.OUT, duration, delay or 0)
	.back_out(M.slide_out_right, easing.IN, duration, delay or 0)
end


function M.in_left_out_left(node, duration, delay, easing)
	assert(node, "You must provide a node")
	assert(duration, "You must provide a duration")
	easing = easing or easings.QUAD()
	return M.create(node)
	.show_in(M.slide_in_left, easing.OUT, duration, delay or 0)
	.show_out(M.slide_out_left, easing.IN, duration, delay or 0)
	.back_in(M.slide_in_left, easing.OUT, duration, delay or 0)
	.back_out(M.slide_out_left, easing.IN, duration, delay or 0)
end


return M
