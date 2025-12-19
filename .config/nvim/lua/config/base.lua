-- Interface Settings
vim.opt.number = true         -- Show absolute line numbers
vim.opt.relativenumber = true -- Show relative line numbers
vim.opt.cursorline = true     -- Highlight current line
vim.wo.signcolumn = "yes"     -- Always show signcolumn (for Git, LSP, etc.)
vim.opt.wrap = false          -- Don't wrap long lines
vim.opt.scrolloff = 10        -- Minimum lines above/below cursor
vim.opt.colorcolumn = "80"    -- Style Guide Vertical Line to guide lenght of code

-- Visuals & Characters
vim.o.termguicolors = true -- Enable full RGB color support
vim.opt.list = true -- Show invisible characters
vim.opt.listchars = {
  tab = "» ", -- Show tabs as »
  trail = "·", -- Show trailing spaces
  nbsp = "␣", -- Show non-breaking space
}

-- Tabs & Indentation
vim.o.tabstop = 2        -- Tab character = 2 spaces (visually)
vim.o.expandtab = true   -- Pressing <Tab> inserts spaces
vim.o.softtabstop = 2    -- Tab key = 2 spaces
vim.o.shiftwidth = 2     -- Indentation = 2 spaces
vim.o.breakindent = true -- Indent wrapped lines properly

-- Search Behavior
vim.o.hlsearch = true   -- Don't highlight matches by default
vim.o.ignorecase = true -- Ignore case when searching...
vim.o.smartcase = true  -- ...unless capital letters are used

-- Clipboard & Undo
vim.o.clipboard = "unnamedplus" -- Use system clipboard (works with Ctrl+C / Ctrl+V)
vim.o.undofile = true           -- Save undo history to disk
vim.o.swapfile = false          -- Disable swap file

-- Mouse & Splits
vim.o.mouse = "a"         -- Enable mouse in all modes
vim.opt.splitright = true -- Vertical splits open to the right
vim.opt.splitbelow = true -- Horizontal splits open below

-- Command Behavior
vim.opt.inccommand =
"split"                                -- Show live preview of substitutions eg. %s/foo/bar/g open new split at bottom with live preview
vim.o.completeopt = "menuone,noselect" -- Better completion experience

-- Performance Tweaks
vim.o.updatetime = 250 -- Faster CursorHold, LSP updates, etc.
vim.o.timeoutlen = 300 -- Timeout for mapped sequence
