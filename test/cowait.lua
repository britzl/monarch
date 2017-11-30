local M = {}


local instances = {}

local function create(fn)
	local instance = {
		co = coroutine.running(),
		fn = fn,
	}
	table.insert(instances, instance)
	coroutine.yield(instance.co)
end

	

function M.seconds(amount)
	local time = socket.gettime() + amount
	create(function()
		return socket.gettime() >= time
	end)
end


function M.eval(fn)
	create(fn)
end

function M.update()
	for k,instance in pairs(instances) do
		if instance.fn() then
			instances[k] = nil
			coroutine.resume(instance.co)
		end
	end
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