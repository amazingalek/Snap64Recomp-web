// Plays Pokémon Snap's courses on the page for web/record_shaders.sh and web/play_plan.json (the plans load it into
// the page). The page's web/survey.cpp says which scene the game is in (Module._snap_web_scene: 0-6 a course, 8 the
// main menu, 9 the camera check, 11 and 13 Oak's lab, 14 the report, 100 the new game's name entry) and starts a
// course from the main menu's New Game (Module._snap_web_course), so:
// - sceneReached(scene, ms) waits until the game is in that scene;
// - course(scene, ms) asks for a course and presses Start until the main menu's New Game has started it;
// - ride(seconds) plays a course as it rolls on by itself: the view swung about with the stick, the camera taken out
//   with Z and a photo taken with A, the Apple and the Pester Ball thrown (A and B outside the camera), the Poke Flute
//   played (C up), the Dash Engine run (R), until the seconds are up or the course has ended;
// - browse(seconds) presses through the screens after a course;
// - quit(ms) quits the course being played from its pause menu (Start, the stick down to Quit, A), as a player does,
//   and resolves true once the game has left it, false after ms (15 s if not given);
// - next(scene, seconds) takes the game from the screens after a course (the camera check, Oak's lab, the report)
//   to another course, for a plan that plays more than one in a load: the main menu, where survey.cpp starts one,
//   comes only at boot. A menu scene ends by setting the scene loop's next scene (the decomp's D_800AF3C0, which
//   func_800AADF0 sets, src/app_render/53AD0.c) and returning it a frame or more later, so a worker holds that word
//   at the course asked for while next() goes through the screens (the camera check left by To Prof. Oak, Oak's lab
//   by a course or by saving and not going on): the first screen that ends starts that course. Where the hold loses,
//   next() goes on from the screen the game chose (below). Resolves with the scene once the game is in it, false
//   after the seconds.
// - later(label, promise) starts a long one (a ride, the boot) and prints "[plan] <label>: <value>" when it resolves:
//   a plan's eval gets 30 s to answer, so a plan waits for that line with an until step and checks the value with a
//   need on planWaits[label].
// The keys are the page's defaults (src/input.cpp): A X, B Z, Z Left Shift, Start Return, R E, C up I, the stick WASD.
(() => {
  const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
  const key = (type, code, k, keyCode) =>
    window.dispatchEvent(new KeyboardEvent(type, { bubbles: true, code, key: k, keyCode, which: keyCode }));
  const keys = {
    a: ['KeyX', 'x', 88], b: ['KeyZ', 'z', 90], z: ['ShiftLeft', 'Shift', 16], start: ['Enter', 'Enter', 13],
    r: ['KeyE', 'e', 69], cUp: ['KeyI', 'i', 73], up: ['KeyW', 'w', 87], down: ['KeyS', 's', 83],
    left: ['KeyA', 'a', 65], right: ['KeyD', 'd', 68],
  };
  const down = (name) => key('keydown', ...keys[name]);
  const up = (name) => key('keyup', ...keys[name]);
  // The game reads its controller once a frame, so a press is held for a few.
  const press = async (name, ms = 120) => { down(name); await sleep(ms); up(name); await sleep(ms); };
  const scene = () => Module._snap_web_scene();
  // A test that throws (the program not there yet) counts as false.
  const until = async (test, ms) => {
    for (const end = Date.now() + ms; Date.now() < end; await sleep(100)) {
      try { if (test()) return true; } catch { /* not yet */ }
    }
    return false;
  };

  window.snapScene = scene;
  window.sceneReached = (wanted, ms) => until(() => scene() === wanted, ms);
  window.course = async (wanted, ms) => {
    const started = Module._snap_web_courses_started();
    Module._snap_web_course(wanted);
    for (const end = Date.now() + ms; Date.now() < end;) {
      if (Module._snap_web_courses_started() > started && scene() === wanted) return true;
      await press('start', 150);
      await sleep(600);
    }
    return false;
  };
  window.ride = async (seconds) => {
    const end = Date.now() + seconds * 1000;
    const here = scene();
    const going = () => Date.now() < end && scene() === here;
    const sways = ['left', 'right', 'up', 'down'];
    for (let round = 0; going(); round++) {
      // The camera out, the view swung one way and back, a photo every ~0.6 s.
      down('z');
      await sleep(400);
      const sway = sways[round % sways.length];
      const back = { left: 'right', right: 'left', up: 'down', down: 'up' }[sway];
      for (const way of [sway, back]) {
        down(way);
        for (let i = 0; i < 3 && going(); i++) {
          await sleep(300);
          await press('a');
        }
        up(way);
      }
      up('z');
      await sleep(300);
      // Outside the camera: an item thrown, the Flute played, now and then the Dash Engine.
      await press(['a', 'b', 'cUp'][round % 3]);
      if (round % 4 === 3) await press('r', 600);
      await sleep(800);
    }
    for (const name of Object.keys(keys)) up(name);
    return scene() !== here;
  };
  // browse(seconds) goes through the screens after a course (the camera check, Oak's report) by pressing A, now and
  // then the stick down and Start, and resolves with the scenes it passed through.
  window.browse = async (seconds) => {
    const seen = [scene()];
    const end = Date.now() + seconds * 1000;
    for (let i = 0; Date.now() < end; i++) {
      await press(['a', 'a', 'down', 'a', 'start'][i % 5], 150);
      await sleep(900);
      if (scene() !== seen[seen.length - 1]) seen.push(scene());
    }
    return seen;
  };
  window.quit = async (ms = 15000) => {
    const here = scene();
    await press('start', 150);
    await sleep(1500);
    await press('down', 200);
    await sleep(600);
    await press('a', 150);
    return until(() => scene() !== here, ms);
  };

  // The scene loop's next scene, held by a worker that rewrites it in a loop with no sleeps while hold[0] is a scene
  // and sleeps in Atomics.wait while it is -1 (left alone): a worker that looked every millisecond lost about half its
  // races. RDRAM is found as N64Recomp-browser's n64r finds it.
  const NEXT_SCENE = 0x800AF3C0;
  let hold = null;
  const holdNext = (wanted) => {
    if (!hold) {
      const h = HEAPU32;
      let base = -1;
      for (let i = 2; i < h.length - 8; i++) {
        if (h[i] === 0xB0000000 && h[i - 2] <= 2 && (h[i + 4] === 0x400000 || h[i + 4] === 0x800000)) { base = i * 4 - 0x308; break; }
      }
      if (base < 0) throw new Error('RDRAM not found');
      hold = new Int32Array(new SharedArrayBuffer(8));
      hold[0] = -1;
      const source = 'onmessage = ({ data: [memory, at, hold] }) => { const word = new Int32Array(memory); ' +
        'for (;;) { const wanted = Atomics.load(hold, 0); if (wanted < 0) { Atomics.wait(hold, 0, wanted); continue; } ' +
        'if (Atomics.load(word, at) !== wanted) Atomics.store(word, at, wanted); } };';
      const worker = new Worker(URL.createObjectURL(new Blob([source], { type: 'text/javascript' })));
      worker.postMessage([HEAPU32.buffer, (base + (NEXT_SCENE - 0x80000000)) >>> 2, hold]);
    }
    Atomics.store(hold, 0, wanted);
    Atomics.notify(hold, 0);
  };
  // The worker can lose the race on a busy host (the word is read a frame after it is set), so the game can land in
  // any screen, and each is left its own way:
  // - the camera check (9): B backs out of any of its pages to its menu, up from its first button wraps to the last,
  //   To Prof. Oak, and A on it and A on "No pictures to show to Prof. Oak?" end it (the decomp's
  //   src/camera_check/87D1A0.c);
  // - Oak's lab (11, 13): A twice, then A or B in turn (src/oaks_lab/8A8A50.c). With the cursor on a course, A A A
  //   takes it ("Should I take this course? Let's go!"); on Save, A A saves and B answers "Would you like to keep
  //   going?" with No, which ends the lab for the main menu, where A would come back to the lab's menu; every third
//   round the cursor moves down first;
  // - the main menu (8): course() starts the course asked for, as the plan's start does;
  // - a course not asked for: quit() leaves it, for the camera check or the lab;
  // - any other screen (the report, the photo check): A goes on.
  window.next = async (wanted, seconds) => {
    holdNext(wanted);
    const end = Date.now() + seconds * 1000;
    let last = null;
    let round = 0;
    while (scene() !== wanted && Date.now() < end) {
      const here = scene();
      if (here !== last) { last = here; console.log('[next] scene ' + here); }
      if (here === 9) {
        for (const name of ['b', 'b', 'up', 'a', 'a']) { await press(name, 150); await sleep(900); }
        await sleep(1500);
      } else if (here === 11 || here === 13) {
        if (round % 3 === 2) { await press('down', 200); await sleep(900); }
        await press('a', 150);
        await sleep(1500);
        await press('a', 150);
        // Saving takes about 100 of the game's frames before it asks.
        await sleep(4000);
        await press(round++ % 2 ? 'b' : 'a', 150);
        await sleep(3000);
      } else if (here === 8) {
        await course(wanted, Math.max(1000, end - Date.now()));
      } else if (here >= 0 && here <= 6) {
        await sleep(5000);
        if (scene() === here) await quit();
      } else {
        await press('a', 150);
        await sleep(900);
      }
    }
    holdNext(-1);
    for (const name of Object.keys(keys)) up(name);
    return scene() === wanted && scene();
  };

  window.planWaits = window.planWaits || {};
  window.later = (label, promise) => {
    window.planWaits[label] = promise;
    // Printed a second late, so that the plan's until step after the eval that started it is waiting by then.
    const say = (text) => setTimeout(() => console.log('[plan] ' + label + ': ' + text), 1000);
    promise.then((v) => say(JSON.stringify(v)), (e) => say(String(e)));
    return label + ' started';
  };
})();
