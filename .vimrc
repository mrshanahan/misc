inoremap jk <ESC>
set shiftwidth=4
set tabstop=4
set expandtab
set nu
set smartindent
syntax on
set list
set lcs=tab:·\ ,trail:~

" Cleans up trailing whitespace
command CleanWS :%s/\s\+$//g

" Converts tabs to spaces
command TabsToSpaces :%s/\t/    /g

" Converts spaces to tabs
command SpacesToTabs :%s/    /\t/g
