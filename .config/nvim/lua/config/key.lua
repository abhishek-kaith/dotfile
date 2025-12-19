-- Leader Key Configuration
vim.g.mapleader = " "      -- Use <space> as the leader key
vim.g.maplocalleader = " " -- Same for local leader

-- Remove Search Highlight  See `:help hlsearch`
vim.keymap.set("n", "<Esc>", "<cmd>nohlsearch<CR>")

-- Update Neovim
vim.keymap.set("n", "<leader>o", ":update<CR> :source<CR>")

-- Fzf
vim.api.nvim_set_keymap("n", "<C-\\>", [[<Cmd>lua require"fzf-lua".buffers()<CR>]], {})
vim.api.nvim_set_keymap("n", "<C-k>", [[<Cmd>lua require"fzf-lua".builtin()<CR>]], {})
vim.api.nvim_set_keymap("n", "<C-p>", [[<Cmd>lua require"fzf-lua".files()<CR>]], {})
vim.api.nvim_set_keymap("n", "<C-l>", [[<Cmd>lua require"fzf-lua".live_grep()<CR>]], {})
vim.api.nvim_set_keymap("n", "<C-g>", [[<Cmd>lua require"fzf-lua".grep_project()<CR>]], {})
vim.api.nvim_set_keymap("n", "<F1>", [[<Cmd>lua require"fzf-lua".help_tags()<CR>]], {})

-- Grapple
vim.keymap.set("n", "<leader>a", ":lua require('grapple').toggle()<CR>")
vim.keymap.set("n", "<C-e>", ":lua require('grapple').toggle_tags()<CR>")

-- Lsp
vim.keymap.set("n", "gd", ":lua vim.lsp.buf.definition()<CR>", { desc = "Go to definition" })
vim.keymap.set("n", "gD", ":lua vim.lsp.buf.declaration()<CR>", { desc = "Go to declaration" })
vim.keymap.set("n", "gi", ":lua vim.lsp.buf.implementation()<CR>", { desc = "Go to implementation" })
vim.keymap.set("n", "gr", ":lua vim.lsp.buf.references()<CR>", { desc = "List references" })
vim.keymap.set("n", "<leader>rn", ":lua vim.lsp.buf.rename()<CR>", { desc = "Rename symbol" })
vim.keymap.set("n", "<leader>ca", ":lua vim.lsp.buf.code_action()<CR>", { desc = "Code action" })
vim.keymap.set("n", "<leader>q", ":lua vim.diagnostic.setloclist()<CR>", { desc = "Set quickfix list" })
vim.keymap.set("n", "<leader>f", ":lua vim.lsp.buf.format({ async = true })<CR>", { desc = "Format buffer" })

local diagnostic_float_win = nil
local function toggle_diagnostic_float()
  local api = vim.api
  if diagnostic_float_win and api.nvim_win_is_valid(diagnostic_float_win) then
    api.nvim_set_current_win(diagnostic_float_win)
  else
    local bufnr = api.nvim_get_current_buf()
    local opts = { focus = false }
    ---@diagnostic disable-next-line: param-type-mismatch
    vim.diagnostic.open_float(bufnr, opts)
    local wins = api.nvim_tabpage_list_wins(0)
    for _, w in ipairs(wins) do
      local config = api.nvim_win_get_config(w)
      if config.relative ~= '' then
        diagnostic_float_win = w
        break
      end
    end
  end
end

vim.keymap.set("n", "<leader>e", toggle_diagnostic_float, { desc = "Toggle diagnostic float and focus" })

--  Use CTRL+<hjkl> to switch between windows
--  See `:help wincmd` for a list of all window commands
vim.keymap.set("n", "<C-h>", "<C-w><C-h>", { desc = "Move focus to the left window" })
vim.keymap.set("n", "<C-l>", "<C-w><C-l>", { desc = "Move focus to the right window" })
vim.keymap.set("n", "<C-j>", "<C-w><C-j>", { desc = "Move focus to the lower window" })
vim.keymap.set("n", "<C-k>", "<C-w><C-k>", { desc = "Move focus to the upper window" })

-- Highlight when yanking (copying) text
vim.api.nvim_create_autocmd("TextYankPost", {
  desc = "Highlight when yanking (copying) text",
  group = vim.api.nvim_create_augroup("kickstart-highlight-yank", { clear = true }),
  callback = function()
    vim.highlight.on_yank()
  end,
})

-- Move Code
vim.keymap.set("v", "J", ":m '>+1<CR>gv=gv")
vim.keymap.set("v", "K", ":m '<-2<CR>gv=gv")

-- Indenting
vim.keymap.set("v", "<", "<gv")
vim.keymap.set("v", ">", ">gv")

-- Overide default when centering
vim.keymap.set("n", "J", "mzJ`z")
vim.keymap.set("n", "<C-d>", "<C-d>zz")
vim.keymap.set("n", "<C-u>", "<C-u>zz")
vim.keymap.set("n", "n", "nzzzv")
vim.keymap.set("n", "N", "Nzzzv")
