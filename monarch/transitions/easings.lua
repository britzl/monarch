local M = {}


local function create(name)
	assert(gui["EASING_OUT" .. name])
	assert(gui["EASING_IN" .. name])
	return {
		IN = gui["EASING_OUT" .. name],
		OUT = gui["EASING_IN" .. name],
	}
end


function M.BACK() return create("BACK") end
function M.BOUNCE() return create("BOUNCE") end
function M.CIRC() return create("CIRC") end
function M.CUBIC() return create("CUBIC") end
function M.ELASTIC() return create("ELASTIC") end
function M.EXPO() return create("EXPO") end
function M.QUAD() return create("QUAD") end
function M.QUART() return create("QUART") end
function M.QUINT() return create("QUINT") end
function M.SINE() return create("SINE") end


return M