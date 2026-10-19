# The game as a page for a browser (emcmake cmake), Snap64Recomp.html, through lib/N64Recomp-browser: RT64 on WebGPU
# in the page's canvas, sound on the browser's audio thread, the ROM, the save and the settings in the browser's
# storage. CMakeLists.txt includes this in place of the rest of itself when it configures with Emscripten;
# tools/build_web.sh makes what it needs first (the web patches on the submodules, the recompiled game and patches
# from the web-patched N64Recomp, the audio microcode) and passes the microcode's C++ as SNAP_ASPMAIN_CPP.
#
# What differs from the desktop build:
# - rt64 and the runtime are the submodules with N64Recomp-browser's web support patched in (tools/build_web.sh, and
#   patches/web where Snap64 Recomp's own changes meet it). RT64 draws through WebGPU whatever the settings say.
# - No file dialog: the ROM comes from a launcher on the page (src/rom_picker.cpp) and is kept under HOME, which the
#   page keeps in the browser's IndexedDB (src/paths.cpp).
# - The shipped files (menu_text/, gamecontrollerdb.txt, the window icon) are the page's .data, at the root of its
#   file system, where the desktop build copies them beside the executable. Not the seen-shader list: a page builds
#   its prebuilt shader list (web/rt64_shaders.txt) instead.
# - No mods: a page has no live recompiler (N64Recomp-browser's README).

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
if (NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "" FORCE)
endif()
if (NOT SNAP_ASPMAIN_CPP OR NOT EXISTS "${SNAP_ASPMAIN_CPP}")
    message(FATAL_ERROR "SNAP_ASPMAIN_CPP: the recompiled audio microcode; tools/build_web.sh makes it")
endif()

# Threads are pthreads (SharedArrayBuffer), and the runtime ends a game thread by throwing. -msimd128 is wasm SIMD,
# which every browser with WebGPU has; -mtail-call makes the recompiled code's tail calls return_calls. With -msimd128
# xxHash would take its NEON path through Emscripten's arm_neon.h, which doesn't compile in C++ there.
add_compile_options(-pthread -fwasm-exceptions -msimd128 -mtail-call "-DXXH_HAS_INCLUDE(x)=0" -sUSE_SDL=2)
include_directories(SYSTEM "${EMSCRIPTEN_SYSROOT}/include/SDL2")
add_link_options(-pthread -fwasm-exceptions -mtail-call)
# ccache when it is on PATH, for shorter builds; before rt64 and the runtime are added.
include(${CMAKE_SOURCE_DIR}/lib/N64Recomp-browser/frontend/build_speed.cmake)
# The shaders the page specializes at build time and builds before the game draws with them (web/rt64_shaders.txt
# says how it was recorded); before rt64 is added.
if (EXISTS "${CMAKE_SOURCE_DIR}/web/rt64_shaders.txt")
    set(RT64_PREBUILT_SHADER_LIST "${CMAKE_SOURCE_DIR}/web/rt64_shaders.txt" CACHE FILEPATH "" FORCE)
endif()

set(RT64_STATIC ON CACHE BOOL "" FORCE)
add_subdirectory(${CMAKE_SOURCE_DIR}/lib/rt64 ${CMAKE_BINARY_DIR}/rt64 EXCLUDE_FROM_ALL)
add_subdirectory(${CMAKE_SOURCE_DIR}/lib/N64ModernRuntime ${CMAKE_BINARY_DIR}/N64ModernRuntime EXCLUDE_FROM_ALL)
add_subdirectory(${CMAKE_SOURCE_DIR}/lib/N64Recomp-browser/frontend ${CMAKE_BINARY_DIR}/web_frontend)
# fmt 11.1 (N64Recomp's) leans on <cstdlib> arriving through other headers, which Emscripten's libc++ doesn't do.
if (TARGET fmt)
    target_compile_options(fmt PRIVATE -include cstdlib)
endif()

# The recompiled game. WebAssembly turns a call to an undeclared function into a trap, so it may call none.
file(GLOB RECOMP_FUNC_SOURCES CONFIGURE_DEPENDS "${CMAKE_SOURCE_DIR}/RecompiledFuncs/funcs_*.c")
if (NOT RECOMP_FUNC_SOURCES)
    message(FATAL_ERROR "RecompiledFuncs/ is empty: tools/build_web.sh recompiles the game first")
endif()
add_library(recomp_funcs STATIC ${RECOMP_FUNC_SOURCES})
target_include_directories(recomp_funcs PUBLIC
    "${CMAKE_SOURCE_DIR}/RecompiledFuncs"
    "${CMAKE_SOURCE_DIR}/lib/N64ModernRuntime/N64Recomp/include")
target_compile_options(recomp_funcs PRIVATE -fno-strict-aliasing -fwrapv -w -Werror=implicit-function-declaration)

# The game's patches, as the desktop build compiles them (CMakeLists.txt says why each step), and the patch ELF's
# bytes embedded.
set(SNAP_PATCH_DIR "${CMAKE_BINARY_DIR}/generated/patches")
set(SNAP_PATCH_C "${SNAP_PATCH_DIR}/patches.c")
add_custom_command(
    OUTPUT "${SNAP_PATCH_C}"
    COMMAND ${CMAKE_COMMAND} "-DINPUT_DIR=${CMAKE_SOURCE_DIR}/RecompiledPatches" "-DOUTPUT_DIR=${SNAP_PATCH_DIR}"
        -P "${CMAKE_SOURCE_DIR}/tools/portable_patches.cmake"
    DEPENDS "${CMAKE_SOURCE_DIR}/RecompiledPatches/patches.c" "${CMAKE_SOURCE_DIR}/RecompiledPatches/funcs.h"
        "${CMAKE_SOURCE_DIR}/tools/portable_patches.cmake"
    COMMENT "Copying RecompiledPatches with the C library's reserved names renamed")
set_source_files_properties("${SNAP_PATCH_C}" PROPERTIES
    COMPILE_OPTIONS "-w;-fno-strict-aliasing;-fwrapv;-Werror=implicit-function-declaration")
set(SNAP_PATCH_BIN "${CMAKE_SOURCE_DIR}/patches/build/patches.bin")
set(SNAP_PATCH_BIN_C "${CMAKE_BINARY_DIR}/generated/snap_patches_bin.c")
add_custom_command(
    OUTPUT "${SNAP_PATCH_BIN_C}"
    COMMAND ${CMAKE_COMMAND} "-DINPUT=${SNAP_PATCH_BIN}" "-DOUTPUT=${SNAP_PATCH_BIN_C}" -DSYMBOL=snap_patches_bin
        -P "${CMAKE_SOURCE_DIR}/tools/embed_bin.cmake"
    DEPENDS "${SNAP_PATCH_BIN}" "${CMAKE_SOURCE_DIR}/tools/embed_bin.cmake"
    COMMENT "Embedding patches/build/patches.bin")
set_source_files_properties("${SNAP_ASPMAIN_CPP}" PROPERTIES COMPILE_OPTIONS "-w")

configure_file("${CMAKE_SOURCE_DIR}/src/version.h.in" "${CMAKE_BINARY_DIR}/generated/version.h" @ONLY)

# CMakeLists.txt's SNAP_SOURCES.
add_executable(Snap64Recomp
    "${SNAP_PATCH_C}"
    "${SNAP_PATCH_BIN_C}"
    src/main.cpp
    src/paths.cpp
    src/rom_picker.cpp
    src/fast_forward.cpp
    src/steam_deck.cpp
    src/mod_api.cpp
    src/mod_data_api.cpp
    src/mod_time_api.cpp
    src/mod_installer.cpp
    src/menu_mouse.cpp
    src/pointer.cpp
    src/gpu_check.cpp
    src/dds_image.cpp
    src/rt64_render_context.cpp
    src/rsp_microcode.cpp
    src/audio.cpp
    src/input.cpp
    src/os_stubs.cpp
    src/overlay_hook.cpp
    src/matrix_tags.cpp
    src/rect_tags.cpp
    src/lab_monitor.cpp
    src/save_file.cpp
    src/rect_census.cpp
    src/fx_tags.cpp
    src/host_hooks.cpp
    src/menu_assets.cpp
    src/menu_harvest.cpp
    src/anim_steps.cpp
    src/focus_dot.cpp
    src/dl_budget.cpp
    src/frame_cost.cpp
    src/sfx_volume_probe.cpp
    src/score_probe.cpp
    src/intro_probe.cpp
    src/settings.cpp
    src/photo_export.cpp
    src/snap_station.cpp
    web/survey.cpp
    "${SNAP_ASPMAIN_CPP}")
target_include_directories(Snap64Recomp PRIVATE
    "${CMAKE_SOURCE_DIR}/src"
    "${CMAKE_BINARY_DIR}/generated"
    "${CMAKE_SOURCE_DIR}/RecompiledFuncs"
    "${CMAKE_SOURCE_DIR}/lib/N64ModernRuntime/N64Recomp/include"
    "${CMAKE_SOURCE_DIR}/lib/N64ModernRuntime/librecomp/include"
    "${CMAKE_SOURCE_DIR}/lib/N64ModernRuntime/ultramodern/include"
    "${CMAKE_SOURCE_DIR}/lib/N64ModernRuntime/thirdparty"
    "${CMAKE_SOURCE_DIR}/lib/N64ModernRuntime/thirdparty/concurrentqueue"
    "${CMAKE_SOURCE_DIR}/lib/rt64/src"
    "${CMAKE_SOURCE_DIR}/lib/rt64/src/contrib"
    "${CMAKE_SOURCE_DIR}/lib/rt64/src/contrib/hlslpp/include"
    "${CMAKE_SOURCE_DIR}/lib/rt64/src/contrib/plume"
    "${CMAKE_SOURCE_DIR}/lib/rt64/src/contrib/imgui"
    "${CMAKE_SOURCE_DIR}/lib/rt64/src/contrib/mupen64plus-core/src/api"
    "${CMAKE_SOURCE_DIR}/lib/SlotMap")
target_compile_definitions(Snap64Recomp PRIVATE HAS_RT64=1 HLSL_CPU FFX_GCC SNAP_HAS_PATCH_BIN=1)
target_compile_options(Snap64Recomp PRIVATE -fno-strict-aliasing -Wall -Wextra -Wno-unused-parameter)
target_link_libraries(Snap64Recomp PRIVATE recomp_funcs librecomp ultramodern rt64)

# The page (lib/N64Recomp-browser/frontend), with the shipped files in its .data. No ROM: the player loads theirs on
# the page, and it stays in the browser.
n64recomp_browser_frontend_page(Snap64Recomp)
target_link_options(Snap64Recomp PRIVATE
    "SHELL:--preload-file ${CMAKE_SOURCE_DIR}/menu_text/recomp_logo.png@/menu_text/recomp_logo.png"
    "SHELL:--preload-file ${CMAKE_SOURCE_DIR}/menu_text/pointer.png@/menu_text/pointer.png"
    "SHELL:--preload-file ${CMAKE_SOURCE_DIR}/menu_text/pointer_flash.png@/menu_text/pointer_flash.png"
    "SHELL:--preload-file ${CMAKE_SOURCE_DIR}/assets/gamecontrollerdb.txt@/gamecontrollerdb.txt"
    "SHELL:--preload-file ${CMAKE_SOURCE_DIR}/src/snap64-window.png@/Snap64Recomp-window.png")
set_property(TARGET Snap64Recomp APPEND PROPERTY LINK_DEPENDS
    "${CMAKE_SOURCE_DIR}/menu_text/recomp_logo.png" "${CMAKE_SOURCE_DIR}/menu_text/pointer.png"
    "${CMAKE_SOURCE_DIR}/menu_text/pointer_flash.png" "${CMAKE_SOURCE_DIR}/assets/gamecontrollerdb.txt"
    "${CMAKE_SOURCE_DIR}/src/snap64-window.png")
