# ~/.bashrc - unified for Linux + macOS
case $- in
    *i*) ;;
      *) return;;
esac

# --- History ---
HISTCONTROL=ignoreboth
shopt -s histappend
HISTSIZE=5000
HISTFILESIZE=10000
HISTTIMEFORMAT="%H:%M "   # hh:mm timestamps

# --- Shell options ---
shopt -s checkwinsize
shopt -s globstar 2>/dev/null || true

# --- Prompt (unified: user@host cwd $ or #) ---
if [[ $EUID -eq 0 ]]; then
  PS1='\[\e[1;32m\]A \u@\h \[\e[1;34m\]\w \[\e[1;31m\]# \[\e[0m\]'
else
  PS1='\[\e[1;32m\]\A \u@\h \[\e[1;34m\]\w \[\e[1;31m\]$ \[\e[0m\]'
fi

# --- Colors for ls ---
if [[ "$OSTYPE" == "darwin"* ]]; then
  export CLICOLOR=1
  export LSCOLORS=ExFxBxDxCxegedabagacad
else
  export HOST_LIBVIRT_GID=$(getent group libvirt | cut -d: -f3)
  if [ -x /usr/bin/dircolors ]; then
    eval "$(dircolors -b ~/.dircolors 2>/dev/null || dircolors -b)"
    alias ls='ls --color=auto'
    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
  fi
fi

# pbc for Unix instead of pbcopy
# Copy stdin to local clipboard via OSC 52
pbc() {
  local input encoded
  input=$(cat) || return 1
  # Base64-encode without newlines
  encoded=$(printf "%s" "$input" | base64 | tr -d '\n')
  # Emit OSC 52 escape sequence
  printf '\e]52;c;%s\a' "$encoded"
}

# --- Aliases ---
alias clear='clear && printf "\e[3J"'
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias lar='ls -AlR'
alias lld='ls -lad . .. *'
alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git log --oneline --graph --decorate'
alias find='gfind'
alias awk='gawk'
# Allow terminal apps to use system clipboard via OSC52
if command -v xclip >/dev/null; then
  alias pbcopy='xclip -selection clipboard'
  alias pbpaste='xclip -selection clipboard -o'
elif command -v xsel >/dev/null; then
  alias pbcopy='xsel --clipboard --input'
  alias pbpaste='xsel --clipboard --output'
  # Enable bracketed paste mode in bash
  bind 'set enable-bracketed-paste on'
fi

# --- Editor ---
if command -v vim >/dev/null 2>&1; then
  export EDITOR=vim
elif command -v vi >/dev/null 2>&1; then
  export EDITOR=vi
fi

# --- PATH setup ---
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
  export PATH="$HOME/.local/bin:$PATH"
  export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin
  export GOPATH=$HOME/go
  export PATH=$PATH:$GOPATH/bin
  export PATH=$PATH:~braam/scripts
  PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"
fi

if [[ "$OSTYPE" == "darwin"* ]]; then
export PATH="/opt/homebrew/opt/make/libexec/gnubin"
export PATH="$PATH:/opt/homebrew/bin"
export PATH="$PATH:/Users/braam/.nix-profile/bin:/nix/var/nix/profiles/default/bin"
export PATH="$PATH:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export PATH="$PATH:/Applications/VMware Fusion.app/Contents/Public"
export PATH="$PATH:/Users/braam/go/bin"
export PATH="$PATH:/opt/local/bin"
fi
export PATH="$PATH:/Users/braam/sst/tools:/Users/braam/scripts"



# --- Pager preference ---
if command -v less >/dev/null 2>&1; then
  export PAGER=less
elif command -v more >/dev/null 2>&1; then
  export PAGER=more
else
  export PAGER=cat
fi
export MANPAGER="$PAGER"
export GIT_PAGER="$PAGER"

# --- Functions ---
cdr() {
    local root
    root=$(git rev-parse --show-toplevel 2>/dev/null)
    if [[ -n "$root" && "$PWD" != "$root" ]]; then
        cd "$root"
    else
        cd ..
    fi
}

# --- Secrets (Google API key) ---
if [ -f "$HOME/secrets/google_api_key.sh" ]; then
  . "$HOME/secrets/google_api_key.sh"
elif gitroot="$(git rev-parse --show-toplevel 2>/dev/null)"; then
  if [ -f "$gitroot/secrets/google_api_key.sh" ]; then
    . "$gitroot/secrets/google_api_key.sh"
  else
    echo "[.bashrc] ERROR: No google_api_key.sh found in ~/secrets or $gitroot/secrets" >&2
  fi
else
  echo "[.bashrc] ERROR: Could not find google_api_key.sh and not inside a git repo." >&2
fi

# --- Completion ---
if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi
export HOMEBREW_NO_AUTO_UPDATE="1"
# Lima BEGIN
# Make sure iptables and mount.fuse3 are available
PATH="$PATH:/usr/sbin:/sbin"
export PATH
# Lima END
# Enable programmable completion features via Homebrew
if type brew &>/dev/null; then
  HOMEBREW_PREFIX="$(brew --prefix)"
  if [[ -r "${HOMEBREW_PREFIX}/etc/profile.d/bash_completion.sh" ]]; then
    source "${HOMEBREW_PREFIX}/etc/profile.d/bash_completion.sh"
  fi
fi
source <(ggo completion bash)
