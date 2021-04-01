local M = {}

function M.seconds(amount)
	local co = coroutine.running()
	assert(co, "You must run this from within a coroutine")
	timer.delay(amount, false, function()
		local ok, err = coroutine.resume(co)
		if not ok then
			print(err)
		end
	end)
	coroutine.yield()
end

function M.eval(fn, timeout)
	local co = coroutine.running()
	assert(co, "You must run this from within a coroutine")
	local start = socket.gettime()
	timer.delay(0.02, true, function(self, handle, time_elapsed)
		if fn() or (timeout and socket.gettime() > (start + timeout)) then
			timer.cancel(handle)
			local ok, err = coroutine.resume(co)
			if not ok then
				print(err)
			end
		end
	end)
	coroutine.yield()
end

return setmetatable(M, {
	__call = function(self, arg1, ...)
		if type(arg1) == "number" then
			return M.seconds(arg1, ...)
		elseif type(arg1) == "function" then
			return M.eval(arg1, ...)
		else
			error("Unknown argument type")
		end
	end
})