return {
  "ray-x/go.nvim",
  dependencies = {
    "ray-x/guihua.lua",
    "neovim/nvim-lspconfig",
    "nvim-treesitter/nvim-treesitter",
  },
  config = function()
    require("go").setup({
      -- LSP設定はLazyVim Go extrasに任せる
      lsp_cfg = false, -- LazyVimのgopls設定を使用
      lsp_keymaps = false, -- LazyVimのキーマップを使用
      lsp_codelens = false, -- LazyVim側で設定済み

      -- go.nvim独自の機能を有効化
      -- テスト関連
      test_runner = "go", -- デフォルトのテストランナー
      run_in_floaterm = true, -- フローティングターミナルで実行

      -- デバッガー
      dap_debug = true, -- DAP統合有効化
      dap_debug_keymap = true, -- デバッグキーマップ有効化

      -- コード生成・リファクタリング
      fillstruct = "gopls", -- 構造体フィールド自動補完
      tag_transform = "camelcase", -- 構造体タグの変換形式

      -- その他の統合
      trouble = true, -- trouble.nvim統合
      luasnip = false, -- luasnip統合を無効化（LazyVimで管理）
    })
  end,
  event = { "CmdlineEnter" },
  ft = { "go", "gomod" },
  build = ':lua require("go.install").update_all_sync()',
}
