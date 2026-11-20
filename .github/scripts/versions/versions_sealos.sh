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

readonly defaultVersion="$(until curl -sL "https://api.github.com/repos/labring/sealos/tags" | yq '.[].name' | grep -E "^v.+$"; do sleep 1; done | grep -E "v[0-9.]+$" | head -n 1 | cut -dv -f2)"

if [[ "${SEALOS_VERSION:-}" == latest ]]; then
  sealosVersion=latest
elif [[ -n "${SEALOS_VERSION:-}" ]]; then
  sealosVersion="${SEALOS_VERSION#v}"
else
  sealosVersion="$defaultVersion"
fi

if [[ "$sealosVersion" == latest ]]; then
  echo "sealos latest for development"
else
  until curl -sL https://api.github.com/repos/labring/sealos/tags | yq .[].name | grep -E "^v.+$"; do sleep 3; done >.tags
  if ! grep "$sealosVersion" .tags >/dev/null; then
    cat .tags
    echo "sealos version $sealosVersion does not exist"
    exit 127
  fi
fi

echo "sealos: $sealosVersion"
echo "sealoslatest=$sealosVersion" >>$GITHUB_OUTPUT
