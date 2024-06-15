#!/bin/bash

mkdir -p $HOME/.ssh/
op read "op://dev/id_henry/public key" > $HOME/.ssh/sshkey.pub
op read "op://dev/id_henry/private key" > $HOME/.ssh/sshkey

op read "op://dev/id_henry/public key" > $HOME/.ssh/henry.pub
op read "op://dev/id_henry/private key" > $HOME/.ssh/henry

op read "op://dev/wpwebs/public key" > $HOME/.ssh/wpwebs.pub
op read "op://dev/wpwebs/private key" > $HOME/.ssh/wpwebs

op read "op://dev/thesimonus/public key" > $HOME/.ssh/thesimonus.pub
op read "op://dev/thesimonus/private key" > $HOME/.ssh/thesimonus

op read "op://dev/id_thexglobal/public key" > $HOME/.ssh/thexglobal.pub
op read "op://dev/id_thexglobal/private key" > $HOME/.ssh/thexglobal

chmod 700 $HOME/.ssh
chmod 600 $HOME/.ssh/*
chmod 644 $HOME/.ssh/*.pub

echo "\nalias repo_init='infra/terminal/repo_init.sh'" >> $HOME/.zshrc

cat >> $HOME/.ssh/config <<'EOF'


Host henrygithub
    HostName github.com
    User henrysimonfamily
    IdentityFile "$HOME/.ssh/henry"

Host github.com
    HostName github.com
    User henrysimonfamily
    IdentityFile "$HOME/.ssh/henry"

Host thesimonus
    HostName github.com
    User thesimonus
    IdentityFile "$HOME/.ssh/thesimonus"

Host wpwebs
    HostName github.com
    User wpwebs
    IdentityFile "$HOME/.ssh/wpwebs"

Host thexgithub
    HostName github.com
    User thexglobal
    IdentityFile "$HOME/.ssh/thexglobal"

Host *
    AddKeysToAgent yes
    UseKeychain yes
    IdentityFile "$HOME/.ssh/sshkey"

EOF