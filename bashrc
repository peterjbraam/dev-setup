# ~/.bashrc for macOS (bash)

: "${HISTTIMEFORMAT:=}"
# --- Color setup ---
export CLICOLOR=1
export LSCOLORS=ExFxBxDxCxegedabagacad

# --- Prompt ---
# \h = short hostname, \w = working dir
# Bold green for hostname, bold blue for path
# Bold red % for user, # for root, always with trailing space

if [[ $EUID -eq 0 ]]; then
  # root prompt
  PS1='\[\e[1;32m\]\h \[\e[1;34m\]\w \[\e[1;31m\]# \[\e[0m\]'
else
  # user prompt
  PS1='\[\e[1;32m\]\h \[\e[1;34m\]\w \[\e[1;31m\]$ \[\e[0m\]'
fi

# PATH

# --- no pagers; avoid terminal corruption ---
export GIT_PAGER=cat
export PAGER=cat
export MANPAGER=cat
# export LESS=FRX

# --- guard commonly unset vars under `set -u` ---
: "${HISTTIMEFORMAT:=}"
: "${size:=0}"            # some prompts/plugins reference $size on exit; keep harmless default


# --- Aliases / goodies ---
alias ll='ls -alF'
alias lar='ls -AlR'

# Long directory listing with details (lld)
alias lld='ls -lad . .. *'

# Git helpers
alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git log --oneline --graph --decorate'


# --- Misc ---
command -v vim >/dev/null 2>&1 && export EDITOR=vim

# PATH
PATH="/opt/homebrew/opt/make/libexec/gnubin:$PATH"
export PATH=$PATH:$(go env GOPATH)/bin


# Change directory to the git repository root.
# If already at the root, change to the parent directory.
cdr() {
    local root
    root=$(git rev-parse --show-toplevel 2>/dev/null)
    if [[ -n "$root" && "$PWD" != "$root" ]]; then
        cd "$root"
    else
        cd ..
    fi
}
alias patch='gpatch'
alias make=gmake


# --- Load Google API key (Gemini etc.)
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
