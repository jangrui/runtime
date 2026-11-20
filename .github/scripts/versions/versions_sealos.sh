#!/bin/bash
#
# NOTE (bug fix): Sealos version is now passed explicitly via the
# SEALOS_VERSION environment variable, set by the calling workflow from
# its inputs.sealosVersion (workflow_call) or left empty on
# workflow_dispatch (meaning: use the latest Sealos tag).
#
# The old logic read the 2nd word of github.event.comment.body as the
# Sealos version:
#   commentVersion="$(echo "${commentbody?}" | awk '{print $2}')"
# That was wrong for the restored issue-comment command
#   /imagebuild_k8s <kubeVersion> [sealosVersion]
# e.g. "/imagebuild_k8s 1.33.6": $2 is the *Kubernetes* version 1.33.6,
# not a Sealos version, so the Sealos tag check below would fail with
# "sealos version 1.33.6 does not exist". Do not restore that logic:
# comment bodies are parsed by the issue-comment workflow
# (.github/workflows/autobuild-k8s-on-issue-comment.yml) and passed in
# as explicit inputs instead.
set -e

# NOTE (fork fix): resolve tags with git ls-remote, not the GitHub REST API.
# The API call above has no auth token, so a shared runner IP easily hits
# the 60 req/hour unauthenticated rate limit; the until-loop then retries
# forever with no timeout (run #7 hung 20+ min here). git ls-remote has
# no such limit. The loop below is bounded: 10 tries, then fail loudly.
fetch_sealos_tags() {
  local tries=0
  until git ls-remote --refs --sort="-version:refname" --tags "https://github.com/labring/sealos.git" | cut -d/ -f3- | grep -E "^v[0-9.]+$" > .tags; do
    tries=$((tries + 1))
    if [[ $tries -ge 10 ]]; then
      echo "failed to list labring/sealos tags after 10 tries"
      exit 1
    fi
    sleep 3
  done
}

fetch_sealos_tags
readonly defaultVersion="$(head -n 1 .tags | cut -dv -f2)"

if [[ "${SEALOS_VERSION:-}" == latest ]]; then
  # Fork fix: "latest" must resolve to the newest final tag (e.g. 5.1.2).
  # Passing the literal string "latest" through makes kubernetes.sh take
  # its unstable branch (floating v<minor>-<arch> tag only) and makes the
  # manifest job build version "<kube>-latest", e.g. 1.34.13-latest.
  # The workflow input itself documents "empty or latest means latest
  # Sealos tag", so resolve it here.
  sealosVersion="$defaultVersion"
elif [[ -n "${SEALOS_VERSION:-}" ]]; then
  sealosVersion="${SEALOS_VERSION#v}"
else
  sealosVersion="$defaultVersion"
fi

if [[ "$sealosVersion" == latest ]]; then
  echo "sealos latest for development"
else
  fetch_sealos_tags
  if ! grep "$sealosVersion" .tags >/dev/null; then
    cat .tags
    echo "sealos version $sealosVersion does not exist"
    exit 127
  fi
fi

echo "sealos: $sealosVersion"
echo "sealoslatest=$sealosVersion" >>$GITHUB_OUTPUT
