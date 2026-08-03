#!/usr/bin/env bash
set -Eeuo pipefail

cd /actions-runner

for variable in ACCESS_TOKEN GITHUB_OWNER GITHUB_REPO REPO_URL RUNNER_NAME LABELS; do
    if [[ -z "${!variable:-}" ]]; then
        echo "Required environment variable ${variable} is missing." >&2
        exit 1
    fi
done

readonly RUNNERS_API="https://api.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPO}/actions/runners"
runner_pid=""

get_runner_token() {
    local endpoint="$1"
    local response_file http_status token

    response_file="$(mktemp)"
    http_status="$(curl --silent --show-error --location \
        --output "${response_file}" \
        --write-out '%{http_code}' \
        --request POST \
        --header 'Accept: application/vnd.github+json' \
        --header "Authorization: Bearer ${ACCESS_TOKEN}" \
        --header 'X-GitHub-Api-Version: 2022-11-28' \
        "${RUNNERS_API}/${endpoint}")" || {
            rm -f "${response_file}"
            echo "GitHub API request failed for ${endpoint}." >&2
            return 1
        }

    if [[ "${http_status}" != "201" ]]; then
        echo "GitHub API returned HTTP ${http_status}: $(jq -r '.message // "unknown error"' "${response_file}")" >&2
        rm -f "${response_file}"
        return 1
    fi

    token="$(jq -er '.token' "${response_file}")" || {
        rm -f "${response_file}"
        echo "GitHub API response did not contain a runner token." >&2
        return 1
    }

    rm -f "${response_file}"
    printf '%s' "${token}"
}

cleanup() {
    local exit_code=$?
    local remove_token

    trap - EXIT INT TERM

    if [[ -n "${runner_pid}" ]] && kill -0 "${runner_pid}" 2>/dev/null; then
        kill -TERM "${runner_pid}" 2>/dev/null || true
        wait "${runner_pid}" 2>/dev/null || true
    fi

    if [[ -f .runner ]]; then
        echo "Removing runner registration..."
        if remove_token="$(get_runner_token remove-token)"; then
            ./config.sh remove --unattended --token "${remove_token}" || true
        else
            echo "Could not remove the runner registration; it will be replaced on the next start." >&2
        fi
    fi

    exit "${exit_code}"
}

trap cleanup EXIT INT TERM

echo "Obtaining runner registration token..."
registration_token="$(get_runner_token registration-token)"

echo "Configuring runner ${RUNNER_NAME} for ${GITHUB_OWNER}/${GITHUB_REPO}..."
./config.sh \
    --url "${REPO_URL}" \
    --token "${registration_token}" \
    --name "${RUNNER_NAME}" \
    --labels "${LABELS}" \
    --unattended \
    --replace

echo "Starting runner..."
./run.sh &
runner_pid=$!
wait "${runner_pid}"
