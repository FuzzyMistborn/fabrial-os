# Enable Powerlevel10k instant prompt (only if p10k is configured)
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

export PATH=$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH

# ── Oh My Zsh ────────────────────────────────────────────────────────────────
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="powerlevel10k/powerlevel10k"
ZSH_CUSTOM="$HOME/.oh-my-zsh-custom"

plugins=(
  git
  command-not-found
  history
  zsh-syntax-highlighting
  zsh-autosuggestions
)

# Only load oh-my-zsh if it's installed (run `ujust install-zsh` if not)
if [[ -f "$ZSH/oh-my-zsh.sh" ]]; then
  source "$ZSH/oh-my-zsh.sh"
else
  echo "oh-my-zsh not installed. Run: ujust install-zsh"
fi

# ── Aliases ──────────────────────────────────────────────────────────────────
[[ -f ~/.bash_aliases ]] && source ~/.bash_aliases

# ── Powerlevel10k config ─────────────────────────────────────────────────────
[[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh

# ── eza / ls ─────────────────────────────────────────────────────────────────
if command -v eza &>/dev/null; then
  alias ls="eza"
  alias la="eza --long --all --group"
fi

# ── Aliases ──────────────────────────────────────────────────────────────────
alias c='clear'
alias e='exit'
alias ssh-remove='ssh-keygen -f ~/.ssh/known_hosts -R $1'
alias logi-restart='sudo systemctl restart logid'
alias fingerprint-enable='sudo authselect enable-feature with-fingerprint'
alias fingerprint-disable='sudo authselect disable-feature with-fingerprint'

# ── Keyboard directory navigation ────────────────────────────────────────────
function my-redraw-prompt() {
  {
    builtin echoti civis
    builtin local f
    for f in chpwd "${chpwd_functions[@]}" precmd "${precmd_functions[@]}"; do
      (( ! ${+functions[$f]} )) || "$f" &>/dev/null || builtin true
    done
    builtin zle reset-prompt
  } always {
    builtin echoti cnorm
  }
}
function my-cd-up()      { builtin cd -q .. && my-redraw-prompt; }
function my-cd-rotate() {
  () {
    builtin emulate -L zsh
    while (( $#dirstack )) && ! builtin pushd -q $1 &>/dev/null; do
      builtin popd -q $1
    done
    (( $#dirstack ))
  } "$@" && my-redraw-prompt
}
function my-cd-back()    { my-cd-rotate +1; }
function my-cd-forward() { my-cd-rotate -0; }
builtin zle -N my-cd-up
builtin zle -N my-cd-back
builtin zle -N my-cd-forward
() {
  for keymap in emacs viins vicmd; do
    builtin bindkey '^[^[[A'  my-cd-up
    builtin bindkey '^[[1;3A' my-cd-up
    builtin bindkey '^[[1;9A' my-cd-up
    builtin bindkey '^[^[[D'  my-cd-back
    builtin bindkey '^[[1;3D' my-cd-back
    builtin bindkey '^[[1;9D' my-cd-back
    builtin bindkey '^[^[[C'  my-cd-forward
    builtin bindkey '^[[1;3C' my-cd-forward
    builtin bindkey '^[[1;9C' my-cd-forward
  done
}
setopt auto_pushd
