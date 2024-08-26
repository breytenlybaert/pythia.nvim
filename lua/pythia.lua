local M = {}

-- Function to send text to llm and stream the result
local function send_to_llm(text, replace_file)
	-- Create a temporary file to store the input
	local tmp_input = os.tmpname()

	-- Write the input text to the temporary file
	local input_file = io.open(tmp_input, "w")
	input_file:write(text)
	input_file:close()

	-- Prepare buffer for output
	if replace_file then
		-- Clear the entire buffer
		vim.api.nvim_buf_set_lines(0, 0, -1, false, {})
	else
		-- Move cursor to the end of the buffer and add a new line
		local last_line = vim.api.nvim_buf_line_count(0)
		vim.api.nvim_win_set_cursor(0, { last_line, 0 })
		vim.api.nvim_buf_set_lines(0, last_line, last_line, false, { "" })
	end

	-- Get the current cursor position
	local cursor = vim.api.nvim_win_get_cursor(0)
	local row, col = cursor[1] - 1, cursor[2] -- Convert to 0-based index

	-- Function to handle job output
	local function on_stdout(_, data)
		if data then
			for _, chunk in ipairs(data) do
				for char in chunk:gmatch(".") do
					if char == "\n" then
						-- Move to the next line
						row = row + 1
						col = 0
						vim.api.nvim_buf_set_lines(0, row, row, false, { "" })
					else
						-- Insert the character at the current cursor position
						vim.api.nvim_buf_set_text(0, row, col, row, col, { char })
						col = col + 1
					end
					-- Update the cursor position
					vim.api.nvim_win_set_cursor(0, { row + 1, col }) -- Convert back to 1-based index
				end
			end
		end
	end

	-- Function to clean up after job completion
	local function on_exit()
		os.remove(tmp_input)
	end

	-- Start the job
	vim.fn.jobstart(string.format("llm < %s", tmp_input), {
		on_stdout = on_stdout,
		on_stderr = on_stdout, -- Handle stderr same as stdout
		on_exit = on_exit,
		stdout_buffered = false,
		stderr_buffered = false,
	})
end

-- Function to send the entire file content to llm
function M.send_file()
	local content = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
	send_to_llm(content, true) -- true indicates to replace the entire file
end

-- Function to send the yanked text to llm
function M.send_yanked()
	local yanked = vim.fn.getreg('"')
	send_to_llm(yanked, false) -- false indicates to append on a new line
end

return M
