#!/bin/bash
set -e -o pipefail

sudo apt install npm sudo apt lua5.3 liblua5.3-dev libev-dev luarocks -y
# Install rocks system wide as in a local installation busted can't find luacov
sudo luarocks install copas
sudo luarocks install luafilesystem
sudo luarocks install busted
sudo luarocks install luacov
sudo luarocks install luacov-html
sudo luarocks install luaposix
# Install globally to keep node_modules away from project directory
sudo npm i -g @wolfe-labs/du-luac
# Give us ownership of node_modules
sudo chown -R $USER /usr/local/lib/node_modules