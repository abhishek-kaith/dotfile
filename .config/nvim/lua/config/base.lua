-- Interface Settings
vim.opt.number = true -- Show absolute line numbers
vim.opt.relativenumber = true -- Show relative line numbers
vim.opt.cursorline = true -- Highlight current line
vim.wo.signcolumn = "yes" -- Always show signcolumn (for Git, LSP, etc.)
vim.opt.wrap = false -- Don't wrap long lines
vim.opt.scrolloff = 10 -- Minimum lines above/below cursor
vim.opt.colorcolumn = "80" -- Style Guide Vertical Line to guide lenght of code

-- Visuals & Characters
vim.o.termguicolors = true -- Enable full RGB color support
vim.opt.list = true -- Show invisible characters
vim.opt.listchars = {
	tab = "» ", -- Show tabs as »
	trail = "·", -- Show trailing spaces
	nbsp = "␣", -- Show non-breaking space
}

-- Tabs & Indentation
vim.o.tabstop = 2 -- Tab character = 2 spaces (visually)
vim.o.expandtab = true -- Pressing <Tab> inserts spaces
vim.o.softtabstop = 2 -- Tab key = 2 spaces
vim.o.shiftwidth = 2 -- Indentation = 2 spaces
vim.o.breakindent = true -- Indent wrapped lines properly

-- Search Behavior
vim.o.hlsearch = true -- Don't highlight matches by default
vim.o.ignorecase = true -- Ignore case when searching...
vim.o.smartcase = true -- ...unless capital letters are used

-- Clipboard & Undo
vim.o.clipboard = "unnamedplus" -- Use system clipboard (works with Ctrl+C / Ctrl+V)
vim.o.undofile = true -- Save undo history to disk
vim.o.swapfile = false -- Disable swap file

-- Mouse & Splits
vim.o.mouse = "a" -- Enable mouse in all modes
vim.opt.splitright = true -- Vertical splits open to the right
vim.opt.splitbelow = true -- Horizontal splits open below

-- Command Behavior
vim.opt.inccommand = "split" -- Show live preview of substitutions eg. %s/foo/bar/g open new split at bottom with live preview
vim.o.completeopt = "menuone,noselect" -- Better completion experience

-- Performance Tweaks
vim.o.updatetime = 250 -- Faster CursorHold, LSP updates, etc.
vim.o.timeoutlen = 300 -- Timeout for mapped sequence

-- =========================
-- Lazy.nvim bootstrap
-- =========================
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
	vim.fn.system({
		"git",
		"clone",
		"--filter=blob:none",
		"https://github.com/folke/lazy.nvim.git",
		"--branch=stable",
		lazypath,
	})
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
	{
		"vague2k/vague.nvim",
		lazy = false,
		priority = 1000,
		config = function()
			vim.cmd.colorscheme("vague")
			-- transparent-ish UI
			-- vim.api.nvim_set_hl(0, "Normal", { bg = "NONE" })
			-- vim.api.nvim_set_hl(0, "NormalFloat", { bg = "NONE" })
			-- vim.api.nvim_set_hl(0, "SignColumn", { bg = "NONE" })
			-- vim.api.nvim_set_hl(0, "StatusLine", { bg = "NONE" })
		end,
	},

	----------------------------------------------------------------------
	-- NAVIGATION
	----------------------------------------------------------------------
	{
		"ibhagwan/fzf-lua",
		dependencies = { "nvim-tree/nvim-web-devicons" },
		config = function()
			require("fzf-lua").setup({ "fzf-native" })
		end,
	},

	{
		"cbochs/grapple.nvim",
		config = function()
			require("grapple").setup({ icons = false })
		end,
	},

	----------------------------------------------------------------------
	-- LSP + MASON
	----------------------------------------------------------------------
	{
		"neovim/nvim-lspconfig",
	},

	{
		"mason-org/mason.nvim",
		config = true,
	},

	{
		"mason-org/mason-lspconfig.nvim",
		dependencies = { "mason-org/mason.nvim", "neovim/nvim-lspconfig" },
		config = function()
			require("mason-lspconfig").setup()
		end,
	},

	{
		"WhoIsSethDaniel/mason-tool-installer.nvim",
		dependencies = { "mason-org/mason.nvim" },
		config = function()
			require("mason-tool-installer").setup({
				ensure_installed = {
					"lua_ls",
					"stylua",
					"ts_ls",
					"tailwindcss",
					"clangd",
				},
			})
		end,
	},

	----------------------------------------------------------------------
	-- AUTOCOMPLETE + SNIPPETS
	----------------------------------------------------------------------
	{
		"Saghen/blink.cmp",
		version = "v1.6.0",
		dependencies = {
			"L3MON4D3/LuaSnip",
			"rafamadriz/friendly-snippets",
		},
		config = function()
			require("luasnip.loaders.from_vscode").lazy_load()

			require("blink.cmp").setup({
				signature = { enabled = true },
				completion = {
					documentation = {
						auto_show = true,
						auto_show_delay_ms = 500,
					},
					menu = {
						auto_show = true,
						draw = {
							treesitter = { "lsp" },
							columns = {
								{ "kind_icon", "label", "label_description", gap = 1 },
								{ "kind" },
							},
						},
					},
				},
			})
		end,
	},

	----------------------------------------------------------------------
	-- TREESITTER
	----------------------------------------------------------------------
	{
		"nvim-treesitter/nvim-treesitter",
		opts = function(_, opts)
			opts.auto_install = true

			opts.highlight = opts.highlight or {}
			opts.highlight.enable = true
			opts.highlight.disable = function(_, buf)
				local max_filesize = 100 * 1024 -- 100 KB
				local ok, stats = pcall(vim.loop.fs_stat, vim.api.nvim_buf_get_name(buf))
				return ok and stats and stats.size > max_filesize
			end

			opts.incremental_selection = {
				enable = true,
				keymaps = {
					init_selection = "<C-space>",
					node_incremental = "<C-space>",
					node_decremental = "<bs>",
				},
			}
		end,
	},
	----------------------------------------------------------------------
	-- GIT
	----------------------------------------------------------------------
	{
		"lewis6991/gitsigns.nvim",
		config = true,
	},
})

-- =========================
-- LSP server config
-- =========================
vim.lsp.config("lua_ls", {
	settings = {
		Lua = {
			runtime = { version = "LuaJIT" },
			diagnostics = { globals = { "vim", "require" } },
			workspace = {
				library = vim.api.nvim_get_runtime_file("", true),
			},
			telemetry = { enable = false },
		},
	},
})
