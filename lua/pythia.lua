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
local function send_to_llm(text, replace_file)
    -- Create a temporary file to store the input
    local tmp_input = os.tmpname()

    -- Write the input text to the temporary file
    local input_file = io.open(tmp_input, "w")
    input_file:write(text)
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
            vim.api.nvim_buf_set_lines(0, row, row, false, {""})
        end
    end

    -- Function to handle job output
    local function on_stdout(_, data)
        if data then
            for _, chunk in ipairs(data) do
                for char in chunk:gmatch(".") do
                    if char == "\n" then
                        -- Move to the next line
                        row = row + 1
                        col = 0
                        -- If we're at the end of the buffer, add a new line
                        if row == vim.api.nvim_buf_line_count(0) then
                            vim.api.nvim_buf_set_lines(0, row, row, false, {""})
                        end
                    else
                        -- Insert the character at the current cursor position
                        vim.api.nvim_buf_set_text(0, row, col, row, col, {char})
                        col = col + 1
                    end
                end
            end
            -- Update the cursor position
            vim.api.nvim_win_set_cursor(0, {row + 1, col}) -- Convert back to 1-based index
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
    send_to_llm(yanked, false) -- false indicates to insert at the first empty line or end of buffer
end

return M

-- File: lua/pythia/init.lua
local M = {}

function M.setup()
    local pythia = require("pythia")
    vim.keymap.set("n", "<leader>lf", pythia.send_file, { desc = "Send file to LLM" })
    vim.keymap.set("n", "<leader>ly", pythia.send_yanked, { desc = "Send yanked text to LLM" })
end

return M

-- In your Neovim config (init.lua or wherever you configure lazy.nvim)
return {
    "breytenlybaert/pythia.nvim",
    lazy = true,
    config = true,
    keys = {
        { "<leader>lf", desc = "Send file to LLM" },
        { "<leader>ly", desc = "Send yanked text to LLM" },
    },
}
