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

function M.fade_out(node, from, easing, duration, delay, cb)
	local to = gui.get_color(node)
	to.w = 1
	gui.set_color(node, to)
	to.w = 0
	gui.animate(node, gui.PROP_COLOR, to, easing, duration, delay, cb)
end

function M.fade_in(node, from, easing, duration, delay, cb)
	local to = gui.get_color(node)
	to.w = 0
	gui.set_color(node, to)
	to.w = 1
	gui.animate(node, gui.PROP_COLOR, to, easing, duration, delay, cb)
end



--- Create a transition
-- @return Transition instance
local function create()
	local instance = {}

	local transitions = {
		[monarch.TRANSITION.SHOW_IN] = { urls = {}, transitions = {}, in_progress_count = 0, },
		[monarch.TRANSITION.SHOW_OUT] = { urls = {}, transitions = {}, in_progress_count = 0, },
		[monarch.TRANSITION.BACK_IN] = { urls = {}, transitions = {}, in_progress_count = 0, },
		[monarch.TRANSITION.BACK_OUT] = { urls = {}, transitions = {}, in_progress_count = 0, },
	}

	local current_transition = nil

	local function create_transition(transition_id, node, fn, easing, duration, delay)
		local t = transitions[transition_id]
		-- find if there's already a transition for the node in
		-- question and if so update it instead of creating a new
		-- transition
		for _,transition in ipairs(t) do
			if transition.node == node then
				transition.fn = fn
				transition.easing = easing
				transition.duration = duration
				transitions.delay = delay
				return
			end
		end
		-- create new transition
		t.transitions[#t.transitions + 1] = {
			node = node,
			node_data = {
				pos = gui.get_position(node),
				scale = gui.get_scale(node),
			},
			fn = fn,
			easing = easing,
			duration = duration,
			delay = delay,
			id = transition_id
		}
	end

	local function finish_transition(transition_id)
		local t = transitions[transition_id]
		if #t.urls > 0 then
			local message = { transition = transition_id }
			while #t.urls > 0 do
				local url = table.remove(t.urls)
				msg.post(url, monarch.TRANSITION.DONE, message)
			end
		end
		current_transition = nil
	end

	local function check_and_finish_transition(transition_id)
		local t = transitions[transition_id]
		if t.in_progress_count == 0 then
			finish_transition(transition_id)
		end
	end

	local function start_transition(transition_id, url)
		local t = transitions[transition_id]
		table.insert(t.urls, url)
		if t.in_progress_count == 0 then
			table.insert(t.urls, msg.url())
			current_transition = t
			current_transition.id = transition_id
			if #t.transitions > 0 then
				for i=1,#t.transitions do
					local transition = t.transitions[i]
					t.in_progress_count = t.in_progress_count + 1
					transition.fn(transition.node, transition.node_data, transition.easing, transition.duration, transition.delay or 0, function()
						t.in_progress_count = t.in_progress_count - 1
						check_and_finish_transition(transition_id)
					end)
				end
			else
				check_and_finish_transition(transition_id)
			end
		end
	end

	-- Forward on_message calls here
	function instance.handle(message_id, message, sender)
		if message_id == LAYOUT_CHANGED then
			for _,t in pairs(transitions) do
				for _,transitions in pairs(t.transitions) do
					transitions.node_data.pos = gui.get_position(transitions.node)
				end
			end
			-- replay the current transition if the layout changes
			-- this will ensure that things are still hidden if they
			-- were transitioned out
			if current_transition then
				for _,transition in pairs(current_transition.transitions) do
					local node = transition.node
					transition.fn(transition.node, transition.node_data, transition.easing, 0, 0)
				end
				if current_transition.in_progress_count > 0 then
					finish_transition(current_transition.id)
				end
			end
		elseif message_id == monarch.TRANSITION.SHOW_IN
		or message_id == monarch.TRANSITION.SHOW_OUT
		or message_id == monarch.TRANSITION.BACK_IN
		or message_id == monarch.TRANSITION.BACK_OUT then
			start_transition(message_id, sender)
		end
	end

	-- Specify the transition function when this node is transitioned
	-- to
	-- @param fn Transition function (see slide_in_left and other above)
	-- @param easing Easing function to use
	-- @param duration Transition duration
	-- @param delay Transition delay
	function instance.show_in(node, fn, easing, duration, delay)
		create_transition(monarch.TRANSITION.SHOW_IN, node, fn, easing, duration, delay)
		return instance
	end

	-- Specify the transition function when this node is transitioned
	-- from when showing another screen
	function instance.show_out(node, fn, easing, duration, delay)
		create_transition(monarch.TRANSITION.SHOW_OUT, node, fn, easing, duration, delay)
		return instance
	end

	--- Specify the transition function when this node is transitioned
	-- to when navigating back in the screen stack
	function instance.back_in(node, fn, easing, duration, delay)
		create_transition(monarch.TRANSITION.BACK_IN, node, fn, easing, duration, delay)
		return instance
	end

	--- Specify the transition function when this node is transitioned
	-- from when navigating back in the screen stack
	function instance.back_out(node, fn, easing, duration, delay)
		create_transition(monarch.TRANSITION.BACK_OUT, node, fn, easing, duration, delay)
		return instance
	end

	return instance
end

function M.create(node)
	local instance = create()
	-- backward compatibility with the old version of create
	-- where a single node was used
	if node then
		local show_in = instance.show_in
		local show_out = instance.show_out
		local back_in = instance.back_in
		local back_out = instance.back_out
		instance.show_in = function(fn, easing, duration, delay)
			return show_in(node, fn, easing, duration, delay)
		end
		instance.show_out = function(fn, easing, duration, delay)
			return show_out(node, fn, easing, duration, delay)
		end
		instance.back_in = function(fn, easing, duration, delay)
			return back_in(node, fn, easing, duration, delay)
		end
		instance.back_out = function(fn, easing, duration, delay)
			return back_out(node, fn, easing, duration, delay)
		end
	end
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


function M.fade_in_out(node, duration, delay, easing)
	assert(node, "You must provide a node")
	assert(duration, "You must provide a duration")
	easing = easing or easings.QUAD()
	return M.create(node)
	.show_in(M.fade_in, easing.OUT, duration, delay or 0)
	.show_out(M.fade_out, easing.IN, duration, delay or 0)
	.back_in(M.fade_in, easing.OUT, duration, delay or 0)
	.back_out(M.fade_out, easing.IN, duration, delay or 0)
end


return M
