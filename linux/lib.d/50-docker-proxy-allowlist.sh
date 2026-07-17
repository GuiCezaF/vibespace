# Allowlist explicito da API Docker exposta pelo wollomatic (deny-by-default).
# Novo acesso = nova linha aqui, revisado de proposito.

DOCKER_PROXY_ALLOW_GET=(
    '/_ping'
    '/v1\.[0-9]+/version'
    '/v1\.[0-9]+/info'
    '/v1\.[0-9]+/containers/json'
    '/v1\.[0-9]+/containers/[a-zA-Z0-9_.-]+/json'
    '/v1\.[0-9]+/containers/[a-zA-Z0-9_.-]+/logs'
    '/v1\.[0-9]+/containers/[a-zA-Z0-9_.-]+/stats'
    '/v1\.[0-9]+/containers/[a-zA-Z0-9_.-]+/top'
    '/v1\.[0-9]+/images/json'
    '/v1\.[0-9]+/images/[a-zA-Z0-9_.-]+/json'
    '/v1\.[0-9]+/networks'
    '/v1\.[0-9]+/networks/[a-zA-Z0-9_.-]+'
    '/v1\.[0-9]+/volumes'
    '/v1\.[0-9]+/volumes/[a-zA-Z0-9_.-]+'
    '/v1\.[0-9]+/exec/[a-zA-Z0-9]+/json'
    '/v1\.[0-9]+/distribution/[a-zA-Z0-9_.-]+/json'
)

DOCKER_PROXY_ALLOW_HEAD=(
    '/_ping'
)

DOCKER_PROXY_ALLOW_POST=(
    '/grpc'
    '/session'
    '/v1\.[0-9]+/containers/create'
    '/v1\.[0-9]+/containers/[a-zA-Z0-9_.-]+/start'
    '/v1\.[0-9]+/containers/[a-zA-Z0-9_.-]+/attach'
    '/v1\.[0-9]+/containers/[a-zA-Z0-9_.-]+/stop'
    '/v1\.[0-9]+/containers/[a-zA-Z0-9_.-]+/restart'
    '/v1\.[0-9]+/containers/[a-zA-Z0-9_.-]+/kill'
    '/v1\.[0-9]+/containers/[a-zA-Z0-9_.-]+/wait'
    '/v1\.[0-9]+/containers/[a-zA-Z0-9_.-]+/exec'
    '/v1\.[0-9]+/exec/[a-zA-Z0-9]+/start'
    '/v1\.[0-9]+/exec/[a-zA-Z0-9]+/resize'
    '/v1\.[0-9]+/images/create'
    '/v1\.[0-9]+/images/[a-zA-Z0-9_.-]+/tag'
    '/v1\.[0-9]+/build'
    '/v1\.[0-9]+/networks/create'
    '/v1\.[0-9]+/networks/[a-zA-Z0-9_.-]+/connect'
    '/v1\.[0-9]+/networks/[a-zA-Z0-9_.-]+/disconnect'
    '/v1\.[0-9]+/volumes/create'
)

DOCKER_PROXY_ALLOW_PUT=(
    '/v1\.[0-9]+/containers/[a-zA-Z0-9_.-]+/archive'
)

DOCKER_PROXY_ALLOW_DELETE=(
    '/v1\.[0-9]+/containers/[a-zA-Z0-9_.-]+'
    '/v1\.[0-9]+/images/[a-zA-Z0-9_.-]+'
    '/v1\.[0-9]+/networks/[a-zA-Z0-9_.-]+'
    '/v1\.[0-9]+/volumes/[a-zA-Z0-9_.-]+'
)

docker_proxy_append_allowlist_env() {
    local -n _out=$1
    local method=$2
    local -n _patterns=$3
    local i suffix name

    for i in "${!_patterns[@]}"; do
        if [ "$i" -eq 0 ]; then
            suffix=""
        else
            suffix="_$((i + 1))"
        fi
        name="SP_ALLOW_${method}${suffix}"
        _out+=(-e "${name}=${_patterns[$i]}")
    done
}

docker_proxy_allowlist_env() {
    local -a env=()

    docker_proxy_append_allowlist_env env GET DOCKER_PROXY_ALLOW_GET
    docker_proxy_append_allowlist_env env HEAD DOCKER_PROXY_ALLOW_HEAD
    docker_proxy_append_allowlist_env env POST DOCKER_PROXY_ALLOW_POST
    docker_proxy_append_allowlist_env env PUT DOCKER_PROXY_ALLOW_PUT
    docker_proxy_append_allowlist_env env DELETE DOCKER_PROXY_ALLOW_DELETE
    printf '%s\n' "${env[@]}"
}
