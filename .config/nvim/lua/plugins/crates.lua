return {
  "saecki/crates.nvim",
  event = { "BufRead Cargo.toml" },
  dependencies = { "nvim-lua/plenary.nvim" },
  config = function()
    require("crates").setup({
      popup = {
        autofocus = true,
        border = "rounded",
      },
      lsp = {
        enabled = true,
        actions = true,
        completion = true,
        hover = true,
      },
    })
  end,
}
