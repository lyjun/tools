After installed nvim configuration, do these

[ 1. install extra binary ]
1. install lsp via mason
Execute this command in nvim environment
:MasonInstall
or run this command and use manage UI to install/uninstall
:Mason

2. install treesitter
:TSUpdate or :TSInstall

3. install extra binary "ripgrep" for telescope

[ 2. revise plugin setting ]
1. mason.lau
to add/remove built-in lsp if you need

2. nvim-cmp.lua
revise auto completion for your language server(lsp) if you need

[ truble shooting ]
1. if you have trouble with these messages "E319: No "python3" provider found". Usually, it's ocurred on macos.

  Execute this command in you environment
    pip3 install --user --upgrade neovim


[[ TODO ]] 
1. integrate lint with mason
2. formatters install via mason or manully from mason UI
3. (?)use other git plugin instead of net-git
4. DAP add this feature(?)
   - https://github.com/rcarriga/nvim-dap-ui
   - https://github.com/mfussenegger/nvim-dap
