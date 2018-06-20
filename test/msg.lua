local mock = require "deftest.mock.mock"


local M = {}


local recipients = {}

local history = {}

local function get_recipient(url)
	recipients[url] = recipients[url] or {}
	return recipients[url]
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