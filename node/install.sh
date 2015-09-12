#!/bin/sh

if test ! $(nvm --version)
then
  echo "  Installing nvm for you."
  brew install nvm > /tmp/nvm-install.log
  mkdir ~/.nvm
  cp $(brew --prefix nvm)/nvm-exec ~/.nvm
fi
