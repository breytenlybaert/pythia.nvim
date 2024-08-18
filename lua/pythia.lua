local M = {}
local Job = require("plenary.job")

local function get_api_key(name)
	return os.getenv(name)
end

function M.get_lines_until_cursor()
	local current_buffer = vim.api.nvim_get_current_buf()
	local current_window = vim.api.nvim_get_current_win()
	local cursor_position = vim.api.nvim_win_get_cursor(current_window)
	local row = cursor_position[1]
	local lines = vim.api.nvim_buf_get_lines(current_buffer, 0, row, true)
	return table.concat(lines, "\n")
end

function M.get_visual_selection()
	local _, srow, scol = unpack(vim.fn.getpos("v"))
	local _, erow, ecol = unpack(vim.fn.getpos("."))
	if vim.fn.mode() == "V" then
		return vim.api.nvim_buf_get_lines(0, math.min(srow, erow) - 1, math.max(srow, erow), true)
	elseif vim.fn.mode() == "v" then
		return vim.api.nvim_buf_get_text(0, srow - 1, scol - 1, erow - 1, ecol, {})
	elseif vim.fn.mode() == "\22" then
		local lines = {}
		for i = math.min(srow, erow), math.max(srow, erow) do
			table.insert(lines, vim.api.nvim_buf_get_text(0, i - 1, scol - 1, i - 1, ecol, {})[1])
		end
		return lines
	end
end

function M.write_string_at_cursor(str)
	vim.schedule(function()
		local cursor_position = vim.api.nvim_win_get_cursor(0)
		local row, col = cursor_position[1], cursor_position[2]
		local lines = vim.split(str, "\n")
		vim.cmd("undojoin")
		vim.api.nvim_put(lines, "c", true, true)
		vim.api.nvim_win_set_cursor(0, { row + #lines - 1, col + #lines[#lines] })
	end)
end

local function make_curl_args(opts, prompt, system_prompt)
	local api_key = get_api_key(opts.api_key_name)
	local data = {
		messages = { { role = "system", content = system_prompt }, { role = "user", content = prompt } },
		model = opts.model,
		stream = true,
	}
	local args = { "-N", "-X", "POST", "-H", "Content-Type: application/json", "-d", vim.json.encode(data), opts.url }
	if api_key then
		table.insert(args, 5, "-H")
		table.insert(args, 6, "Authorization: Bearer " .. api_key)
	end
	return args
end

local function handle_data_stream(data_stream, insert_mode)
	local json = vim.json.decode(data_stream)
	if json.choices and json.choices[1].delta then
		local content = json.choices[1].delta.content or ""
		if insert_mode then
			M.write_string_at_cursor(content)
		else
			print(content)
		end
	end
end

function M.invoke_llm(opts, insert_mode)
	local prompt = M.get_visual_selection() and table.concat(M.get_visual_selection(), "\n")
		or M.get_lines_until_cursor()
	local args = make_curl_args(opts, prompt, opts.system_prompt)
	Job:new({
		command = "curl",
		args = args,
		on_stdout = function(_, out)
			handle_data_stream(out, insert_mode)
		end,
		on_stderr = function(_, _) end,
		on_exit = function()
			vim.api.nvim_clear_autocmds({ group = "DING_LLM_AutoGroup" })
		end,
	}):start()
end

return M
