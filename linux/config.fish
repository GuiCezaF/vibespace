# Host-only fish config for vibespace (installed to ~/.config/fish/conf.d/vibespace.fish)

set -gx VIBE_RUNTIME podman

# initialize zoxide for interactive shells
if status is-interactive
    eval (zoxide init fish)
end

alias cursor="vibe cursor"
alias flutter="vibe flutter"
alias mise="vibe mise"
alias bun="vibe bun"
alias bunx="vibe bunx"
alias npm="vibe npm"
alias npx="vibe npx"
alias node="vibe node"

function vibe_ensure_runtime
    if test "$VIBE_RUNTIME" = docker
        if not test -f /var/run/docker.pid
            systemctl start docker
        end
    end
end

function docker_ensure_host
    if not type -q docker
        return 0
    end
    if not docker info >/dev/null 2>&1
        systemctl start docker 2>/dev/null
        or systemctl --user start docker 2>/dev/null
    end
end

function vibe
    vibe_ensure_runtime
    docker_ensure_host

    set -l workdir /w
    if string match -q '/w/*' -- $PWD
        set workdir $PWD
    end

    if not $VIBE_RUNTIME ps --filter "name=^/vibespace\$" --format '{{.Names}}' | grep -q '^vibespace$'
        $VIBE_RUNTIME start vibespace >/dev/null
    end

    if test (count $argv) -eq 0
        $VIBE_RUNTIME exec -it -w "$workdir" vibespace fish
    else
        set cmd (string escape -- $argv)
        echo running '"'"$cmd"'"' inside vibespace
        $VIBE_RUNTIME exec -it -w "$workdir" vibespace fish -c "$cmd"
    end
end

function viberoot
    vibe_ensure_runtime
    docker_ensure_host

    set -l workdir /w
    if string match -q '/w/*' -- $PWD
        set workdir $PWD
    end

    if not $VIBE_RUNTIME ps --filter "name=^/vibespace\$" --format '{{.Names}}' | grep -q '^vibespace$'
        $VIBE_RUNTIME start vibespace >/dev/null
    end

    $VIBE_RUNTIME exec -u0 -it -w "$workdir" vibespace fish
end
