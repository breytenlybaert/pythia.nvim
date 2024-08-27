local M = {}

-- Function to find the first empty line or the end of the buffer
local function find_insert_position()
	local line_count = vim.api.nvim_buf_line_count(0)
	for i = 0, line_count - 1 do
		local line = vim.api.nvim_buf_get_lines(0, i, i + 1, false)[1]
		if line == "" then
			return i
		end
	end
	return line_count
end

-- Function to send text to llm and stream the result
local function send_to_llm(text, replace_file, system_message, instruction, title)
	-- Create a temporary file to store the input
	local tmp_input = os.tmpname()

	-- Prepare the input content
	local input_content = ""
	if system_message then
		input_content = input_content .. "System: " .. system_message .. "\n\n"
	end
	if instruction then
		input_content = input_content .. "Instruction: " .. instruction .. "\n\n"
	end
	if title then
		input_content = input_content .. "Title: " .. title .. "\n\n"
	end
	input_content = input_content .. "Content:\n" .. text

	-- Write the input content to the temporary file
	local input_file = io.open(tmp_input, "w")
	input_file:write(input_content)
	input_file:close()

	-- Prepare buffer for output
	local row, col
	if replace_file then
		-- Clear the entire buffer
		vim.api.nvim_buf_set_lines(0, 0, -1, false, {})
		row, col = 0, 0
	else
		-- Find the first empty line or the end of the buffer
		row = find_insert_position()
		col = 0
		-- If we're at the end of the buffer, add a new line
		if row == vim.api.nvim_buf_line_count(0) then
			vim.api.nvim_buf_set_lines(0, row, row, false, { "" })
		end
	end

	local buffer = ""
	local function on_stdout(_, data)
		if data then
			local debug_file = io.open("/tmp/neovim_llm_debug.log", "a")
			for _, chunk in ipairs(data) do
				debug_file:write("Raw chunk: " .. vim.inspect(chunk) .. "\n")

				-- Append the chunk to the buffer
				buffer = buffer .. chunk

				-- Process complete lines
				while true do
					local line_end = buffer:find("\n")
					if not line_end then
						break
					end

					local line = buffer:sub(1, line_end - 1)
					buffer = buffer:sub(line_end + 1)

					-- Insert the line
					vim.api.nvim_buf_set_lines(0, -1, -1, false, { line })
					debug_file:write("Line inserted: " .. line .. "\n")
				end
			end
			debug_file:close()
		end
	end

	-- Function to handle job completion
	local function on_exit()
		-- Insert any remaining text in the buffer
		if buffer ~= "" then
			vim.api.nvim_buf_set_lines(0, -1, -1, false, { buffer })
			local debug_file = io.open("/tmp/neovim_llm_debug.log", "a")
			debug_file:write("Final line inserted: " .. buffer .. "\n")
			debug_file:close()
		end
		buffer = "" -- Clear the buffer
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
	send_to_llm(content, true)
end

-- Function to send the yanked text to llm
function M.send_yanked()
	local yanked = vim.fn.getreg('"')
	send_to_llm(yanked, false)
end

-- New function to send file with instruction
function M.send_file_with_instruction()
	local content = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
	local title = vim.fn.expand("%:t") -- Get the current file name

	-- Prompt for instruction
	local instruction = vim.fn.input("Enter instruction: ")
	if instruction == "" then
		print("Cancelled")
		return
	end

	-- Send to LLM with instruction
	send_to_llm(content, true, "Answer only in code", instruction, title)
end

return M
