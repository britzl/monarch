local cowait = require "test.cowait"
local mock_msg = require "test.msg"
local unload = require "deftest.util.unload"
local monarch = require "monarch.monarch"

local SCREEN1_STR = hash("screen1")
local SCREEN1 = hash(SCREEN1_STR)
local SCREEN2 = hash("screen2")
local POPUP1 = hash("popup1")
local POPUP2 = hash("popup2")
local FOOBAR = hash("foobar")
local TRANSITION1 = hash("transition1")

return function()

	local screens_instances = {}

	local function is_shown(screen_id)
		return monarch.is_top(screen_id)
	end

	local function is_hidden(screen_id)
		return not monarch.is_top(screen_id)
	end

	local function wait_timeout(fn, ...)
		local args = { ... }
		local time = socket.gettime()
		cowait(function()
			return fn(unpack(args)) or socket.gettime() > time + 5	
		end)
		return fn(...)
	end
		
	local function wait_until_shown(screen_id)
		return wait_timeout(is_shown, screen_id)
	end
	local function wait_until_hidden(screen_id)
		return wait_timeout(is_hidden, screen_id)
	end
	local function wait_until_not_busy()
		return wait_timeout(function() return not monarch.is_busy() end)
	end

	local function assert_stack(expected_screens)
		local actual_screens = monarch.get_stack()
		if #actual_screens ~= #expected_screens then
			error("Stack length mismatch", 2)
		end
		for i=1,#actual_screens do
			if actual_screens[i] ~= expected_screens[i] then
				error("Stack content not matching", 2)
			end
		end
	end

	
	describe("monarch", function()
		before(function()
			mock_msg.mock()
			monarch = require "monarch.monarch"
			screens_instances = collectionfactory.create("#screensfactory")
		end)

		after(function()
			while #monarch.get_stack() > 0 do
				monarch.back()
				wait_until_not_busy()
			end
			mock_msg.unmock()
			unload.unload("monarch%..*")
			for id,instance_id in pairs(screens_instances) do
				go.delete(instance_id)
			end
			cowait(0.1)
		end)


		it("should be able to tell if a screen exists", function()
			assert(monarch.screen_exists(SCREEN1))
			assert(monarch.screen_exists(SCREEN1_STR))
			assert(not monarch.screen_exists(hash("foobar")))
		end)


		it("should be able to show screens and go back to previous screens", function()
			monarch.show(SCREEN1_STR)
			assert(wait_until_shown(SCREEN1), "Screen1 was never shown")
			assert_stack({ SCREEN1 })

			monarch.show(SCREEN2)
			assert(wait_until_hidden(SCREEN1), "Screen1 was never hidden")
			assert(wait_until_shown(SCREEN2), "Screen2 was never shown")
			assert_stack({ SCREEN1, SCREEN2 })

			monarch.back()
			assert(wait_until_hidden(SCREEN2), "Screen2 was never hidden")
			assert(wait_until_shown(SCREEN1), "Screen1 was never shown")
			assert_stack({ SCREEN1 })

			monarch.back()
			assert(wait_until_hidden(SCREEN1), "Screen1 was never hidden")
			assert_stack({ })
		end)

		it("should be able to tell if a screen is visible or not", function()
			assert(not monarch.is_visible(SCREEN1))
			monarch.show(SCREEN1)
			assert(wait_until_shown(SCREEN1), "Screen1 was never shown")
			assert_stack({ SCREEN1 })
			assert(monarch.is_visible(SCREEN1))
			
			monarch.show(SCREEN2)
			assert(wait_until_hidden(SCREEN1), "Screen1 was never hidden")
			assert(wait_until_shown(SCREEN2), "Screen2 was never shown")
			assert_stack({ SCREEN1, SCREEN2 })
			assert(not monarch.is_visible(SCREEN1))
			assert(monarch.is_visible(SCREEN2))
			
			monarch.show(POPUP1)
			assert(wait_until_shown(POPUP1), "Popup1 was never shown")
			assert_stack({ SCREEN1, SCREEN2, POPUP1 })
			assert(not monarch.is_visible(SCREEN1))
			assert(monarch.is_visible(SCREEN2))
			assert(monarch.is_visible(POPUP1))
		end)
		

		it("should be able to pass data to a screen when showning it or going back to it", function()
			local data1 = { foo = "bar" }
			monarch.show(SCREEN1, nil, data1)
			assert(wait_until_shown(SCREEN1), "Screen1 was never shown")

			local data2 = { boo = "car" }
			monarch.show(SCREEN2, nil, data2)
			assert(wait_until_shown(SCREEN2), "Screen2 was never shown")
			
			assert(monarch.data(SCREEN1) == data1, "Expected data on screen1 doesn't match actual data")
			assert(monarch.data(SCREEN2) == data2, "Expected data on screen2 doesn't match actual data")

			local data_back = { going = "back" }
			monarch.back(data_back)
			assert_stack({ SCREEN1 })

			assert(monarch.data(SCREEN1) == data_back, "Expected data on screen1 doesn't match actual data")
		end)


		it("should be able to show the same screen twice", function()
			monarch.show(SCREEN1)
			assert(wait_until_shown(SCREEN1), "Screen1 was never shown")
			assert_stack({ SCREEN1 })
			monarch.show(SCREEN1)
			assert(wait_until_shown(SCREEN1), "Screen1 was never shown")
			assert_stack({ SCREEN1, SCREEN1 })
		end)
		

		it("should be able to clear the stack if trying to show the same screen twice", function()
			monarch.show(SCREEN1)
			assert(wait_until_shown(SCREEN1), "Screen1 was never shown")
			assert_stack({ SCREEN1 })
			monarch.show(SCREEN2)
			assert(wait_until_shown(SCREEN2), "Screen2 was never shown")
			assert_stack({ SCREEN1, SCREEN2 })
			monarch.show(SCREEN1, { clear = true })
			assert(wait_until_shown(SCREEN1), "Screen1 was never shown")
			assert_stack({ SCREEN1 })
		end)
		

		it("should be able to show one popup on top of another if the Popup On Popup flag is set", function()
			monarch.show(SCREEN1)
			assert(wait_until_shown(SCREEN1), "Screen1 was never shown")
			assert_stack({ SCREEN1 })
			monarch.show(POPUP1)
			assert(wait_until_shown(POPUP1), "Popup1 was never shown")
			assert_stack({ SCREEN1, POPUP1 })
			monarch.show(POPUP2)
			assert(wait_until_shown(POPUP2), "Popup2 was never shown")
			assert_stack({ SCREEN1, POPUP1, POPUP2 })
		end)

		
		it("should prevent further operations while hiding/showing a screen", function()
			assert(monarch.show(SCREEN1) == true)
			assert(monarch.show(SCREEN2) == false)
			assert(wait_until_shown(SCREEN1), "Screen1 was never shown")
			assert_stack({ SCREEN1 })

			assert(monarch.show(SCREEN2) == true)
			assert(wait_until_shown(SCREEN2), "Screen2 was never shown")
			assert_stack({ SCREEN1, SCREEN2 })

			assert(monarch.back() == true)
			assert(monarch.back() == false)
			assert(wait_until_shown(SCREEN1), "Screen1 was never shown")
			assert_stack({ SCREEN1 })
		end)
		
		
		it("should close any open popups when showing a popup without the Popup On Popup flag", function()
			monarch.show(SCREEN1)
			assert(wait_until_shown(SCREEN1), "Screen1 was never shown")
			assert_stack({ SCREEN1 })
			monarch.show(POPUP2)
			assert(wait_until_shown(POPUP2), "Popup2 was never shown")
			assert_stack({ SCREEN1, POPUP2 })
			monarch.show(POPUP1)
			assert(wait_until_shown(POPUP1), "Popup1 was never shown")
			assert_stack({ SCREEN1, POPUP1 })
		end)

		
		it("should close any open popups when showing a non-popup", function()
			monarch.show(SCREEN1)
			assert(wait_until_shown(SCREEN1), "Screen1 was never shown")
			assert_stack({ SCREEN1 })
			monarch.show(POPUP1)
			assert(wait_until_shown(POPUP1), "Popup1 was never shown")
			assert_stack({ SCREEN1, POPUP1 })
			monarch.show(POPUP2)
			assert(wait_until_shown(POPUP2), "Popup2 was never shown")
			assert_stack({ SCREEN1, POPUP1, POPUP2 })
			monarch.show(SCREEN2)
			assert(wait_until_shown(SCREEN2), "Popup2 was never shown")
			assert_stack({ SCREEN1, SCREEN2 })
		end)


		it("should be able to get the id of the screen at the top and bottom of the stack", function()
			assert(monarch.top() == nil)
			assert(monarch.bottom() == nil)
			assert(monarch.top(1) == nil)
			assert(monarch.bottom(-1) == nil)
						
			monarch.show(SCREEN1)
			assert(wait_until_shown(SCREEN1), "Screen1 was never shown")
			assert(monarch.top() == SCREEN1)
			assert(monarch.top(0) == SCREEN1)
			assert(monarch.top(1) == nil)
			assert(monarch.bottom() == SCREEN1)
			assert(monarch.bottom(0) == SCREEN1)
			assert(monarch.bottom(-1) == nil)
									
			monarch.show(SCREEN2)
			assert(wait_until_hidden(SCREEN1), "Screen1 was never hidden")
			assert(wait_until_shown(SCREEN2), "Screen2 was never shown")
			assert_stack({ SCREEN1, SCREEN2 })
			assert(monarch.top(0) == SCREEN2)
			assert(monarch.top(-1) == SCREEN1)
			assert(monarch.bottom(0) == SCREEN1)
			assert(monarch.bottom(1) == SCREEN2)
		end)

		it("should be busy while transition is running", function()
			monarch.show(TRANSITION1)
			assert(wait_until_shown(TRANSITION1), "Transition1 was never shown")
			assert(monarch.is_busy())
			assert(wait_until_not_busy())
		end)

		it("should ignore any preload calls while busy", function()
			monarch.show(TRANSITION1)
			-- previously a call to preload() while also showing a screen would
			-- lock up monarch. See issue #32
			monarch.preload(TRANSITION1)
			assert(wait_until_shown(TRANSITION1), "Transition1 was never shown")
		end)
		
		it("should be able to notify listeners of navigation events", function()
			local URL1 = msg.url(screens_instances[hash("/listener1")])
			local URL2 = msg.url(screens_instances[hash("/listener2")])
			monarch.add_listener(URL1)
			monarch.add_listener(URL2)

			monarch.show(SCREEN1)
			assert(mock_msg.messages(URL1)[1].message_id == monarch.SCREEN_TRANSITION_IN_STARTED)
			assert(mock_msg.messages(URL1)[1].message.screen == SCREEN1)
			assert(mock_msg.messages(URL2)[1].message_id == monarch.SCREEN_TRANSITION_IN_STARTED)
			assert(mock_msg.messages(URL2)[1].message.screen == SCREEN1)
			assert(wait_until_not_busy())
			assert(mock_msg.messages(URL1)[2].message_id == monarch.SCREEN_TRANSITION_IN_FINISHED)
			assert(mock_msg.messages(URL1)[2].message.screen == SCREEN1)
			assert(mock_msg.messages(URL2)[2].message_id == monarch.SCREEN_TRANSITION_IN_FINISHED)
			assert(mock_msg.messages(URL2)[2].message.screen == SCREEN1)
												
			monarch.remove_listener(URL2)
			monarch.show(SCREEN2)
			assert(wait_until_not_busy())

			assert(#mock_msg.messages(URL1) == 6)
			assert(#mock_msg.messages(URL2) == 2)
			assert(mock_msg.messages(URL1)[3].message_id == monarch.SCREEN_TRANSITION_OUT_STARTED)
			assert(mock_msg.messages(URL1)[3].message.screen == SCREEN1)
			assert(mock_msg.messages(URL1)[4].message_id == monarch.SCREEN_TRANSITION_IN_STARTED)
			assert(mock_msg.messages(URL1)[4].message.screen == SCREEN2)
			assert(mock_msg.messages(URL1)[5].message_id == monarch.SCREEN_TRANSITION_IN_FINISHED)
			assert(mock_msg.messages(URL1)[5].message.screen == SCREEN2)
			assert(mock_msg.messages(URL1)[6].message_id == monarch.SCREEN_TRANSITION_OUT_FINISHED)
			assert(mock_msg.messages(URL1)[6].message.screen == SCREEN1)
						
			monarch.back()
			assert(wait_until_not_busy())
						
			assert(#mock_msg.messages(URL1) == 10)
			assert(#mock_msg.messages(URL2) == 2)
			assert(mock_msg.messages(URL1)[7].message_id == monarch.SCREEN_TRANSITION_OUT_STARTED)
			assert(mock_msg.messages(URL1)[7].message.screen == SCREEN2)
			assert(mock_msg.messages(URL1)[8].message_id == monarch.SCREEN_TRANSITION_IN_STARTED)
			assert(mock_msg.messages(URL1)[8].message.screen == SCREEN1)
			assert(mock_msg.messages(URL1)[9].message_id == monarch.SCREEN_TRANSITION_OUT_FINISHED)
			assert(mock_msg.messages(URL1)[9].message.screen == SCREEN2)
			assert(mock_msg.messages(URL1)[10].message_id == monarch.SCREEN_TRANSITION_IN_FINISHED)
			assert(mock_msg.messages(URL1)[10].message.screen == SCREEN1)
		end)
	end)
end
