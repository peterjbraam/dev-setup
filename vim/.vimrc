" --- Basic UI ---
set nocompatible
set number              " line numbers
set relativenumber      " relative line numbers
set cursorline          " highlight current line
syntax on               " syntax highlighting
set termguicolors       " enable 24-bit color if terminal supports it

" --- Mouse support ---
set mouse=a             " enable mouse in all modes

" --- Clipboard integration ---
set clipboard=unnamedplus   " use system clipboard by default

" --- Indentation & tabs ---
set expandtab           " insert spaces instead of tab characters
set shiftwidth=4        " number of spaces to indent
set softtabstop=4
set tabstop=4
set smartindent

" --- Search ---
set ignorecase
set smartcase
set hlsearch
set incsearch

" --- Status line ---
set laststatus=2
set showmode
set showcmd

" --- Backups & swaps ---
set nobackup
set nowritebackup
set noswapfile          " disable swap files

" --- File encodings ---
set encoding=utf-8
set fileencodings=utf-8,latin1

" --- Split window behavior ---
set splitbelow
set splitright

" --- Key mappings (clipboard helpers) ---
" Yank to system clipboard with <Leader>y
nmap <Leader>y "+y
vmap <Leader>y "+y

" Paste from system clipboard with <Leader>p
nmap <Leader>p "+p
vmap <Leader>p "+p

" --- Colorscheme ---
colorscheme koehler

" --- Filetype specific overrides ---
" Enable filetype detection, plugins, and indenting
filetype plugin indent on

" Override global expandtab for Makefiles (mandate hard tabs)
autocmd FileType make setlocal noexpandtab shiftwidth=8 softtabstop=0