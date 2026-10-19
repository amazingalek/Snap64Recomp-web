// Plays Pokémon Snap's courses on the page for web/record_shaders.sh and tools/play_plan.json (the plans load it into
// the page). The page's web/survey.cpp says which scene the game is in (Module._snap_web_scene: 0-6 a course, 8 the
// main menu, 100 the new game's name entry) and starts a course from the main menu's New Game
// (Module._snap_web_course), so:
// - sceneReached(scene, ms) waits until the game is in that scene;
// - course(scene, ms) asks for a course and presses Start until the main menu's New Game has started it;
// - ride(seconds) plays a course as it rolls on by itself: the view swung about with the stick, the camera taken out
//   with Z and a photo taken with A, the Apple and the Pester Ball thrown (A and B outside the camera), the Poke Flute
//   played (C up), the Dash Engine run (R), until the seconds are up or the course has ended;
// - browse(seconds) presses through the screens after a course.
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
})();
