#!/usr/bin/env bash
# Download the screenshots of a Shots run (draft release asset shots-<run_id>; falls back to the Actions artifact).
#   bash tool/shots/fetch.sh <run_id> [out_dir]
set -euo pipefail
repo=Azamat4588/edux-mobile
run=${1:?run id}
out=${2:-mobile-shots}
mkdir -p "$out"
asset=$(gh api "repos/$repo/releases" --paginate --jq ".[] | select(.tag_name==\"shots-$run\") | .assets[] | select(.name==\"mobile-screenshots.zip\") | .id" | head -1)
if [ -n "$asset" ]; then
  curl -sSfL -H "Authorization: token $(gh auth token)" -H "Accept: application/octet-stream" \
    "https://api.github.com/repos/$repo/releases/assets/$asset" -o "$out/shots.zip"
else
  url=$(gh api "repos/$repo/actions/runs/$run/artifacts" --jq '.artifacts[]|select(.name=="mobile-screenshots").archive_download_url')
  gh api "$url" > "$out/shots.zip"
fi
unzip -o -q "$out/shots.zip" -d "$out"
ls "$out"/*.png | wc -l
