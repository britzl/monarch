local unload = require "deftest.util.unload"
local cowat = require "test.cowait"
local callback_tracker = require "monarch.utils.callback_tracker"

return function()

	describe("callback tracker", function()
		before(function()
			callback_tracker = require "monarch.utils.callback_tracker"
		end)

		after(function()
			unload.unload("monarch%..*")
		end)


		it("should be able to tell when all callbacks are done", function()
			local tracker = callback_tracker.create()
			local t1 = tracker.track()
			local t2 = tracker.track()

			local done = false
			tracker.when_done(function() done = true end)
			
			assert(not done, "It should not be done yet - No callback has completed")
			t1()
			assert(not done, "It should not be done yet - Only one callback has completed")
			t2()
			assert(done, "It should be done now - All callbacks have completed")
		end)

		it("should indicate if a tracked callback has been invoked more than once", function()
			local tracker = callback_tracker.create()
			local t = tracker.track()
			local ok, err = t()
			assert(ok == true and err == nil, "It should return true when successful")
			ok, err = t()
			assert(ok == false and err, "It should return false and a message when invoked multiple times")
		end)

		it("should not be possible to track the same callback more than one time", function()
			local tracker = callback_tracker.create()
			local t1 = tracker.track()
			local t2 = tracker.track()

			local done = false
			tracker.when_done(function() done = true end)

			assert(not done, "It should not be done yet - No callback has completed")
			t1()
			t1()
			assert(not done, "It should not be done yet - Even if one callback has been invoked twice")
			t2()
			assert(done, "It should be done now - All callbacks have completed")
		end)

		it("should handle when callbacks are done before calling when_done()", function()
			local tracker = callback_tracker.create()
			local t1 = tracker.track()
			local t2 = tracker.track()
			t1()
			t2()

			local done = false
			tracker.when_done(function() done = true end)
			assert(done, "It should be done now - All callbacks have completed")
		end)
	end)
end
