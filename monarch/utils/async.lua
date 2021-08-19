local M = {}

local NOT_STARTED = "not_started"
local YIELDED = "yielded"
local RESUMED = "resumed"
local RUNNING = "running"

function M.async(fn)
	local co = coroutine.running()
	
	local state = NOT_STARTED

	local function await(fn, ...)
		state = RUNNING
		fn(...)
		if state ~= RUNNING then
			return
		end
		state = YIELDED
		local r = { coroutine.yield() }
		return unpack(r)
	end

	local function resume(...)
		if state ~= RUNNING then
			state = RUNNING
			local ok, err = coroutine.resume(co, ...)
			if not ok then
				print(err)
				print(debug.traceback())
			end
		end
	end

	if co then
		return fn(await, resume)
	else
		co = coroutine.create(fn)
		return resume(await, resume)
	end
end

return setmetatable(M, {
	__call = function(t, ...)
		return M.async(...)
	end
})