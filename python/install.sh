#!/bin/sh

if test ! $(command which pyenv)
then
  echo "  Installing pyenv for you."
  brew install pyenv > /tmp/pyenv-install.log
fi
