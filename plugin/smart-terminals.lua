if vim.g.loaded_smart_terminals then
	return
end
vim.g.loaded_smart_terminals = true

-- Auto-setup if not explicitly called
vim.api.nvim_create_autocmd("VimEnter", {
	callback = function()
		if not vim.g.smart_terminals_setup_called then
			vim.g.smart_terminals_setup_called = true
			require("smart-terminals").setup()
		end
	end,
})

