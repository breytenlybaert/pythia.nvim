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

    -- Run the llm command and capture its output
    local handle = io.popen(string.format("llm < %s", tmp_input), "r")
    local raw_output = handle:read("*a")
    handle:close()

    -- Log the raw output
    local debug_file = io.open("/tmp/neovim_llm_debug.log", "w")
    debug_file:write("Raw llm output:\n")
    debug_file:write(vim.inspect(raw_output))
    debug_file:close()

    -- Process the output
    local lines = {}
    for line in (raw_output.."\n"):gmatch("(.-)\n") do
        table.insert(lines, line)
    end

    -- Determine where to insert the output
    local start_row = 0
    if not replace_file then
        start_row = vim.api.nvim_buf_line_count(0)
    end

    -- Insert the lines into the buffer
    vim.api.nvim_buf_set_lines(0, start_row, -1, false, lines)

    -- Clean up
    os.remove(tmp_input)
end

	local function on_stdout(_, data)
		if data then
			local debug_file = io.open("/tmp/neovim_llm_debug.log", "a")
			for _, chunk in ipairs(data) do
				raw_output = raw_output .. chunk
				debug_file:write("Raw chunk: " .. vim.inspect(chunk) .. "\n")

				for i = 1, #chunk do
					local char = chunk:sub(i, i)
					if char == "\n" then
						-- Move to the next line
						row = row + 1
						col = 0
						vim.api.nvim_buf_set_lines(0, row, row, false, { "" })
					elseif char == "\r" then
						-- Move cursor to the beginning of the line
						col = 0
						-- Clear the current line
						vim.api.nvim_buf_set_lines(0, row, row + 1, false, { "" })
					else
						-- Get the current line
						local line = vim.api.nvim_buf_get_lines(0, row, row + 1, false)[1]
						-- Insert or replace the character
						if col < #line then
							line = line:sub(1, col) .. char .. line:sub(col + 2)
						else
							line = line .. char
						end
						vim.api.nvim_buf_set_lines(0, row, row + 1, false, { line })
						col = col + 1
					end

					-- Update the cursor position
					vim.api.nvim_win_set_cursor(0, { row + 1, col })
				end

				debug_file:write("After chunk processing - row: " .. row .. ", col: " .. col .. "\n")
			end
			debug_file:close()
		end
	end

	local function on_exit()
		os.remove(tmp_input)
		-- Log the complete raw output
		local debug_file = io.open("/tmp/neovim_llm_debug.log", "a")
		debug_file:write("Complete raw output:\n" .. vim.inspect(raw_output) .. "\n")
		debug_file:close()
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

-- Function to send file with instruction
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
