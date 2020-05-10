local mock = require "deftest.mock.mock"


local M = {}


local recipients = {}

local history = {}

local function url_to_key(url)
	if type(url) == "string" then
		url = msg.url(url)
	end
	local ok, err = pcall(function() return url.socket end)
	if not ok then
		return url
	end
	if url.socket then
		return hash_to_hex(url.socket or hash("")) ..  hash_to_hex(url.path or hash("")) ..  hash_to_hex(url.fragment or hash(""))
	else
		return url
	end
end

local function get_recipient(url)
	local key = url_to_key(url)
	recipients[key] = recipients[key] or {}
	return recipients[key]
end

local function post(url, message_id, message)
	local data = { url = url, message_id = message_id, message = message }
	history[#history + 1] = data
	local recipient = get_recipient(url)
	recipient[#recipient + 1] = data
	msg.post.original(url, message_id, message or {})
end

function M.mock()
	recipients = {}
	history = {}
	mock.mock(msg)
	msg.post.replace(post)
end

function M.unmock()
	mock.unmock(msg)
end



function M.messages(url)
	return url and get_recipient(url) or history
end

function M.first(url)
	local messages = url and get_recipient(url) or history
	return messages[1]
end

function M.last(url)
	local messages = url and get_recipient(url) or history
	return messages[#messages]
end


return M