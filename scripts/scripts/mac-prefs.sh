#!/bin/bash
echo "Applying macOS Settings..."

# --- UI & ANIMATIONS ---
# Note: Kills the nauseating window resize animation
defaults write -g NSWindowResizeTime -float 0.001

# Note: Removes the artificial delay before the Dock appears
defaults write com.apple.dock autohide-delay -float 0

# Note: Removes the slide-up animation of the Dock entirely
defaults write com.apple.dock autohide-time-modifier -float 0

# --- ACCESSIBILITY ---
# Note: Enabling 'Reduce Motion' (This is a complex boolean flag in the UI, 
# but writing it to defaults looks like this)
defaults write com.apple.universalaccess reduceMotion -bool true

# Apply changes
killall Dock
killall WindowServer

echo "Done."
