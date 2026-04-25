# ~/.bashrc - unified for Linux + macOS
case $- in
    *i*) ;;
      *) return;;
esac

# -----------------------------------------------------
# PATH Setup (Loaded first so commands below succeed)
# -----------------------------------------------------
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
  export PATH="$HOME/.local/bin:$PATH"
  export PATH="$PATH:/usr/local/go/bin:$HOME/go/bin"
  export GOPATH="$HOME/go"
  export PATH="$PATH:$GOPATH/bin"
  export PATH="$PATH:~braam/scripts"
  export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"
fi

if [[ "$OSTYPE" == "darwin"* ]]; then
  export PATH="/opt/homebrew/opt/make/libexec/gnubin:$PATH"
  export PATH="$PATH:/opt/homebrew/bin"
  export PATH="$PATH:/Users/braam/.nix-profile/bin:/nix/var/nix/profiles/default/bin"
  export PATH="$PATH:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
  export PATH="$PATH:/Applications/VMware Fusion.app/Contents/Public"
  export PATH="$PATH:/Users/braam/go/bin"
  export PATH="$PATH:/opt/local/bin"
fi
export PATH="$PATH:/Users/braam/sst/tools:/Users/braam/scripts"

# Lima BEGIN
export PATH="$PATH:/usr/sbin:/sbin"
# Lima END

# -----------------------------------------------------
# Shell Options & History
# -----------------------------------------------------
HISTCONTROL=ignoreboth
shopt -s histappend
HISTSIZE=5000
HISTFILESIZE=10000
HISTTIMEFORMAT="%H:%M "

shopt -s checkwinsize
shopt -s globstar 2>/dev/null || true

# -----------------------------------------------------
# Prompt
# -----------------------------------------------------
if [[ $EUID -eq 0 ]]; then
  PS1='\[\e[1;32m\]\A \u@\h \[\e[1;34m\]\w \[\e[1;31m\]# \[\e[0m\]'
else
  PS1='\[\e[1;32m\]\A \u@\h \[\e[1;34m\]\w \[\e[1;31m\]$ \[\e[0m\]'
fi

# -----------------------------------------------------
# Colors
# -----------------------------------------------------
if [[ "$OSTYPE" == "darwin"* ]]; then
  export CLICOLOR=1
  export LSCOLORS=ExFxBxDxCxegedabagacad
else
  export HOST_LIBVIRT_GID=$(getent group libvirt 2>/dev/null | cut -d: -f3)
  if command -v dircolors >/dev/null 2>&1; then
    eval "$(dircolors -b ~/.dircolors 2>/dev/null || dircolors -b)"
    alias ls='ls --color=auto'
    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
  fi
fi

# -----------------------------------------------------
# Universal Clipboard Engine
# -----------------------------------------------------
pbc() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        pbcopy
    elif [ -n "$WAYLAND_DISPLAY" ] && command -v wl-copy >/dev/null 2>&1; then
        wl-copy
    elif [ -n "$DISPLAY" ] && command -v xclip >/dev/null 2>&1; then
        xclip -selection clipboard
    elif [ -n "$DISPLAY" ] && command -v xsel >/dev/null 2>&1; then
        xsel --clipboard --input
    else
        local input=$(cat)
        local encoded=$(printf "%s" "$input" | base64 | tr -d '\n')
        printf '\e]52;c;%s\a' "$encoded"
    fi
}

pbv() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        pbpaste
    elif [ -n "$WAYLAND_DISPLAY" ] && command -v wl-paste >/dev/null 2>&1; then
        wl-paste
    elif [ -n "$DISPLAY" ] && command -v xclip >/dev/null 2>&1; then
        xclip -selection clipboard -o
    elif [ -n "$DISPLAY" ] && command -v xsel >/dev/null 2>&1; then
        xsel --clipboard --output
    else
        echo "Error: No graphical clipboard (DISPLAY/WAYLAND_DISPLAY) found." >&2
        return 1
    fi
}

# -----------------------------------------------------
# Universal Clipboard Engine
# -----------------------------------------------------

alias pbcopy='pbc'
alias pbpaste='pbv'

# Unconditionally enable bracketed paste to protect multi-line SSH pastes
bind 'set enable-bracketed-paste on' 2>/dev/null || true

# -----------------------------------------------------
# Basic Aliases
# -----------------------------------------------------
alias clear='clear && printf "\e[3J"'
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias lar='ls -AlR'
alias lld='ls -lad .* *'
alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git log --oneline --graph --decorate'
alias find='gfind' 2>/dev/null || true
alias awk='gawk' 2>/dev/null || true

# -----------------------------------------------------
# Pager & Functions
# -----------------------------------------------------
if command -v less >/dev/null 2>&1; then
  export PAGER=less
elif command -v more >/dev/null 2>&1; then
  export PAGER=more
else
  export PAGER=cat
fi
export MANPAGER="$PAGER"
export GIT_PAGER="$PAGER"

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
  fi
fi

# -----------------------------------------------------
# Completions & fzf
# -----------------------------------------------------
if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi
export HOMEBREW_NO_AUTO_UPDATE="1"

if type brew &>/dev/null; then
  HOMEBREW_PREFIX="$(brew --prefix)"
  if [[ -r "${HOMEBREW_PREFIX}/etc/profile.d/bash_completion.sh" ]]; then
    source "${HOMEBREW_PREFIX}/etc/profile.d/bash_completion.sh"
  fi
fi
source <(ggo completion bash 2>/dev/null) || true

if command -v fzf >/dev/null 2>&1; then
    eval "$(fzf --bash 2>/dev/null)" || true
    export FZF_CTRL_R_OPTS="--tmux center,80%"
    export FZF_DEFAULT_OPTS="--layout=reverse --border"
fi

# -----------------------------------------------------
# Editor Definitions & Emacsclient Engine
# -----------------------------------------------------
# -----------------------------------------------------
# Editor Definitions & Emacsclient Engine
# -----------------------------------------------------
export FCEDIT="emacsclient -a \"\" -t"
export EDITOR="emacsclient -a \"\" -t"
export VISUAL="emacsclient -a \"\" -c"

# Force Restart Emacs Daemon (Restore Sanity)
ef() {
    echo "[*] Terminating Emacs server..."
    # 1. Try graceful shutdown first (allows hooks/saves to run)
    emacsclient -e "(kill-emacs)" 2>/dev/null
    
    # Give it a second to clean up its socket files
    sleep 1
    
    # 2. Ruthless fallback if the server hung on a bad init.el
    if pgrep -x emacs >/dev/null; then
        echo "[!] Emacs hung. Forcing kill..."
        pkill -x emacs 2>/dev/null || true
        sleep 1
    fi
    
    echo "[*] Spinning up fresh Emacs daemon (loading init.el)..."
    # 3. Explicitly start the daemon in the background
    emacs --daemon
    
    echo "[+] Sanity restored!"
}

# Hardened Functions (Replacing fragile aliases)
# ef - kill the server, restart emacs re-evaluate init.el
ec() { emacsclient -a "" -c "$@"; }  # graphical
et() { emacsclient -a "" -t "$@"; }  # terminal 
ee() { emacsclient -a "" -e "$@"; }  # evaluate
en() { emacsclient -a "" -n -c "$@"; } # no-wait, keep working in terminal

# Smart Emacsclient Wrapper (with fzf safety net)
e() {
    local mode="-t"
    local parsed_args=()

    for arg in "$@"; do
        if [[ "$arg" == "-c" || "$arg" == "-e" || "$arg" == "-n" ]]; then
            mode=""
        else
            parsed_args+=("$arg")
        fi
    done

    # If no file specified, open visual picker
    if [ ${#parsed_args[@]} -eq 0 ]; then
        if command -v fzf >/dev/null 2>&1; then
            local target=$(fzf --prompt="Pick file to edit> ")
            if [ -n "$target" ]; then
                emacsclient -a "" $mode "$target"
            fi
        else
            emacsclient -a "" $mode
        fi
        return
    fi

    # Otherwise, execute normally
    emacsclient -a "" $mode "$@"
}
source ~/.bash-completions/gstow.bash

# tstow bash completions
[ -f /home/braam/.bash-completions/tstow.bash ] && source /home/braam/.bash-completions/tstow.bash
