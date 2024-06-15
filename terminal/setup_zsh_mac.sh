#!/bin/bash

# Install Homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install necessary packages
brew install zsh git 1password-cli

# Install Oh My Zsh
sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" --unattended

# Install Zsh plugins and Powerlevel10k theme
git clone https://github.com/zsh-users/zsh-autosuggestions ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-completions ~/.oh-my-zsh/custom/plugins/zsh-completions
git clone https://github.com/zsh-users/zsh-syntax-highlighting ~/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting
git clone https://github.com/romkatv/powerlevel10k.git ~/.oh-my-zsh/custom/themes/powerlevel10k

# Install iTerm2
brew install --cask iterm2

# Enable iTerm2 Shell Integration
curl -L https://iterm2.com/shell_integration/install_shell_integration_and_utilities.sh | bash

# # Import the profile from JSON
# PROFILE_JSON_PATH="./default.json"
# ITERM2_PROFILE_KEY="Default"
# ITERM2_PREFS_DIR="${HOME}/Library/Preferences/com.googlecode.iterm2.plist"
# /usr/libexec/PlistBuddy -c "Merge $PROFILE_JSON_PATH $ITERM2_PROFILE_KEY" "$ITERM2_PREFS_DIR"

# /usr/libexec/PlistBuddy -c "Merge ./default.json Default" ${HOME}/Library/Preferences/com.googlecode.iterm2.plist

# cp "$ITERM2_PREFS_DIR" "$ITERM2_PREFS_DIR.backup"


# Setup SSH keys
mkdir -p $HOME/.ssh/
op read "op://dev/id_henry/public key" > $HOME/.ssh/sshkey.pub
op read "op://dev/id_henry/private key" > $HOME/.ssh/sshkey
chmod 700 $HOME/.ssh
chmod 644 $HOME/.ssh/sshkey.pub
chmod 600 $HOME/.ssh/sshkey

# Download and install fonts
cd ~/Library/Fonts && { 
    wget https://github.com/romkatv/dotfiles-public/raw/master/.local/share/fonts/NerdFonts/MesloLGS%20NF%20Regular.ttf 
    wget https://github.com/romkatv/dotfiles-public/raw/master/.local/share/fonts/NerdFonts/MesloLGS%20NF%20Bold%20Italic.ttf 
    wget https://github.com/romkatv/dotfiles-public/raw/master/.local/share/fonts/NerdFonts/MesloLGS%20NF%20Bold.ttf 
    wget https://github.com/romkatv/dotfiles-public/raw/master/.local/share/fonts/NerdFonts/MesloLGS%20NF%20Italic.ttf 
    cd -; 
}

echo "Installing terminal fonts:"
cp ./fonts/*.ttf ~/Library/Fonts/

# Open and close iTerm2 to apply changes
open /Applications/iTerm.app/
sleep 1
killall iTerm2

# Customize iTerm2: Fonts, Window size, and Background Transparency
/usr/libexec/PlistBuddy -c "Set :\"New Bookmarks\":0:\"Normal Font\" \"MesloLGS-NF-Regular 12\""  ~/Library/Preferences/com.googlecode.iterm2.plist
/usr/libexec/PlistBuddy -c "Set :\"New Bookmarks\":0:\"Non Ascii Font\" \"MesloLGS-NF-Regular 12\""  ~/Library/Preferences/com.googlecode.iterm2.plist
/usr/libexec/PlistBuddy -c "Set :\"New Bookmarks\":0:\"Columns\" 141"  ~/Library/Preferences/com.googlecode.iterm2.plist
/usr/libexec/PlistBuddy -c "Set :\"New Bookmarks\":0:\"Rows\" 33"  ~/Library/Preferences/com.googlecode.iterm2.plist
/usr/libexec/PlistBuddy -c "Set :\"New Bookmarks\":0:\"Transparency\" 0.18"  ~/Library/Preferences/com.googlecode.iterm2.plist

# Append custom prompt and Zsh configuration to .zshrc
append_to_zshrc="$(cat <<'EOF'

# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# Source iTerm2 shell integration
source ~/.iterm2_shell_integration.zsh

# Source Zsh plugins and Powerlevel10k theme
source ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
source ~/.oh-my-zsh/custom/plugins/zsh-completions/zsh-completions.plugin.zsh
source ~/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
source ~/.oh-my-zsh/custom/themes/powerlevel10k/powerlevel10k.zsh-theme

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# Set Zsh as the default shell
sudo chsh -s $(which zsh) $USER
# Allow execute sudo commands without being prompted for a password
echo "$USER ALL=(ALL) NOPASSWD: ALL" | sudo tee -a /etc/sudoers.d/$USER


# Export OP_SERVICE_ACCOUNT_TOKEN for 1Password CLI
echo "export OP_SERVICE_ACCOUNT_TOKEN='token'" >> $HOME/.zshrc

# Start SSH agent and add key
eval "$(ssh-agent -s)" 
chmod 600 $HOME/.ssh/sshkey
ssh-add $HOME/.ssh/sshkey

EOF
)"
printf "%s\n" "$append_to_zshrc" >> ~/.zshrc

# Clear terminal
clear
