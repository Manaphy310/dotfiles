return {
	-- コンテキストに応じたコメント文字列を提供
	{
		"JoosepAlviste/nvim-ts-context-commentstring",
		lazy = true,
		opts = {
			enable_autocmd = false,
			languages = {
				typescript = "// %s",
				tsx = {
					__default = "// %s",
					__multiline = "/* %s */",
					jsx_element = "{/* %s */}",
					jsx_fragment = "{/* %s */}",
					jsx_attribute = "// %s",
					comment = "// %s",
				},
			},
		},
	},

	-- mini.comment の設定（LazyVimのデフォルトを上書き）
	{
		"nvim-mini/mini.comment",
		event = "VeryLazy",
		opts = {
			options = {
				custom_commentstring = function()
					return require("ts_context_commentstring.internal").calculate_commentstring() or vim.bo.commentstring
				end,
			},
		},
	},
}
