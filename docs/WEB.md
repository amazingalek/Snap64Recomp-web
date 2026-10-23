# The web page

This fork's `main` branch also builds with [Emscripten](https://emscripten.org) into a page, `Snap64Recomp.html`,
that draws through WebGPU: **https://n64hub.com/pokemon-snap/**. The game's code is recompiled from the
Pokémon Snap decompilation's ELF of the US ROM, as the desktop build's is, and
[N64Recomp-browser](https://github.com/n64hub/N64Recomp-browser) (`lib/N64Recomp-browser`) patches RT64, plume,
hlslpp, N64ModernRuntime and N64Recomp with the web support and makes the game a page. Everything the page needs is
behind `__EMSCRIPTEN__` or `if(EMSCRIPTEN)` (`CMakeLists.txt` includes `web/page.cmake` in place of the rest of
itself), so the desktop builds are unchanged.

## What the page leaves out

- **Mods.** N64ModernRuntime's live recompiler (sljit) emits machine code, so a page takes none, and the Mods page has
  nothing to pick (`src/mod_installer.cpp`).
- **Files outside the browser.** The ROM, the save, the settings, the Snap Station's printed sheets and the photos the
  port exports are kept in the browser's storage (IndexedDB, through N64Recomp-browser's `persistent_home.js`), not in
  a folder a player can open: a page has no file manager to open one in (`src/snap_station.cpp`).
- **The window's own settings.** On a page the window is the canvas, sized by the page; fullscreen is the browser's.

## How it is built

`tools/build_web.sh <US ROM>` does all of it on Linux with emsdk active, naga (`cargo install naga-cli`), spirv-opt,
the MIPS binutils, Python 3 with venv and, for faster rebuilds, ccache on `PATH`. Its header says each step:

1. The submodules, with N64Recomp-browser's web patches on them (`lib/N64Recomp-browser/patches/apply.cmake`, project
   by project), but for the files where this port's own changes to rt64 and the runtime meet the web's: the web's
   change to those is `patches/web/<project>.patch`, written on top of the port's from the N64Recomp-browser commit
   `patches/web/files.txt` names. What the web has changed in those files since is merged in by its `apply.cmake
   --since`, so a page never goes without it, and only a change that meets the port's own lines stops the build, to
   be merged into the patch by hand (`files.txt` says how).
2. N64Recomp and RSPRecomp, built natively from the patched checkout: its `funcs.h` declares every function the
   recompiled code calls, which a WebAssembly link needs.
3. The decompilation's ELF, relinked with its relocations as BUILDING.md says and checked against the ROM.
4. The recompiled game and patches, and the audio microcode, from the web-patched N64Recomp.
5. The page, with `emcmake cmake` and `web/page.cmake`, in `build-web`.

`build-web` then holds `Snap64Recomp.html`, `.js`, `.wasm`, `.data` and `coi_serviceworker.js`. Serve that folder with
`Cross-Origin-Opener-Policy: same-origin` and `Cross-Origin-Embedder-Policy: require-corp`, or as is on a host that
can't set headers, where `coi_serviceworker.js` sets them after one reload. It needs a browser with WebGPU (Chrome or
Edge 113 and up, or Firefox 141 and up). The keyboard is the desktop's (MANUAL.md, Controls): WASD the stick, X A, Z B,
Left Shift Z, Enter Start, E R, IJKL the C buttons; the mouse aims the camera once the page has it.

## What the page does differently

- **A launcher of its own** (`src/rom_picker.cpp`): Load ROM, which opens the browser's file picker, and Start Game
  once a ROM is kept. A browser keeps a page silent until the player clicks, so the game always starts from it.
- **Sound** goes to N64Recomp-browser's `audio_output.h`, an AudioWorklet on the browser's audio thread reading a ring
  in the program's memory, through an SDL audio stream from the game's rate to the page's: Emscripten's SDL2 plays its
  queue from the page's thread, where WebGPU's work runs, and breaks up whenever that thread is busy (`src/audio.cpp`).
- **Frame rate Display** by default (`src/settings.h`): RT64 interpolates the game's frames to the display's rate, as
  every recomp's page does, and the resolution follows the canvas as the port's default does (the largest whole
  multiple of the game's 320x240 that fits). A player can still pick Original in the menu.
- **Render to RAM stays on, with the exact copy**: the game scores a photo from the frame it has just drawn, and the
  camera's focus dot is found in that same frame, so a copy a display list late would score the frame before
  (`src/settings.h`, `render_to_ram`).
- **The object manager's threads.** HAL's object manager runs each object's process on a thread of its own, which
  stops itself (`ohWait`) until the next frame starts it again. The runtime's libultra thread stop, on with
  Emscripten, ignored a start of a thread that had stopped itself, and the page stopped after the game's second frame;
  N64ModernRuntime-web 6515ea8 marks such a thread stopped, and `patches/web/N64ModernRuntime.patch` carries the same.

## Prebuilt shaders

The page builds the shaders the game uses before it draws with them, so it never draws with RT64's slow ubershader in
the middle of a course: `web/rt64_shaders.txt` lists them in sections (its header says what each holds), and the build
specializes each one (`RT64_PREBUILT_SHADER_LIST` in `web/page.cmake`). In Chrome the whole list is built behind the
game from its first frame, and the game waits only when a frame wants 4 or more of a section's shaders that aren't
built yet, under a small "Preparing graphics" indicator in a corner. Firefox builds a pipeline in line with the rest
of its GPU work, so there those above the first section are built before the game starts, and a section when the game
first draws it, the game waiting. A shader the list misses is built behind the game, and the page remembers it and
builds it with the rest on the next visit.

`web/record_shaders.sh` records the list (its header says how): N64Recomp-browser's recorder drives the page in
headless Chrome through `web/shader_plan.json`, a page load a course, in which `web/survey.cpp` starts the course from
the main menu (`Module._snap_web_course`) and `web/shader_survey.js` rides it to its end, taking photos and throwing
the items. `Module._snap_web_scene()` says which scene the game is in, for a script.
