#!/usr/bin/env bash
# Checks that patches/web is still the web's change to the files it takes over, run by tools/build_web.sh before it
# patches anything:
#
#   bash tools/check_web_patches.sh [--update]
#
# Snap64 Recomp's own rt64 and runtime change some of the files N64Recomp-browser's web patches change, so the build
# leaves those files out of the web patches and applies patches/web/<project>.patch to them instead, the two changes
# merged by hand (build_web.sh, step 1). patches/web/files.txt names each such file with a hash of the web's change to
# it that patches/web was merged from: the file's part of lib/N64Recomp-browser/patches/<project>.patch, less its
# index line. When N64Recomp-browser moves and the web's change to one of them is another, the build would quietly go
# without the new change, so this stops naming the files: merge their new change into patches/web/<project>.patch
# (the old one is in N64Recomp-browser's history at the commit files.txt names), then run it with --update, which
# writes the hashes and that commit anew. A file the build has to leave out now (the web's change and the port's meet
# in it, so the web patch no longer applies to it) is added to files.txt by hand, then --update.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
browser="$root/lib/N64Recomp-browser"
list="$root/patches/web/files.txt"
update=0
[[ "${1:-}" == --update ]] && update=1

# The file's part of a project's web patch, as a hash (the same from a checkout with CRLF line ends).
change() {
    awk -v f="$2" '{ sub(/\r$/, "") } /^diff --git /{p=($3=="a/"f)} p && !/^index /' "$browser/patches/$1.patch" |
        sha1sum | cut -c1-40
}

if ((update)); then
    {
        grep '^#' "$list" | grep -v '^# merged from '
        echo "# merged from N64Recomp-browser $(git -C "$browser" rev-parse HEAD)"
        grep -v '^#' "$list" | while read -r project file _; do echo "$project $file $(change "$project" "$file")"; done
    } > "$list.new"
    mv "$list.new" "$list"
    exit 0
fi

moved=()
while read -r project file hash; do
    [[ "$(change "$project" "$file")" == "$hash" ]] || moved+=("$project $file")
done < <(grep -v '^#' "$list" | tr -d '\r')
((${#moved[@]} == 0)) && exit 0
from="$(sed -n 's/^# merged from N64Recomp-browser //p' "$list")"
echo "patches/web was merged from N64Recomp-browser ${from:0:7}, and the web's change to these files has moved since:" >&2
printf '  %s\n' "${moved[@]}" >&2
echo "Merge it into patches/web/<project>.patch (git -C lib/N64Recomp-browser diff ${from:0:7} HEAD -- patches/<project>.patch)," >&2
echo "then run tools/check_web_patches.sh --update (its header says how)." >&2
exit 1
