local M = {}

function M.setup()
	local pythia = require("pythia")
	vim.keymap.set("n", "<leader>lf", pythia.send_file, { desc = "Send file to LLM" })
	vim.keymap.set("n", "<leader>ly", pythia.send_yanked, { desc = "Send yanked text to LLM" })
end

return M
