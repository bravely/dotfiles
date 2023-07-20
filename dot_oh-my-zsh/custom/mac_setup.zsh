mac_vscode_setup() {
  print "From https://stackoverflow.com/a/69806016"
  print Setting ApplePressAndHold for VS Code
  defaults write com.microsoft.VSCode ApplePressAndHoldEnabled -bool false
  print Setting ApplePressAndHold for VS Code Insider
  defaults write com.microsoft.VSCodeInsiders ApplePressAndHoldEnabled -bool false
  print Setting ApplePressAndHold for VS Codium
  defaults write com.visualstudio.code.oss ApplePressAndHoldEnabled -bool false
  # If necessary, reset global default
  print "If anything doesn't work as expected, try: 'defaults delete -g ApplePressAndHoldEnabled'"

}
