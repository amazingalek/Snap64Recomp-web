#!/usr/bin/env bash
# Records the page's prebuilt shader list, web/rt64_shaders.txt, from a page built without it or with an older one:
#
#   bash web/record_shaders.sh <build dir> <US ROM> [record_shaders.mjs options: --only <section>,... --port <n>]
#
# N64Recomp-browser's tools/record_shaders.mjs opens the page with ?record-shaders in headless Chrome (node and Chrome
# on PATH or where it looks) and plays web/shader_plan.json: a page load a course, each started by web/survey.cpp from
# the main menu's New Game and ridden by web/shader_survey.js, since a page records only what it draws. Then rebuild
# the page: the list is specialized at build time (RT64_PREBUILT_SHADER_LIST, web/page.cmake).
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
[[ $# -ge 2 ]] || { sed -n 4p "$0"; exit 2; }
build="$1" rom="$2"
shift 2
node "$root/lib/N64Recomp-browser/tools/record_shaders.mjs" "$root/web/shader_plan.json" "$build" "$rom" \
    "$root/web/rt64_shaders.txt" "$@"
