return {
	-- コンテキストに応じたコメント文字列を提供
	{
		"JoosepAlviste/nvim-ts-context-commentstring",
		event = "VeryLazy",
		opts = {
			enable_autocmd = false,
		},
	},

	-- mini.comment の設定（LazyVimのデフォルトを上書き）
	{
		"nvim-mini/mini.comment",
		event = "VeryLazy",
		dependencies = { "JoosepAlviste/nvim-ts-context-commentstring" },
		opts = function()
			return {
				options = {
					custom_commentstring = function()
						return require("ts_context_commentstring").calculate_commentstring() or vim.bo.commentstring
					end,
				},
			}
		end,
	},
}
