SHELL="bash"

SEARCH_SNIPPET_KEY="alt-s"
OPEN_SOURCE_KEY="alt-o"
EDIT_SOURCE_KEY="alt-e"
OPEN_HOMEPAGE_KEY="alt-w"
NIX_SHELL_KEY="alt-S"
NIX_PROFILE_KEY="alt-P"
PRINT_PREVIEW_KEY="ctrl-i"
EVAL_OPTION_KEY="alt-V"

export OPENER="xdg-open"
[[ $OSTYPE == darwin* ]] && export OPENER="open"
export CMD="${NIX_SEARCH_TV:-nix-search-tv}"
export STATE_FILE="/tmp/nix-search-tv-fzf"

echo "" >"$STATE_FILE"

_search_snippet() {
    local match
    match=$(echo "$1" | tr -d "'" | awk '{ if ($2) { print $2 } else print $1 }')
    "$OPENER" "https://github.com/search?type=code&q=lang:nix+$match" >/dev/null 2>&1 </dev/null
}
export -f _search_snippet

_nix_shell() {
    local package_name="${1//nixpkgs\/ /}"
    local cmd="nix shell nixpkgs#$package_name"
    if [ -n "$TMUX" ]; then
        tmux new-window -n "nix-shell-$package_name" -c "$PWD" "$cmd"
    else
        eval "$cmd"
    fi
}
export -f _nix_shell

_nix_profile() {
    local package_name="${1//nixpkgs\/ /}"
    nix profile install "nixpkgs#$package_name"
}
export -f _nix_profile

_open_source() {
    local url
    url=$($CMD source $(cat "$STATE_FILE") "$1" | sed 's|nixos/modules/nixos/modules/|nixos/modules/|g')
    "$OPENER" "$url" >/dev/null 2>&1 </dev/null
}
export -f _open_source

_edit_source() {
    local source_url
    source_url=$($CMD source $(cat "$STATE_FILE") "$1" | sed 's|nixos/modules/nixos/modules/|nixos/modules/|g')

    local file_path
    file_path=$(echo "$source_url" |
        sed 's|https://github.com/[^/]*/[^/]*/blob/[^/]*/||' |
        sed 's|https://github.com/[^/]*/[^/]*/tree/[^/]*/||' |
        sed 's|#L.*||')

    local repo_path
    case "$source_url" in
    *nix-community/home-manager*) repo_path="$HOME/repos/home-manager" ;;
    *nix-darwin/nix-darwin*) repo_path="$HOME/repos/nix-darwin" ;;
    *) repo_path="$HOME/repos/nixpkgs" ;;
    esac

    $EDITOR "$repo_path/$file_path"
}
export -f _edit_source

_eval_option() {
    local option
    option=$(echo "$1" | sed -E 's|^[^/]+/ ||')
    local system=${SYSTEM:-nixos}
    [[ $(uname) == 'Darwin' ]] && system=darwin

    local target="path:$FLAKE#${system}Configurations.${HOST:-$HOSTNAME}.config.$option"
    local sanitize='x: if builtins.isList x then map (builtins.mapAttrs (k: v: let res = builtins.tryEval v; in if res.success then res.value else "<error>")) x else x'

    tmux popup -w 80% -h 80% -T " $option " \
        -e "NIX_TARGET=$target" \
        -e "NIX_SANITIZE=$sanitize" \
        -E "bash -c 'if res=\$(nix eval --json --apply \"\$NIX_SANITIZE\" \"\$NIX_TARGET\" 2>/dev/null); then echo \"\$res\" | jq -rC | less -R; else nix eval \"\$NIX_TARGET\" | less -R; fi'"
}
export -f _eval_option

PREVIEW_WINDOW="wrap,40%"
[ "$(tput cols)" -lt 90 ] && PREVIEW_WINDOW="$PREVIEW_WINDOW,up"

exec "$CMD" print | fzf \
    --preview "$CMD preview \$(cat $STATE_FILE) {}" \
    --bind "ctrl-u:preview-up" \
    --bind "ctrl-d:preview-down" \
    --bind "$OPEN_SOURCE_KEY:execute-silent(_open_source {})" \
    --bind "$EDIT_SOURCE_KEY:execute(_edit_source {})" \
    --bind "$OPEN_HOMEPAGE_KEY:execute-silent($CMD homepage \$(cat $STATE_FILE) {} | xargs $OPENER >/dev/null 2>&1)" \
    --bind "$SEARCH_SNIPPET_KEY:execute-silent(_search_snippet {})" \
    --bind "$NIX_SHELL_KEY:become(_nix_shell {})" \
    --bind "$NIX_PROFILE_KEY:execute(_nix_profile {})" \
    --bind "$PRINT_PREVIEW_KEY:execute($CMD preview \$(cat $STATE_FILE) {} | less)" \
    --bind "$EVAL_OPTION_KEY:execute(_eval_option {})" \
    --layout reverse \
    --scheme history \
    --border=sharp \
    --preview-border=sharp \
    --preview-window="$PREVIEW_WINDOW"
