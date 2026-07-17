dim="$(printf "\e[1;30m")"
green="$(printf "\e[0;32m")"
cyan="$(printf "\e[0;36m")"
yellow="$(printf "\e[0;33m")"
reset="$(printf "\e[m")"

log_step() {
    printf '%b[i]%b %s\n' "$cyan" "$reset" "$*"
}

log_ok() {
    printf '%b[s]%b %s\n' "$green" "$reset" "$*"
}

log_warn() {
    printf '%b[w]%b %s\n' "$yellow" "$reset" "$*" >&2
}
