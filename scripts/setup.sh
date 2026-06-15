#!/usr/bin/env bash
# =============================================================================
# FLAWLESS DEV ENVIRONMENT SETUP
# Remote server bootstrap script — Blink Shell · iPhone-first workflow
# github.com/flawlessstudio/flawless-dotfiles
#
# Tested on: Ubuntu 22.04 / 24.04 LTS · Debian 12 · macOS 14+
# Run as: bash <(curl -fsSL https://raw.githubusercontent.com/flawlessstudio/flawless-dotfiles/main/scripts/setup.sh)
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

log()  { echo -e "${CYAN}${BOLD}[flawless]${RESET} $*"; }
ok()   { echo -e "${GREEN}✓${RESET} $*"; }
warn() { echo -e "${YELLOW}⚠${RESET}  $*"; }
err()  { echo -e "${RED}✗${RESET} $*" >&2; }
sep()  { echo -e "${BLUE}────────────────────────────────────────────────────${RESET}"; }

# ── Detect OS ─────────────────────────────────────────────────────────────────
detect_os() {
  if [[ "$OSTYPE" == "darwin"* ]]; then
    OS="macos"
  elif [[ -f /etc/debian_version ]]; then
    OS="debian"
  elif [[ -f /etc/fedora-release ]]; then
    OS="fedora"
  elif [[ -f /etc/arch-release ]]; then
    OS="arch"
  else
    OS="unknown"
  fi
  log "Detected OS: ${BOLD}${OS}${RESET}"
}

# ── Package installer wrapper ─────────────────────────────────────────────────
pkg_install() {
  case "$OS" in
    macos)   brew install "$@" 2>/dev/null || warn "brew: $* — check manually" ;;
    debian)  sudo apt-get install -y "$@" 2>/dev/null || warn "apt: $* — check manually" ;;
    fedora)  sudo dnf install -y "$@" 2>/dev/null || warn "dnf: $* — check manually" ;;
    arch)    sudo pacman -S --noconfirm "$@" 2>/dev/null || warn "pacman: $* — check manually" ;;
    *)       err "Unknown OS — install manually: $*" ;;
  esac
}

# ═════════════════════════════════════════════════════════════════════════════
# PHASE 0 — System prerequisites
# ═════════════════════════════════════════════════════════════════════════════
phase_0_prerequisites() {
  sep
  log "PHASE 0 — System prerequisites"

  case "$OS" in
    macos)
      if ! command -v brew &>/dev/null; then
        log "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
      else
        ok "Homebrew already installed"
      fi
      brew update --quiet
      ;;
    debian)
      sudo apt-get update -qq
      sudo apt-get install -y curl wget git build-essential ca-certificates gnupg lsb-release
      ;;
    fedora)
      sudo dnf update -y -q
      sudo dnf install -y curl wget git gcc gcc-c++ make
      ;;
    arch)
      sudo pacman -Syu --noconfirm
      sudo pacman -S --noconfirm base-devel curl wget git
      ;;
  esac
  ok "Prerequisites ready"
}

# ═════════════════════════════════════════════════════════════════════════════
# PHASE 1 — Core shell toolchain
# ═════════════════════════════════════════════════════════════════════════════
phase_1_shell() {
  sep
  log "PHASE 1 — Core shell toolchain"

  if ! command -v zsh &>/dev/null; then
    log "Installing zsh..."
    pkg_install zsh
  else
    ok "zsh $(zsh --version | awk '{print $2}')"
  fi

  if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
    log "Installing Oh My Zsh..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    ok "Oh My Zsh installed"
  else
    ok "Oh My Zsh already present"
  fi

  ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

  _clone_plugin() {
    local name="$1" url="$2"
    local dir="$ZSH_CUSTOM/plugins/$name"
    if [[ ! -d "$dir" ]]; then
      git clone --depth=1 "$url" "$dir"
      ok "Plugin: $name"
    else
      ok "Plugin already present: $name"
    fi
  }

  _clone_plugin zsh-autosuggestions     https://github.com/zsh-users/zsh-autosuggestions
  _clone_plugin zsh-syntax-highlighting https://github.com/zsh-users/zsh-syntax-highlighting
  _clone_plugin zsh-completions         https://github.com/zsh-users/zsh-completions
  _clone_plugin zsh-history-substring-search https://github.com/zsh-users/zsh-history-substring-search
  _clone_plugin you-should-use          https://github.com/MichaelAquilina/zsh-you-should-use

  if ! command -v starship &>/dev/null; then
    log "Installing Starship prompt..."
    curl -sS https://starship.rs/install.sh | sh -s -- --yes
    ok "Starship installed"
  else
    ok "Starship $(starship --version | head -1)"
  fi

  if [[ "$SHELL" != "$(command -v zsh)" ]]; then
    log "Setting zsh as default shell..."
    chsh -s "$(command -v zsh)" || warn "Run manually: chsh -s $(command -v zsh)"
  fi

  ok "Phase 1 complete"
}

# ═════════════════════════════════════════════════════════════════════════════
# PHASE 2 — tmux
# ═════════════════════════════════════════════════════════════════════════════
phase_2_tmux() {
  sep
  log "PHASE 2 — tmux"

  if ! command -v tmux &>/dev/null; then
    pkg_install tmux
  else
    ok "tmux $(tmux -V)"
  fi

  if [[ ! -d "$HOME/.tmux/plugins/tpm" ]]; then
    git clone --depth=1 https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
    ok "TPM installed"
  else
    ok "TPM already present"
  fi

  cat > "$HOME/.tmux.conf" << 'TMUXCONF'
# Flawless tmux config — iPhone Blink Shell optimized
set -g default-terminal "tmux-256color"
set -ag terminal-overrides ",xterm-256color:RGB"
set -g mouse on
set -g base-index 1
setw -g pane-base-index 1
set -g renumber-windows on
set -g history-limit 50000
set -g display-time 4000
set -g status-interval 5
set -g focus-events on
setw -g aggressive-resize on

unbind C-b
set -g prefix C-Space
bind C-Space send-prefix

bind h select-pane -L
bind j select-pane -D
bind k select-pane -U
bind l select-pane -R

bind | split-window -h -c "#{pane_current_path}"
bind - split-window -v -c "#{pane_current_path}"
bind c new-window -c "#{pane_current_path}"
bind r source-file ~/.tmux.conf \; display "Config reloaded"

set -g status-style "bg=#0F1216,fg=#AEB8C5"
set -g status-left "#[fg=#5FBBC2,bold] #S "
set -g status-right "#[fg=#566072] %H:%M  %d %b "
set -g status-left-length 20
set -g status-right-length 40
setw -g window-status-format "#[fg=#566072] #I:#W "
setw -g window-status-current-format "#[fg=#E7EDF5,bold,bg=#1A1F27] #I:#W "
set -g pane-border-style "fg=#1A1F27"
set -g pane-active-border-style "fg=#5FBBC2"
set -g message-style "bg=#1A1F27,fg=#E7EDF5"

set -g @plugin 'tmux-plugins/tpm'
set -g @plugin 'tmux-plugins/tmux-sensible'
set -g @plugin 'tmux-plugins/tmux-resurrect'
set -g @plugin 'tmux-plugins/tmux-continuum'
set -g @plugin 'tmux-plugins/tmux-yank'
set -g @plugin 'christoomey/vim-tmux-navigator'
set -g @continuum-restore 'on'
set -g @resurrect-capture-pane-contents 'on'

run '~/.tmux/plugins/tpm/tpm'
TMUXCONF

  ok "tmux.conf written"
  ~/.tmux/plugins/tpm/bin/install_plugins &>/dev/null && ok "TPM plugins installed" || warn "Run: tmux + prefix+I"
  ok "Phase 2 complete"
}

# ═════════════════════════════════════════════════════════════════════════════
# PHASE 3 — Neovim + LazyVim
# ═════════════════════════════════════════════════════════════════════════════
phase_3_editor() {
  sep
  log "PHASE 3 — Neovim"

  if ! command -v nvim &>/dev/null; then
    case "$OS" in
      macos)   brew install neovim ;;
      debian)
        curl -fLo /tmp/nvim.appimage \
          https://github.com/neovim/neovim/releases/latest/download/nvim.appimage
        chmod +x /tmp/nvim.appimage
        sudo mv /tmp/nvim.appimage /usr/local/bin/nvim
        ;;
      fedora)  sudo dnf install -y neovim ;;
      arch)    sudo pacman -S --noconfirm neovim ;;
    esac
  else
    ok "Neovim $(nvim --version | head -1)"
  fi

  if [[ ! -d "$HOME/.config/nvim" ]]; then
    log "Bootstrapping LazyVim..."
    git clone --depth=1 https://github.com/LazyVim/starter "$HOME/.config/nvim"
    rm -rf "$HOME/.config/nvim/.git"
    ok "LazyVim bootstrapped — run nvim to complete install"
  else
    ok "Neovim config already present"
  fi

  ok "Phase 3 complete"
}

# ═════════════════════════════════════════════════════════════════════════════
# PHASE 4 — Git & SSH
# ═════════════════════════════════════════════════════════════════════════════
phase_4_git_ssh() {
  sep
  log "PHASE 4 — Git & SSH"

  if ! command -v git &>/dev/null; then
    pkg_install git
  else
    ok "git $(git --version | awk '{print $3}')"
  fi

  if ! command -v delta &>/dev/null; then
    case "$OS" in
      macos)   brew install git-delta ;;
      debian)
        DELTA_VERSION=$(curl -s https://api.github.com/repos/dandavison/delta/releases/latest | grep tag_name | cut -d'"' -f4 | tr -d 'v')
        curl -fLo /tmp/delta.deb "https://github.com/dandavison/delta/releases/latest/download/git-delta_${DELTA_VERSION}_amd64.deb"
        sudo dpkg -i /tmp/delta.deb &>/dev/null
        ;;
      fedora|arch) pkg_install git-delta ;;
    esac
    ok "delta installed"
  else
    ok "delta $(delta --version)"
  fi

  cat > "$HOME/.gitconfig" << 'GITCONF'
[core]
  pager = delta
  editor = nvim
[interactive]
  diffFilter = delta --color-only
[delta]
  navigate = true
  light = false
  side-by-side = true
  line-numbers = true
  syntax-theme = base16
[merge]
  conflictstyle = diff3
[diff]
  colorMoved = default
[pull]
  rebase = true
[push]
  autoSetupRemote = true
[alias]
  lg = log --oneline --decorate --graph --all
  st = status -sb
  co = checkout
  br = branch
  ci = commit
  unstage = reset HEAD --
  last = log -1 HEAD
GITCONF
  ok ".gitconfig written"

  if [[ ! -f "$HOME/.ssh/id_ed25519" ]]; then
    log "Generating SSH key (ed25519)..."
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    ssh-keygen -t ed25519 -C "flawless@$(hostname)" -f "$HOME/.ssh/id_ed25519" -N ""
    ok "SSH key generated: ~/.ssh/id_ed25519.pub"
    echo ""
    echo -e "${YELLOW}${BOLD}Your public key:${RESET}"
    cat "$HOME/.ssh/id_ed25519.pub"
  else
    ok "SSH key already exists"
  fi

  if [[ ! -f "$HOME/.ssh/config" ]]; then
    cat > "$HOME/.ssh/config" << 'SSHCONF'
Host *
  ServerAliveInterval 60
  ServerAliveCountMax 3
  ControlMaster auto
  ControlPath ~/.ssh/cm-%r@%h:%p
  ControlPersist 10m
  AddKeysToAgent yes
  IdentityFile ~/.ssh/id_ed25519
SSHCONF
    chmod 600 "$HOME/.ssh/config"
    ok "SSH config written"
  fi

  ok "Phase 4 complete"
}

# ═════════════════════════════════════════════════════════════════════════════
# PHASE 5 — CLI powertools
# ═════════════════════════════════════════════════════════════════════════════
phase_5_cli_tools() {
  sep
  log "PHASE 5 — CLI powertools"

  _install_if_missing() {
    local cmd="$1"; shift
    if ! command -v "$cmd" &>/dev/null; then
      pkg_install "$@"
      ok "$cmd installed"
    else
      ok "$cmd already present"
    fi
  }

  _install_if_missing eza eza
  _install_if_missing bat bat
  _install_if_missing fd  fd-find
  _install_if_missing rg  ripgrep
  _install_if_missing fzf fzf
  _install_if_missing zoxide zoxide
  _install_if_missing dust dust
  _install_if_missing procs procs
  _install_if_missing bottom bottom
  _install_if_missing jq jq
  _install_if_missing yq yq
  _install_if_missing hyperfine hyperfine
  _install_if_missing tokei tokei
  _install_if_missing lazygit lazygit
  _install_if_missing mosh mosh
  _install_if_missing httpie httpie
  _install_if_missing nmap nmap
  _install_if_missing tree tree
  _install_if_missing rsync rsync
  _install_if_missing gh gh

  ok "Phase 5 complete"
}

# ═════════════════════════════════════════════════════════════════════════════
# PHASE 6 — Language runtimes
# ═════════════════════════════════════════════════════════════════════════════
phase_6_runtimes() {
  sep
  log "PHASE 6 — Language runtimes"

  if ! command -v fnm &>/dev/null; then
    log "Installing fnm (Node version manager)..."
    curl -fsSL https://fnm.vercel.app/install | bash -s -- --skip-shell
    export PATH="$HOME/.local/share/fnm:$PATH"
    eval "$(fnm env --use-on-cd 2>/dev/null)" || true
    ok "fnm installed"
  fi
  command -v fnm &>/dev/null && fnm install --lts &>/dev/null && ok "Node LTS installed" || warn "fnm: check manually"

  if ! command -v pyenv &>/dev/null; then
    log "Installing pyenv..."
    curl https://pyenv.run | bash &>/dev/null
    ok "pyenv installed"
  else
    ok "pyenv $(pyenv --version | awk '{print $2}')"
  fi

  if ! command -v rustup &>/dev/null; then
    log "Installing Rust via rustup..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --quiet
    ok "Rust installed"
  else
    ok "Rust $(rustc --version 2>/dev/null | awk '{print $2}')"
  fi

  if ! command -v bun &>/dev/null; then
    log "Installing Bun..."
    curl -fsSL https://bun.sh/install | bash &>/dev/null
    ok "Bun installed"
  else
    ok "Bun $(bun --version 2>/dev/null)"
  fi

  ok "Phase 6 complete"
}

# ═════════════════════════════════════════════════════════════════════════════
# PHASE 7 — .zshrc
# ═════════════════════════════════════════════════════════════════════════════
phase_7_zshrc() {
  sep
  log "PHASE 7 — .zshrc"

  [[ -f "$HOME/.zshrc" ]] && cp "$HOME/.zshrc" "$HOME/.zshrc.bak.$(date +%s)"

  cat > "$HOME/.zshrc" << 'ZSHRC'
# Flawless .zshrc — github.com/flawlessstudio/flawless-dotfiles
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME=""

plugins=(
  git
  zsh-autosuggestions
  zsh-syntax-highlighting
  zsh-completions
  zsh-history-substring-search
  you-should-use
  fzf
  gh
  docker
  kubectl
  tmux
)

source "$ZSH/oh-my-zsh.sh"
eval "$(starship init zsh)"
command -v zoxide &>/dev/null && eval "$(zoxide init zsh)"

export PATH="$HOME/.local/share/fnm:$PATH"
command -v fnm &>/dev/null && eval "$(fnm env --use-on-cd)"

export PYENV_ROOT="$HOME/.pyenv"
[[ -d "$PYENV_ROOT/bin" ]] && export PATH="$PYENV_ROOT/bin:$PATH"
command -v pyenv &>/dev/null && eval "$(pyenv init -)"

[[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"
[[ -d "$HOME/.bun" ]] && export BUN_INSTALL="$HOME/.bun" && export PATH="$BUN_INSTALL/bin:$PATH"

alias ls='eza --icons --group-directories-first'
alias ll='eza -la --icons --group-directories-first --git'
alias lt='eza --tree --icons --level=2'
alias cat='bat --style=plain'
alias find='fd'
alias grep='rg'
alias cd='z'
alias top='btm'
alias du='dust'
alias ps='procs'
alias vim='nvim'
alias vi='nvim'
alias g='git'
alias lg='lazygit'
alias k='kubectl'
alias gs='git status -sb'
alias gd='git diff'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git pull'
alias glog='git log --oneline --decorate --graph --all'

export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
export FZF_DEFAULT_OPTS="
  --height 40% --layout=reverse --border
  --color=bg+:#1A1F27,bg:#0F1216,spinner:#5FBBC2,hl:#E26D77
  --color=fg:#AEB8C5,header:#566072,info:#D8BE84,pointer:#5FBBC2
  --color=marker:#98C379,fg+:#E7EDF5,prompt:#6CA9FF,hl+:#E26D77
"

HISTSIZE=50000
SAVEHIST=50000
HISTFILE="$HOME/.zsh_history"
setopt HIST_IGNORE_DUPS HIST_IGNORE_SPACE SHARE_HISTORY EXTENDED_HISTORY

export EDITOR=nvim
export VISUAL=nvim
export PAGER='bat --plain'
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

if [[ -n "$SSH_CONNECTION" ]] && command -v tmux &>/dev/null; then
  if [[ -z "$TMUX" ]]; then
    tmux attach-session -t main 2>/dev/null || tmux new-session -s main
  fi
fi
ZSHRC

  ok ".zshrc written"
  ok "Phase 7 complete"
}

# ═════════════════════════════════════════════════════════════════════════════
# PHASE 8 — Starship (Flawless Graphite)
# ═════════════════════════════════════════════════════════════════════════════
phase_8_starship() {
  sep
  log "PHASE 8 — Starship config"

  mkdir -p "$HOME/.config"
  cat > "$HOME/.config/starship.toml" << 'STARSHIP'
# Flawless Starship — Flawless Graphite palette
format = """
[╭─](fg:#566072)$os$directory$git_branch$git_status$nodejs$python$rust$bun$docker_context$cmd_duration$line_break
[╰─](fg:#566072)$character"""

[os]
disabled = false
style = "fg:#566072"

[directory]
style = "bold fg:#6CA9FF"
truncation_length = 4
format = "[ $path ]($style)"

[git_branch]
symbol = " "
style = "bold fg:#5FBBC2"
format = "[$symbol$branch]($style) "

[git_status]
style = "fg:#E26D77"
format = '([$all_status$ahead_behind]($style) )'

[nodejs]
symbol = " "
style = "fg:#98C379"
format = "[$symbol$version]($style) "

[python]
symbol = " "
style = "fg:#D8BE84"
format = "[$symbol$version]($style) "

[rust]
symbol = " "
style = "fg:#E26D77"
format = "[$symbol$version]($style) "

[bun]
symbol = " "
style = "fg:#D9AEFF"
format = "[$symbol$version]($style) "

[cmd_duration]
min_time = 2_000
style = "fg:#566072"
format = "[ $duration]($style)"

[character]
success_symbol = "[❯](bold fg:#98C379)"
error_symbol = "[❯](bold fg:#E26D77)"
vicmd_symbol = "[❮](bold fg:#D8BE84)"
STARSHIP

  ok "starship.toml written"
  ok "Phase 8 complete"
}

# ═════════════════════════════════════════════════════════════════════════════
# MAIN
# ═════════════════════════════════════════════════════════════════════════════
main() {
  clear
  echo ""
  echo -e "${BOLD}${CYAN}"
  echo "  ███████╗██╗      █████╗ ██╗    ██╗██╗     ███████╗███████╗███████╗"
  echo "  ██╔════╝██║     ██╔══██╗██║    ██║██║     ██╔════╝██╔════╝██╔════╝"
  echo "  █████╗  ██║     ███████║██║ █╗ ██║██║     █████╗  ███████╗███████╗"
  echo "  ██╔══╝  ██║     ██╔══██║██║███╗██║██║     ██╔══╝  ╚════██║╚════██║"
  echo "  ██║     ███████╗██║  ██║╚███╔███╔╝███████╗███████╗███████║███████║"
  echo "  ╚═╝     ╚══════╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚══════╝╚══════╝╚══════╝╚══════╝"
  echo -e "${RESET}"
  echo -e "  ${BOLD}Dev Environment Setup${RESET} · ${CYAN}github.com/flawlessstudio/flawless-dotfiles${RESET}"
  echo -e "  Blink Shell · iPhone-first workflow · SOTA 2026"
  echo ""

  detect_os

  phase_0_prerequisites
  phase_1_shell
  phase_2_tmux
  phase_3_editor
  phase_4_git_ssh
  phase_5_cli_tools
  phase_6_runtimes
  phase_7_zshrc
  phase_8_starship

  sep
  echo ""
  echo -e "${GREEN}${BOLD}  ✓ Flawless environment ready${RESET}"
  echo ""
  echo -e "  ${CYAN}Next steps:${RESET}"
  echo -e "  1. ${BOLD}exec zsh${RESET}               — reload shell"
  echo -e "  2. ${BOLD}nvim${RESET}                   — complete LazyVim install"
  echo -e "  3. ${BOLD}tmux${RESET}                   — prefix+I to install plugins"
  echo -e "  4. Add SSH key to GitHub: ${CYAN}cat ~/.ssh/id_ed25519.pub${RESET}"
  echo ""
  sep
}

main "$@"
