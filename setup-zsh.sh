#!/usr/bin/env bash
# =============================================================================
# setup-zsh.sh — bash -> zsh + Oh My Zsh overhaul for Ubuntu (20.04+ / WSL ok)
#
# Installs: zsh, Oh My Zsh, Powerlevel10k, autosuggestions, syntax highlighting,
#           completions, fzf-tab, history-substring-search, fzf, zoxide, bat,
#           fd, ripgrep, eza (best effort), MesloLGS Nerd Fonts.
# Safe to re-run (idempotent). Backs up your existing ~/.zshrc first.
#
# Usage:  chmod +x setup-zsh.sh && ./setup-zsh.sh
# =============================================================================
set -euo pipefail

# ---------- helpers ----------------------------------------------------------
C_BLUE=$'\e[1;34m'; C_YEL=$'\e[1;33m'; C_RED=$'\e[1;31m'; C_OFF=$'\e[0m'
info() { printf '%s==>%s %s\n' "$C_BLUE" "$C_OFF" "$*"; }
warn() { printf '%s!!%s  %s\n' "$C_YEL" "$C_OFF" "$*"; }
die()  { printf '%sxx%s  %s\n' "$C_RED" "$C_OFF" "$*" >&2; exit 1; }

if [ "$(id -u)" -eq 0 ]; then SUDO=""; else
  command -v sudo >/dev/null || die "sudo not found and you are not root."
  SUDO="sudo"
fi

export DEBIAN_FRONTEND=noninteractive
ZSH_DIR="$HOME/.oh-my-zsh"
ZSH_CUSTOM_DIR="${ZSH_CUSTOM:-$ZSH_DIR/custom}"
LOCAL_BIN="$HOME/.local/bin"
mkdir -p "$LOCAL_BIN"

git_sync() { # git_sync <url> <dest>  (clone or fast-forward update)
  if [ -d "$2/.git" ]; then git -C "$2" pull --ff-only --quiet || warn "could not update $2"
  else git clone --depth=1 --quiet "$1" "$2"; fi
}

# ---------- 0. network sanity check -----------------------------------------
info "Checking network access to GitHub..."
if ! curl -fsI --max-time 15 https://github.com >/dev/null 2>&1; then
  die "Cannot reach github.com. Fix DNS/network first (WSL: try 'wsl --shutdown', check VPN/DNS), then re-run."
fi

# ---------- 1. system packages ----------------------------------------------
info "Installing packages (apt)..."
$SUDO apt-get update -y
$SUDO apt-get install -y \
  zsh git curl wget unzip ca-certificates gnupg fontconfig \
  ripgrep fd-find bat jq tree htop

# Ubuntu names these differently; expose the usual names
[ -x /usr/bin/fdfind ] && ln -sf /usr/bin/fdfind "$LOCAL_BIN/fd"
[ -x /usr/bin/batcat ] && ln -sf /usr/bin/batcat "$LOCAL_BIN/bat"

# ---------- 2. eza (modern ls) — best effort --------------------------------
if ! command -v eza >/dev/null 2>&1; then
  info "Installing eza (best effort)..."
  {
    $SUDO mkdir -p /etc/apt/keyrings
    wget -qO- https://raw.githubusercontent.com/eza-community/eza/main/deb.asc \
      | $SUDO gpg --dearmor --yes -o /etc/apt/keyrings/gierens.gpg
    echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" \
      | $SUDO tee /etc/apt/sources.list.d/gierens.list >/dev/null
    $SUDO chmod 644 /etc/apt/keyrings/gierens.gpg /etc/apt/sources.list.d/gierens.list
    $SUDO apt-get update -y
    $SUDO apt-get install -y eza
  } || warn "eza install failed — falling back to plain ls aliases."
fi

# ---------- 3. fzf (git version: newer than apt's) --------------------------
info "Installing fzf..."
git_sync https://github.com/junegunn/fzf.git "$HOME/.fzf"
"$HOME/.fzf/install" --key-bindings --completion --no-update-rc --no-bash --no-fish >/dev/null

# ---------- 4. zoxide (smarter cd) ------------------------------------------
if ! command -v zoxide >/dev/null 2>&1 && [ ! -x "$LOCAL_BIN/zoxide" ]; then
  info "Installing zoxide..."
  curl -fsSL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash \
    || warn "zoxide install failed — 'cd' will stay normal."
fi

# ---------- 5. Oh My Zsh -----------------------------------------------------
if [ ! -d "$ZSH_DIR" ]; then
  info "Installing Oh My Zsh..."
  RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
else
  info "Oh My Zsh already present — skipping install."
fi

# ---------- 6. theme + plugins ----------------------------------------------
info "Installing Powerlevel10k theme and plugins..."
mkdir -p "$ZSH_CUSTOM_DIR/themes" "$ZSH_CUSTOM_DIR/plugins"
git_sync https://github.com/romkatv/powerlevel10k.git                "$ZSH_CUSTOM_DIR/themes/powerlevel10k"
git_sync https://github.com/zsh-users/zsh-autosuggestions.git         "$ZSH_CUSTOM_DIR/plugins/zsh-autosuggestions"
git_sync https://github.com/zsh-users/zsh-syntax-highlighting.git     "$ZSH_CUSTOM_DIR/plugins/zsh-syntax-highlighting"
git_sync https://github.com/zsh-users/zsh-completions.git             "$ZSH_CUSTOM_DIR/plugins/zsh-completions"
git_sync https://github.com/zsh-users/zsh-history-substring-search.git "$ZSH_CUSTOM_DIR/plugins/zsh-history-substring-search"
git_sync https://github.com/Aloxaf/fzf-tab.git                        "$ZSH_CUSTOM_DIR/plugins/fzf-tab"

# ---------- 7. Nerd Fonts (needed for prompt icons) -------------------------
info "Downloading MesloLGS Nerd Fonts..."
FONT_DIR="$HOME/.local/share/fonts/MesloLGS-NF"
mkdir -p "$FONT_DIR"
base="https://github.com/romkatv/powerlevel10k-media/raw/master"
for f in "MesloLGS NF Regular.ttf" "MesloLGS NF Bold.ttf" "MesloLGS NF Italic.ttf" "MesloLGS NF Bold Italic.ttf"; do
  [ -s "$FONT_DIR/$f" ] || curl -fsSL -o "$FONT_DIR/$f" "${base}/${f// /%20}" || warn "failed to fetch $f"
done
fc-cache -f >/dev/null 2>&1 || true

# ---------- 8. write ~/.zshrc -----------------------------------------------
if [ -f "$HOME/.zshrc" ]; then
  backup="$HOME/.zshrc.bak.$(date +%Y%m%d-%H%M%S)"
  cp "$HOME/.zshrc" "$backup"
  info "Backed up existing .zshrc -> $backup"
fi

info "Writing ~/.zshrc..."
cat > "$HOME/.zshrc" <<'ZSHRC'
# =============================================================================
# ~/.zshrc  (generated by setup-zsh.sh)
# Put personal tweaks in ~/.zshrc.local — it is sourced at the end.
# =============================================================================

# --- Powerlevel10k instant prompt (must stay near the top) -------------------
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# --- PATH --------------------------------------------------------------------
typeset -U path PATH                      # de-duplicate
path=("$HOME/.local/bin" "$HOME/bin" $path)
export PNPM_HOME="${PNPM_HOME:-$HOME/.local/share/pnpm}"
[[ -d $PNPM_HOME ]] && path=("$PNPM_HOME" $path)

# --- Oh My Zsh ---------------------------------------------------------------
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="powerlevel10k/powerlevel10k"
zstyle ':omz:update' mode reminder
DISABLE_AUTO_TITLE="false"
COMPLETION_WAIT_DOTS="true"

# extra completions must be on fpath BEFORE oh-my-zsh runs compinit
fpath+="${ZSH_CUSTOM:-$ZSH/custom}/plugins/zsh-completions/src"

# Order matters: fzf-tab before autosuggestions/highlighting; highlighting LAST.
plugins=(
  git
  sudo                      # press ESC twice to prepend sudo
  extract                   # `x archive.tar.gz` unpacks anything
  colored-man-pages
  copypath                  # copypath -> copies cwd to clipboard
  history-substring-search
  zsh-completions
  fzf-tab
  zsh-autosuggestions
  zsh-syntax-highlighting
)

source "$ZSH/oh-my-zsh.sh"

# --- History -----------------------------------------------------------------
HISTFILE="$HOME/.zsh_history"
HISTSIZE=100000
SAVEHIST=100000
setopt EXTENDED_HISTORY        # timestamps
setopt SHARE_HISTORY           # share across sessions (tmux panes!)
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_IGNORE_SPACE       # leading space = don't record (good for secrets)
setopt HIST_REDUCE_BLANKS
setopt HIST_VERIFY

# --- Shell behaviour ---------------------------------------------------------
setopt AUTO_CD                 # type a dir name to cd into it
setopt AUTO_PUSHD PUSHD_IGNORE_DUPS PUSHD_SILENT
setopt INTERACTIVE_COMMENTS
setopt NO_BEEP
setopt GLOB_DOTS               # include dotfiles in globs
WORDCHARS=${WORDCHARS//[\/]/}  # ctrl+w stops at slashes

# --- Completion tweaks -------------------------------------------------------
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'   # case-insensitive
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' menu no                              # let fzf-tab handle menus
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'ls --color=always $realpath'
zstyle ':fzf-tab:*' switch-group ',' '.'

# --- Autosuggestions / history search keys ----------------------------------
ZSH_AUTOSUGGEST_STRATEGY=(history completion)
ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=50
bindkey '^ ' autosuggest-accept                 # ctrl+space accepts suggestion
bindkey '^[[A' history-substring-search-up      # up arrow: search by typed prefix
bindkey '^[[B' history-substring-search-down
bindkey '^[OA' history-substring-search-up
bindkey '^[OB' history-substring-search-down
bindkey '^[[1;5C' forward-word                  # ctrl+right / ctrl+left
bindkey '^[[1;5D' backward-word
bindkey '^[[3~'   delete-char                   # Delete key

# --- fzf ---------------------------------------------------------------------
[[ -f ~/.fzf.zsh ]] && source ~/.fzf.zsh
if (( $+commands[fd] )); then
  export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git --exclude node_modules'
  export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
  export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git --exclude node_modules'
fi
export FZF_DEFAULT_OPTS='--height 45% --layout=reverse --border --info=inline'
(( $+commands[bat] )) && export FZF_CTRL_T_OPTS="--preview 'bat --style=numbers --color=always --line-range :200 {}'"
# ctrl+r = fuzzy history, ctrl+t = fuzzy files, alt+c = fuzzy cd

# --- zoxide (smart cd): `z foo`, `zi` for interactive ------------------------
(( $+commands[zoxide] )) && eval "$(zoxide init zsh)"

# --- Editor / pager / colours ------------------------------------------------
export EDITOR="${EDITOR:-nano}"
export VISUAL="$EDITOR"
export LESS='-R -F -X -i'
(( $+commands[bat] )) && export MANPAGER="sh -c 'col -bx | bat -l man -p'"
export CLICOLOR=1

# --- Aliases -----------------------------------------------------------------
if (( $+commands[eza] )); then
  alias ls='eza --icons --group-directories-first'
  alias ll='eza -lah --icons --git --group-directories-first'
  alias lt='eza --tree --level=2 --icons'
else
  alias ls='ls --color=auto --group-directories-first'
  alias ll='ls -lAh'
fi
(( $+commands[bat] )) && alias cat='bat --paging=never --style=plain'
alias grep='grep --color=auto'
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias reload='exec zsh'
alias zshrc='${EDITOR} ~/.zshrc'
alias ports='ss -tulpn'
alias myip='curl -s ifconfig.me; echo'
alias path='print -l $path'
alias dud='du -h --max-depth=1 | sort -h'
alias gs='git status -sb'
alias glg='git log --oneline --graph --decorate -20'
alias p='pnpm'
alias pi='pnpm install'
alias pd='pnpm dev'
alias pb='pnpm build'

# --- Small functions ---------------------------------------------------------
mkcd() { mkdir -p -- "$1" && cd -- "$1"; }
fe()   { local f; f=$(fzf --preview 'bat --color=always --line-range :200 {}') && ${EDITOR} "$f"; }   # fuzzy edit
fkill(){ local pid; pid=$(ps -ef | sed 1d | fzf -m | awk '{print $2}'); [[ -n $pid ]] && kill -${1:-9} $pid; }

# --- WSL niceties ------------------------------------------------------------
if [[ -n "${WSL_DISTRO_NAME:-}" ]]; then
  alias open='explorer.exe'
  export BROWSER="${BROWSER:-wslview}"
fi

# --- Powerlevel10k config (run `p10k configure` to redo the wizard) ----------
[[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh

# --- Local overrides ---------------------------------------------------------
[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local
ZSHRC

# ---------- 9. make zsh the default login shell -----------------------------
ZSH_BIN="$(command -v zsh)"
grep -qx "$ZSH_BIN" /etc/shells || echo "$ZSH_BIN" | $SUDO tee -a /etc/shells >/dev/null
if [ "${SHELL:-}" != "$ZSH_BIN" ]; then
  info "Setting zsh as default shell..."
  $SUDO chsh -s "$ZSH_BIN" "$(id -un)" || warn "chsh failed; run: chsh -s $ZSH_BIN"
fi

# ---------- done -------------------------------------------------------------
echo
info "Done. Next steps:"
cat <<EOF

  1. FONT (important): the prompt needs a Nerd Font in the app that DISPLAYS your terminal.
     Fonts were downloaded to: $FONT_DIR
EOF
if [ -n "${WSL_DISTRO_NAME:-}" ] && command -v wslpath >/dev/null 2>&1; then
cat <<EOF
     You are on WSL: open this folder in Windows Explorer, select all 4 .ttf files,
     right-click -> Install:
         $(wslpath -w "$FONT_DIR")
     Then in Windows Terminal: Settings -> your Ubuntu profile -> Appearance ->
     Font face -> "MesloLGS NF". (Installing the font inside Linux does NOT affect Windows Terminal.)
EOF
else
cat <<EOF
     Set your terminal's font to "MesloLGS NF".
EOF
fi
cat <<EOF

  2. Start zsh now:   exec zsh
     The first launch runs the Powerlevel10k wizard; re-run any time with: p10k configure

  3. tmux users: add this to ~/.tmux.conf so new panes use zsh, then restart tmux:
         set -g default-shell "$ZSH_BIN"
         set -g default-terminal "tmux-256color"

  4. Put personal config in ~/.zshrc.local (sourced automatically).
  5. Old .zshrc backup (if any): ~/.zshrc.bak.*

  Handy keys: ctrl+r fuzzy history | ctrl+t fuzzy file | alt+c fuzzy cd |
              ctrl+space accept suggestion | esc esc add sudo | z <dir> smart jump
EOF
