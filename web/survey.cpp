// A script's way to any course on the page, for recording its shader list a course at a time
// (tools/shader_survey.js) and for a play plan that doesn't start a new game's tutorial first (tools/play_plan.json).
//
// Module._snap_web_course(<scene>) asks for a course by its scene number (the decomp's SceneIds: 0 the Beach to
// 6 Rainbow Cloud). The game's scene loop (src/app_render/46270.c in the decomp) goes from the main menu's New Game
// to the new game's scene and from there to the Beach; with a course asked for, the main menu, if it hasn't begun,
// goes straight to New Game, and the new game's scene starts the course instead, with the Apple, the Pester Ball, the
// Poke Flute and the Dash Engine given, as a save with every course open has them. Asked while the main menu shows,
// the menu plays on, and its New Game starts the course. Module._snap_web_courses_started() counts the courses started.
//
// Module._snap_web_scene() is the scene the game is in: the scene loop's own number, which each scene's function is
// called with (0-6 a course, the attract demo's included, 8 the main menu, 9 the camera check, 11 and 13 Oak's lab,
// 12 the album, 14 the report, 15 the photo check, 17-20 the credits, 22 the gallery, 24 a course's end), and 100 for
// the new game's name entry; -1 before the main menu.
//
// tools/build_web.sh hooks the two functions for the page only (tools/hook_funcs.py --web), so a desktop build has
// neither: the scenes' functions run as the game's, only noting the scene first.
#include <atomic>
#include <cstdint>
#include <cstdio>

#include <emscripten.h>

#include "recomp.h"

namespace {

std::atomic<int> g_course{-1};
std::atomic<int> g_started{0};
std::atomic<int> g_scene{-1};

constexpr uint32_t kSceneBeach = 0;
constexpr uint32_t kSceneRainbow = 6;
constexpr int kSceneNewGame = 100;
// The player's data (the decomp's D_800C21B0_5F050, a pointer to the save's UnkBigBoy) and its item flags' byte.
constexpr uint32_t kPlayerData = 0x800C21B0;
constexpr uint32_t kItemFlags = 0x66;
constexpr uint8_t kItems = 0x80 | 0x40 | 0x20 | 0x04; // hasApple, hasPesterBall, hasFlute, hasDashEngine

uint32_t word(uint8_t* rdram, uint32_t addr) {
    return *reinterpret_cast<uint32_t*>(rdram + (addr - 0x80000000u));
}

uint8_t& byte(uint8_t* rdram, uint32_t addr) {
    return rdram[(addr - 0x80000000u) ^ 3];
}

} // namespace

extern "C" {

void __real_func_800E4830_A0BDC0(uint8_t* rdram, recomp_context* ctx);
void __real_menu_new_game_entry(uint8_t* rdram, recomp_context* ctx);

EMSCRIPTEN_KEEPALIVE void snap_web_course(int scene) {
    if (scene >= int(kSceneBeach) && scene <= int(kSceneRainbow)) {
        g_course.store(scene);
    }
}

// How many courses the page has started this way, for a script to wait on.
EMSCRIPTEN_KEEPALIVE int snap_web_courses_started() {
    return g_started.load();
}

EMSCRIPTEN_KEEPALIVE int snap_web_scene() {
    return g_scene.load();
}

// Every other scene's function, called with its scene's number.
#define SNAP_WEB_SCENE(name)                                        void __real_##name(uint8_t* rdram, recomp_context* ctx);        void name(uint8_t* rdram, recomp_context* ctx) {                    g_scene.store(int(ctx->r4));                                    __real_##name(rdram, ctx);                                  }
SNAP_WEB_SCENE(func_beach_802C4740)
SNAP_WEB_SCENE(tunnel_Start)
SNAP_WEB_SCENE(func_802BE3B0_640860)
SNAP_WEB_SCENE(func_802D9210_6C0FF0)
SNAP_WEB_SCENE(volcano_Start)
SNAP_WEB_SCENE(func_802C6544_79FAD4)
SNAP_WEB_SCENE(func_80346EF0_826660)
SNAP_WEB_SCENE(func_camera_check_801DCACC)
SNAP_WEB_SCENE(func_oaks_lab_800E1AD8)
SNAP_WEB_SCENE(album_Start)
SNAP_WEB_SCENE(func_801DCC74_9D35E4)
SNAP_WEB_SCENE(func_801DCC74_98C6E4)
SNAP_WEB_SCENE(func_801DCEBC_9FAB7C)
SNAP_WEB_SCENE(func_801DD09C_A08C8C)
SNAP_WEB_SCENE(func_credits_801DCB24)
#undef SNAP_WEB_SCENE

// The main menu's scene (the decomp's src/main_menu/A08E30.c).
void func_800E4830_A0BDC0(uint8_t* rdram, recomp_context* ctx) {
    g_scene.store(int(ctx->r4));
    if (g_course.load() >= 0) {
        ctx->r2 = kSceneBeach;
        return;
    }
    __real_func_800E4830_A0BDC0(rdram, ctx);
}

// The new game's scene, its name entry (src/menu_new_game/A5CC50.c).
void menu_new_game_entry(uint8_t* rdram, recomp_context* ctx) {
    g_scene.store(kSceneNewGame);
    const int course = g_course.exchange(-1);
    if (course < 0) {
        __real_menu_new_game_entry(rdram, ctx);
        return;
    }
    const uint32_t player = word(rdram, kPlayerData);
    if (player >= 0x80000000u && player < 0x80800000u) {
        byte(rdram, player + kItemFlags) |= kItems;
    }
    printf("[SNAP-WEB] course %d\n", course);
    fflush(stdout);
    g_started.fetch_add(1);
    ctx->r2 = uint32_t(course);
}

} // extern "C"
