vim.opt.smartcase = true
vim.opt.breakindent = true

-- Translated from .vimrc
vim.keymap.set('i', 'jk', '<ESC>')
vim.keymap.set('n', '<C-h>', ':noh<CR>')
vim.keymap.set('n', '<C-_>', '/\\C')
vim.opt.number = true
vim.opt.ignorecase = true
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = true
vim.opt.smartindent = true

-- vim.g.mapleader = ','

-- neovim-specific configs
vim.keymap.set({'n', 'x'}, 'cp', '"+y') -- Copy to system clipboard
vim.keymap.set({'n', 'x'}, 'cv', '"+p') -- Paste from system clipboard
vim.keymap.set({'n', 'x'}, 'x', '"_x')  -- Delete via 'x' without overwriting clipboard register

--
-- Plugins
--

local install_path = vim.fn.stdpath('data') .. '/site/pack/packer/start/packer.nvim'
local install_plugins = false

if vim.fn.empty(vim.fn.glob(install_path)) > 0 then
    print('Installing packer...')
    local packer_url = 'https://github.com/wbthomason/packer.nvim'
    vim.fn.system({'git', 'clone', '--depth', '1', packer_url, install_path})
    print('Done.')

    vim.cmd('packadd packer.nvim')
    install_plugins = true
end

require('packer').startup(function(use)

    -- Package manager - packer can now update itself
    use 'wbthomason/packer.nvim'

    -- Theme inspired by Atom
    use 'joshdick/onedark.vim'

    -- Slick status line
    use 'nvim-lualine/lualine.nvim'


    if install_plugins then
        require('packer').sync()
    end
end)

-- If plugins are being installed, exit & re-enter
-- so that we can properly configure on next time
if install_plugins then
    return
end

-- Use default config
require('lualine').setup()


-- onedark config
vim.opt.termguicolors = true
vim.cmd('colorscheme onedark')
