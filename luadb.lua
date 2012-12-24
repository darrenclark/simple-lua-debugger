local luadb_src = require 'luadb_src'

-------------------
-- Core
-------------------

local MODE_RUNNING = nil
local MODE_PAUSED = "paused"
local MODE_STEP_INTO = "step_into"
local MODE_STEP_OVER = "step_over"

local mode = nil
local step_over_depth = 0

local command_handlers = {}
local our_source = debug.getinfo(1, "S").source

local function get_line_of_code(debug_info)
	local file_name = debug_info.source

	-- not from a file
	if string.sub(file_name, 1, 1) ~= "@" then
		return nil
	end
	
	-- string '@'
	file_name = string.sub(file_name, 2)

	return luadb_src.get_line(file_name, debug_info.currentline)
end

local function listen_for_input(debug_info)
	local finished = false
	repeat
		local loc = get_line_of_code(debug_info)
		if loc then
			print("(db) " .. debug_info.short_src .. ":" .. debug_info.currentline .. ":", loc)
		end
		io.write("(db) >> ")
		local input = io.read()
		local command = string.match(input, "%w+")

		local handler = command_handlers[command]
		if handler then
			finished, error_msg = pcall(function() handler(input) end)
			if not finished and error_msg then
				print("(db) Failed running command: " .. tostring(error_msg))
			end
		else
			print("(db) Unknown command: " .. command)
		end
	until finished
end

local function debug_event(event, line)
	-- ignore events if they are happening inside luadb
	local debug_info = debug.getinfo(2, "lS")
	local source = debug_info.source
	if source == our_source then
		return
	end
	
	if event == "line" then
		if mode == MODE_PAUSED then
			listen_for_input(debug_info)
		elseif mode == MODE_STEP_INTO then
			mode = MODE_PAUSED
			listen_for_input(debug_info)
		elseif mode == MODE_STEP_OVER then
			if step_over_depth == 0 then
				mode = MODE_PAUSED
				listen_for_input(debug_info)
			end
		end
	elseif mode == MODE_STEP_OVER then
		if event == "call" then
			step_over_depth = step_over_depth + 1
		elseif event == "return" or event == "tail return" then
			step_over_depth = step_over_depth - 1
		end
	end
end

local function breakpoint()
	if mode == MODE_RUNNING then
		local debug_info = debug.getinfo(2, "Sl")
		local src = debug_info.short_src
		local line = debug_info.currentline
		print("(db) Hit breakpoint: " .. src .. ":" .. line)

		mode = MODE_PAUSED
		debug.sethook(debug_event, "lrc")
	end
end

-------------------
-- Commands
-------------------

command_handlers["continue"] = function()
	debug.sethook()
	mode = MODE_RUNNING
end
command_handlers["c"] = command_handlers["continue"]

command_handlers["step"] = function()
	mode = MODE_STEP_INTO
end
command_handlers["s"] = command_handlers["step"]

command_handlers["next"] = function()
	mode = MODE_STEP_OVER
end
command_handlers["n"] = command_handlers["next"]

-------------------
-- Public interface
-------------------

local luadb = {}
luadb.b = breakpoint
luadb.breakpoint = breakpoint

return luadb
