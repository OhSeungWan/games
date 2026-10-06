#!/usr/bin/env bash
# Assembles the public GitHub Pages site of the policy pages (FR-43, FR-31).
#
# Usage: bash tool/build_pages_site.sh [out-dir]
#   out-dir  where the site is written; default <repo>/_site. A relative path
#            is taken from the current directory.
#
# Copies only `docs/games/<slug>/{en,ko,ja}/<name>.html` (files directly in
# those language folders) to `<out-dir>/<slug>/<lang>/<name>.html`, so the
# internal documents next to them (`store/`, `verification/`, `user-site/`,
# sub-folders, other languages, non-HTML files) are never published. The
# output directory is deleted and made again on every run. Symbolic links
# among the pages are skipped. It refuses (exit 2, nothing deleted):
#   - an empty path;
#   - the repository root or any directory that contains it (such as `/`), and
#     anything inside `docs/`, compared case-insensitively (APFS default);
#   - an existing output that is not a real directory, or that holds anything
#     an earlier run could not have written: every entry must be a directory
#     or regular file (no symbolic link) on a path of the site shape
#     `<slug>/<en|ko|ja>/<name>.html`. An empty directory is fine.
# With no page to copy it exits with 1.
#
# The site is the same for every app (all of docs/games/*), so it takes no
# --app. .github/workflows/pages.yml deploys the result; each app's
# tool/ci_local.sh builds it and checks it with
# packages/game_tooling/tool/check_links.dart against the app's link
# constants (game_ui_kit lib/app/legal_links.dart with the slug of
# apps/<slug>/tool/tooling.yaml, which must equal lib/app/game_slug.dart).
set -euo pipefail

usage() {
  echo "usage: bash tool/build_pages_site.sh [out-dir]" >&2
  exit 2
}

if [[ $# -gt 1 ]]; then
  usage
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

if [[ $# -eq 1 ]]; then
  out="$1"
  if [[ -z "$out" ]]; then
    echo "build_pages_site: the output directory is an empty path" >&2
    exit 2
  fi
else
  out="$repo_root/_site"
fi

# Absolute path of $1 with `.` and `..` removed; the longest existing prefix
# is resolved through symbolic links.
normalize() {
  local path="$1"
  [[ "$path" == /* ]] || path="$PWD/$path"
  local clean="" part
  local IFS='/'
  set -f
  for part in $path; do
    case "$part" in
      '' | .) ;;
      ..) clean="${clean%/*}" ;;
      *) clean="$clean/$part" ;;
    esac
  done
  set +f
  unset IFS
  # Resolve the longest existing prefix through symbolic links.
  local prefix="$clean" rest=""
  while [[ -n "$prefix" && ! -d "$prefix" ]]; do
    rest="/${prefix##*/}$rest"
    prefix="${prefix%/*}"
  done
  if [[ -n "$prefix" ]]; then
    prefix="$(cd "$prefix" && pwd -P)"
  fi
  local result="$prefix$rest"
  echo "${result:-/}"
}

out="$(normalize "$out")"

refuse() {
  echo "build_pages_site: refusing to write to $out: $1" >&2
  exit 2
}

lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
out_lc="$(lower "$out")"
repo_lc="$(lower "$repo_root")"

if [[ "$out" == "/" || "$repo_lc/" == "$out_lc/"* ]]; then
  refuse "it is the repository root or contains it"
fi
if [[ "$out_lc/" == "$repo_lc/docs/"* ]]; then
  refuse "it is inside docs/"
fi

# An existing output may only hold what an earlier run wrote.
if [[ -e "$out" || -L "$out" ]]; then
  if [[ -L "$out" || ! -d "$out" ]]; then
    refuse "it exists and is not a directory"
  fi
  while IFS= read -r -d '' entry; do
    relative="${entry#"$out/"}"
    if [[ -L "$entry" ]]; then
      refuse "it holds a symbolic link: $relative"
    elif [[ -d "$entry" ]]; then
      [[ "$relative" =~ ^[^/.][^/]*(/(en|ko|ja))?$ ]] ||
        refuse "it holds a directory a site does not have: $relative"
    elif [[ -f "$entry" ]]; then
      [[ "$relative" =~ ^[^/.][^/]*/(en|ko|ja)/[^/]+\.html$ ]] ||
        refuse "it holds a file a site does not have: $relative"
    else
      refuse "it holds a special file: $relative"
    fi
  done < <(find "$out" -mindepth 1 -print0)
fi

shopt -s nullglob
pages=()
for page in "$repo_root"/docs/games/*/{en,ko,ja}/*.html; do
  if [[ -f "$page" && ! -L "$page" ]]; then
    pages+=("$page")
  fi
done
shopt -u nullglob

if [[ ${#pages[@]} -eq 0 ]]; then
  echo "build_pages_site: no page under docs/games/<slug>/{en,ko,ja}/*.html" >&2
  exit 1
fi

rm -rf "$out"
mkdir -p "$out"

for page in "${pages[@]}"; do
  relative="${page#"$repo_root/docs/games/"}"
  mkdir -p "$out/$(dirname "$relative")"
  cp "$page" "$out/$relative"
  echo "$relative"
done
echo "Copied ${#pages[@]} pages to $out"
