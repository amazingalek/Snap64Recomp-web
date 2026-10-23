#!/usr/bin/env bash
# Builds the web page (build-web/Snap64Recomp.html, .js, .wasm, .data) from the US ROM, on Linux with emsdk active
# (N64Recomp-browser's README, Using it in a recomp, says what else: naga, spirv-opt, ccache), the MIPS binutils and
# Python 3 with venv:
#
#   bash tools/build_web.sh <US ROM> [--prepare]
#   bash tools/build_web.sh --patches          step 1 alone: no ROM, and only git and CMake
#
# 1. The submodules, and N64Recomp-browser's web patches on them (lib/N64Recomp-browser/patches/apply.cmake, project
#    by project), but for the files where Snap64 Recomp's own forks of rt64 and the runtime change the same lines: the
#    web's change to those (patches/web/files.txt) is patches/web/<name>.patch instead, written on top of Snap64
#    Recomp's from the N64Recomp-browser commit patches/web/files.txt names, with what the web has changed in them
#    since merged in by apply.cmake --since (only a change that meets the port's own lines stops the build, for
#    another merge by hand). Patched from clean whenever lib/N64Recomp-browser, patches/web or the commit of rt64 or the runtime moved since the last time, which build-web-prep/web-patched records (a sync that moves a submodule resets it, so its patches have to go on again): apply.cmake can't take a checkout from one
#    version of its patches to another.
#      rt64: what both add beside each other (the rect and primitive colour matching beside the CPU hot paths' call
#      hash map, the shader blob cache beside the WGSL cache and the prebuilt shaders, the swap chain's vsync beside
#      the present timeline, the depth every pixel writes beside the derivatives taken first); on a page the present
#      thread keeps the web's timer, since the browser presents on its animation frames.
#      N64ModernRuntime: the live recompiler's code registered for unwinding off on wasm (it has none), offline mods
#      still refused, macOS's thread policy beside the web's thread names, ULTRAMODERN_LIBULTRA_THREAD_STOP, the timer
#      thread polling for a near timer beside the port's game speed and its never-destroyed queue.
# 2. N64Recomp and RSPRecomp, built natively from the patched checkout: the page needs the code the web-patched
#    N64Recomp writes.
# 3. The decomp's ELF (ethteck/pokemonsnap at the commit BUILDING.md names, IDO through its own setup), relinked with
#    its relocations as BUILDING.md's step 2 says and checked against the ROM, in build-web-prep/decomp.
# 4. The recompiled game and patches, as BUILDING.md's steps 3-5 and 8, and the audio microcode (step 9).
# 5. The page, with emcmake, in build-web (web/page.cmake). --prepare stops before it.
# --patches stops after step 1. N64Recomp-browser's CI runs it with its own checkout as lib/N64Recomp-browser and the
# submodules checked out, so a web change there that meets this port's own lines in a file left out is red where it is
# made: merge it into the patch by hand then.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
[[ $# -ge 1 ]] || { echo "usage: $0 <US ROM> [--prepare] | --patches" >&2; exit 2; }
patches_only=0
[[ "$1" == --patches ]] && patches_only=1
[[ $patches_only == 1 ]] || rom="$(realpath "$1")"
prepare_only=0
[[ "${2:-}" == --prepare ]] && prepare_only=1
cd "$root"
jobs="$(nproc)"
browser=lib/N64Recomp-browser
prep=build-web-prep
decomp_url=https://github.com/ethteck/pokemonsnap
decomp_commit=3a236dc20cd7f34dea188ef8bc33a31154f0ee97
mkdir -p $prep

step() { printf '\n== %s\n' "$*"; }

# --- 1. Submodules and patches ---
step "Submodules"
[[ -f lib/rt64/CMakeLists.txt && -f lib/N64ModernRuntime/N64Recomp/CMakeLists.txt && -f $browser/patches/apply.cmake ]] ||
    git submodule update --init --recursive --depth 1 lib/rt64 lib/N64ModernRuntime $browser

step "Patches"
# <name> <checkout> [files left to patches/web/<name>.patch, merged from the commit files.txt names]
shared() { awk -v p="$1" '!/^#/ && $1 == p { printf "%s ", $2 }' patches/web/files.txt; }
merged_from="$(sed -n 's/^# merged from N64Recomp-browser //p' patches/web/files.txt)"
web_patches="rt64 lib/rt64 $(shared rt64)
plume lib/rt64/src/contrib/plume
hlslpp lib/rt64/src/contrib/hlslpp
N64ModernRuntime lib/N64ModernRuntime $(shared N64ModernRuntime)
N64Recomp lib/N64ModernRuntime/N64Recomp"
stamp="$(git -C $browser rev-parse HEAD) $(git -C lib/rt64 rev-parse HEAD) $(git -C lib/N64ModernRuntime rev-parse HEAD) $( (cat patches/web/*.patch patches/web/files.txt; echo "$web_patches") | sha1sum | cut -c1-40)"
if [[ "$(cat $prep/web-patched 2> /dev/null)" != "$stamp" ]]; then
    for s in lib/rt64 lib/N64ModernRuntime; do
        git -C $s submodule foreach --recursive -q 'git reset -q --hard && git clean -fdq'
        git -C $s reset -q --hard && git -C $s clean -fdq
    done
    while read -r name checkout skip; do
        cmake -P $browser/patches/apply.cmake "$name" "$checkout" $skip
        [[ ! -f patches/web/$name.patch ]] || git -C "$checkout" apply --whitespace=nowarn "$root/patches/web/$name.patch"
        [[ -z "$skip" ]] || cmake -P $browser/patches/apply.cmake "$name" "$checkout" --since "$merged_from" $skip
    done <<< "$web_patches"
    echo "$stamp" > $prep/web-patched
fi

[[ $patches_only == 1 ]] && exit 0

# --- 2. N64Recomp and RSPRecomp ---
step "N64Recomp"
tools=$prep/tools
[[ -f $tools/build.ninja ]] || cmake -S lib/N64ModernRuntime/N64Recomp -B $tools -G Ninja -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ > /dev/null
ninja -C $tools N64RecompCLI RSPRecomp > /dev/null
recompiler="$root/$tools/N64Recomp"

# --- 3. The decomp's ELF ---
step "Decomp ELF"
decomp=$prep/decomp
python3 - "$rom" $prep/pokemonsnap.z64 <<'PY'
import hashlib, pathlib, sys
source, target = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
data = bytearray(source.read_bytes())
magic = bytes(data[:4]).hex()
if magic == "37804012":
    data[0::2], data[1::2] = data[1::2], data[0::2]
elif magic == "40123780":
    for i in range(0, len(data) - 3, 4):
        data[i:i + 4] = data[i:i + 4][::-1]
if hashlib.sha1(data).hexdigest() != "edc7c49cc568c045fe48be0d18011c30f393cbaf":
    raise SystemExit(f"{source}: not Pokemon Snap (US) (SHA-1 {hashlib.sha1(data).hexdigest()})")
if not target.exists() or target.read_bytes() != data:
    target.write_bytes(data)
PY
elf=$decomp/build/pokemonsnap.relocs.elf
if [[ "$(cat $decomp/.snap-elf-stamp 2> /dev/null)" != "$decomp_commit" || ! -f $decomp/build/pokemonsnap.elf ]]; then
    [[ -d $decomp/.git ]] || git clone -q $decomp_url $decomp
    git -C $decomp fetch -q origin $decomp_commit 2> /dev/null || true
    git -C $decomp checkout -q $decomp_commit
    git -C $decomp submodule update -q --init --recursive
    cp $prep/pokemonsnap.z64 $decomp/pokemonsnap.z64
    # uv, which the decomp's Python dependencies are locked with (uv.lock), in a venv of its own.
    [[ -x $prep/uv/bin/uv ]] || { python3 -m venv $prep/uv && $prep/uv/bin/pip install -q uv; }
    uv="$root/$prep/uv/bin/uv"
    # pigment64, which converts the decomp's images, from crates.io as the decomp's own CI gets it.
    if ! command -v pigment64 > /dev/null && [[ ! -x $prep/cargo/bin/pigment64 ]]; then
        PATH="$PATH:/opt/cargo/bin" CARGO_HOME="$root/$prep/cargo" cargo install -q --locked --root "$root/$prep/cargo" pigment64@0.6.3
    fi
    export PATH="$root/$prep/cargo/bin:$PATH"
    # A split from splat's cache (.splache) leaves out of undefined_syms_auto.txt the symbols of the segments it skips,
    # and the link then misses them: every split here starts without it.
    (cd $decomp && rm -f .splache && "$uv" sync -q && "$uv" run configure.py --setup && "$uv" run configure.py && ninja)
    echo "$decomp_commit" > $decomp/.snap-elf-stamp
fi
# BUILDING.md's step 2: the same link with --emit-relocs. undefined_syms_auto.txt also sets two microcode text labels
# that pokemonsnap.us.toml ignores to their addresses, which makes them absolute symbols, not functions of .main, and
# N64Recomp stops on an ignored function it can't find; in this link they keep their place in .main.
grep -v -E '^(aspMainTextStart|gspF3DEX2_NoN_fifoTextStart) =' $decomp/undefined_syms_auto.txt \
    > $decomp/build/undefined_syms_relocs.txt
(cd $decomp && mips-linux-gnu-ld -T undefined_syms.txt -T build/undefined_syms_relocs.txt \
    -Map build/pokemonsnap.relocs.map -T pokemonsnap.ld --emit-relocs -o build/pokemonsnap.relocs.elf.new)
cmp -s $elf.new $elf && rm $elf.new || mv $elf.new $elf
# .main, 0x45270 bytes at ROM 0x1000, must be the ROM's (BUILDING.md, step 2).
python3 - $elf $prep/pokemonsnap.z64 <<'PY'
import struct, sys
elf, rom = open(sys.argv[1], "rb").read(), open(sys.argv[2], "rb").read()
shoff, shentsize, shnum, shstrndx = struct.unpack(">I", elf[0x20:0x24])[0], *struct.unpack(">HHH", elf[0x2E:0x34])
sections = [struct.unpack(">IIIIIIIIII", elf[shoff + i * shentsize:shoff + (i + 1) * shentsize]) for i in range(shnum)]
names = sections[shstrndx][4]
for s in sections:
    name = elf[names + s[0]:elf.index(b"\0", names + s[0])].decode()
    if name == ".main":
        if s[5] != 0x45270 or elf[s[4]:s[4] + s[5]] != rom[0x1000:0x1000 + 0x45270]:
            raise SystemExit(".main in the relocatable ELF doesn't match the ROM")
        break
else:
    raise SystemExit("no .main in the relocatable ELF")
PY

# --- 4. The recompiled game, the patches and the audio microcode ---
step "Recompiled code"
cp -u $elf pokemonsnap.relocs.elf
cp -u $prep/pokemonsnap.z64 pokemonsnap.z64
inputs="$( (cat pokemonsnap.us.toml overlays.us.txt patches.toml tools/hook_funcs.py pokemonsnap.relocs.elf "$recompiler" \
    patches/Makefile patches/*.ld patches/pokemonsnap.syms.toml patches/src/*; ls patches/src) | sha1sum | cut -c1-40)"
if [[ "$(cat $prep/recompiled-stamp 2> /dev/null)" != "$inputs" || ! -f RecompiledFuncs/funcs.h ||
      ! -f RecompiledPatches/patches.c ]]; then
    rm -rf RecompiledFuncs RecompiledPatches patches/build
    "$recompiler" pokemonsnap.us.toml > $prep/n64recomp.log 2>&1 || { tail -20 $prep/n64recomp.log; exit 1; }
    python3 tools/hook_funcs.py --web
    # The patches include rt64's extended GBI from the decomp's include folder (BUILDING.md, step 1).
    cp lib/rt64/include/rt64_extended_gbi.h $decomp/include/
    make -C patches -j"$jobs" DECOMP="$root/$decomp" > $prep/patches.log 2>&1 || { tail -20 $prep/patches.log; exit 1; }
    "$recompiler" patches.toml >> $prep/n64recomp.log 2>&1 || { tail -20 $prep/n64recomp.log; exit 1; }
    python3 tools/hook_funcs.py --web
    echo "$inputs" > $prep/recompiled-stamp
fi

step "Audio microcode"
mkdir -p $prep/rsp
sed -e "s|@SNAP_ROM_CMAKE@|$root/$prep/pokemonsnap.z64|" -e "s|@SNAP_ASPMAIN_CPP@|$root/$prep/rsp/aspMain.cpp|" \
    rsp/aspMain.us.toml.in > $prep/rsp/aspMain.us.toml
[[ $prep/rsp/aspMain.cpp -nt $prep/rsp/aspMain.us.toml ]] || $tools/RSPRecomp $prep/rsp/aspMain.us.toml > /dev/null
[[ $prepare_only == 1 ]] && exit 0

# --- 5. The page ---
step "Page"
emcmake cmake -S . -B build-web -G Ninja -DCMAKE_BUILD_TYPE=Release -DSNAP_ASPMAIN_CPP="$root/$prep/rsp/aspMain.cpp" \
    -DPython3_EXECUTABLE="$(command -v python3)" > /dev/null
cmake --build build-web --target Snap64Recomp -j"$jobs"
ls -l build-web/Snap64Recomp.{html,js,wasm,data}
