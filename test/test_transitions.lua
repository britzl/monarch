local cowait = require "test.cowait"
local mock_msg = require "test.msg"
local mock_gui = require "deftest.mock.gui"
local unload = require "deftest.util.unload"
local monarch = require "monarch.monarch"
local transitions = require "monarch.transitions.gui"
local easing = require "monarch.transitions.easings"

return function()

local function wait_timeout(fn, ...)
	local args = { ... }
	cowait(function() return fn(unpack(args)) end, 5)
	return fn(...)
end

describe("transitions", function()
	before(function()
		mock_msg.mock()
		mock_gui.mock()
		transitions = require "monarch.transitions.gui"
	end)

	after(function()
		mock_msg.unmock()
		mock_gui.unmock()
		unload.unload("monarch%..*")
	end)


	it("should replace an existing transition with a new one", function()
		local one = false
		function dummy_transition1(node, to, easing, duration, delay, cb)
			one = true
		end
		local two = false
		function dummy_transition2(node, to, easing, duration, delay, cb)
			two = true
		end
		
		local node = gui.new_box_node(vmath.vector3(), vmath.vector3(100, 100, 0))
		local duration = 2
		local t = transitions.create(node)
		t.show_in(dummy_transition1, easing.OUT, duration, delay or 0)
		t.show_in(dummy_transition2, easing.OUT, duration, delay or 0)
		t.handle(monarch.TRANSITION.SHOW_IN)
		
		wait_timeout(function() return one or two end)
		assert(two)
		assert(not one)
	end)

	it("should replay and immediately finish on layout change", function()
		function dummy_transition(node, to, easing, duration, delay, cb)
			print("dummy transition")
		end

		local node = gui.new_box_node(vmath.vector3(), vmath.vector3(100, 100, 0))
		local duration = 2
		local t = transitions.create(node)
		.show_in(dummy_transition, easing.OUT, duration, delay or 0)
		.show_out(dummy_transition, easing.IN, duration, delay or 0)
		.back_in(dummy_transition, easing.OUT, duration, delay or 0)
		.back_out(dummy_transition, easing.IN, duration, delay or 0)

		t.handle(monarch.TRANSITION.SHOW_IN)
		t.handle(hash("layout_changed"))
		local messages = mock_msg.messages(msg.url())
		assert(#messages == 1, "Expected one message to have been received")
		assert(messages[1].message_id == monarch.TRANSITION.DONE, "Expected a TRANSITION.DONE message")
	end)
end)

end
