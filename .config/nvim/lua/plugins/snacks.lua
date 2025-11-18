return {
  "folke/snacks.nvim",
  opts = {
    terminal = {
      win = {
        position = "bottom",
        height = 0.20, -- 通常のターミナルは20%の高さ
      },
    },
    lazygit = {
      win = {
        position = "float",
        width = 0.9,
        height = 0.9,
      },
      -- パフォーマンス改善のための設定
      configure = function(_, opts)
        -- より高速なターミナルタイプを設定
        if vim.fn.has("mac") == 1 then
          vim.env.TERM = "xterm-256color"
        end
      end,
    },
  },
}
