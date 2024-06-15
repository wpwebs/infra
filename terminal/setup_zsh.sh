#!/bin/sh

# Install Oh My Zsh
sudo apt-get update
sudo apt-get install -y zsh git curl 
0>/dev/null sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" --unattended

# Install zsh-autosuggestions, zsh-completions, zsh-syntax-highlighting, powerlevel10k theme
git clone https://github.com/zsh-users/zsh-autosuggestions $HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-completions $HOME/.oh-my-zsh/custom/plugins/zsh-completions
git clone https://github.com/zsh-users/zsh-syntax-highlighting $HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting
git clone https://github.com/romkatv/powerlevel10k.git $HOME/.oh-my-zsh/custom/themes/powerlevel10k

curl https://raw.githubusercontent.com/wpwebs/dev_container_docker_compose/main/.dot_files/.p10k.zsh > p10k.zsh ; mv p10k.zsh ~/.p10k.zsh

# Setting timezene to PDT
sudo cp /usr/share/zoneinfo/US/Pacific /etc/localtime

# Customize PROMPT 
append_to_zshrc="$(cat <<'EOF'

# Enable Powerlevel10k instant prompt. Should stay close to the top of $HOME/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

source $HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
source $HOME/.oh-my-zsh/custom/plugins/zsh-completions/zsh-completions.plugin.zsh
source $HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
source $HOME/.oh-my-zsh/custom/themes/powerlevel10k/powerlevel10k.zsh-theme

# To customize prompt, run `p10k configure` or edit $HOME/.p10k.zsh.
[[ ! -f $HOME/.p10k.zsh ]] || source $HOME/.p10k.zsh

eval "$(ssh-agent -s)" 
chmod 600 $HOME/.ssh/sshkey
ssh-add $HOME/.ssh/sshkey

# Set Zsh As Your Default Shell
command -v zsh | sudo tee -a /etc/shells
sudo chsh -s $(which zsh) $USER

clear

EOF
)"
printf "%s\n" "$append_to_zshrc" >> $HOME/.zshrc

rm setup_zsh.sh

0>/dev/null zsh
