#!/usr/bin/env python3
"""The Audiobooks source talks to the real audible bridge.

Runs tests/qml/AudibleSourceScene.qml (the real lib/AudibleSource.qml) in a
private Quickshell, offscreen. AudibleSource starts bin/audible-bridge itself
(serve --lifeline, a cleared environment) in a throwaway XDG tree, so it is
signed out: the probe, the replies' error codes, the sign-in guard and the
player poll are checked, and Amazon is never contacted. Skips when Quickshell
or a desktop session is not available.
"""
import testenv  # noqa: F401 - isolates HOME/XDG_*/SOLFA_* before anything else runs
import os
import shutil
import subprocess
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
QS = shutil.which(os.environ.get("QS_TOOL", "qs"))
PLUGIN_ID = "ninepointlabs.vibe-stage"


def run_scene(scene_ms=20000):
    workdir = tempfile.mkdtemp(prefix="vibe-ab-")
    # AF_UNIX paths are short (108 bytes): the runtime dir lives under /tmp.
    runtime = tempfile.mkdtemp(prefix="vibe-r-", dir="/tmp")
    try:
        cfg = os.path.join(workdir, "scene")
        os.mkdir(cfg)
        os.symlink(os.path.join(ROOT, "lib"), os.path.join(cfg, "lib"))
        os.symlink(os.path.join(HERE, "qml", "AudibleSourceScene.qml"), os.path.join(cfg, "shell.qml"))
        plugin_runtime = os.path.join(runtime, PLUGIN_ID)
        os.mkdir(plugin_runtime, 0o700)
        env = dict(os.environ, QT_QPA_PLATFORM="offscreen", XDG_RUNTIME_DIR=runtime,
                   VIBE_PLUGIN_DIR=ROOT, VIBE_RUNTIME_DIR=plugin_runtime, VIBE_SCENE_MS=str(scene_ms))
        env.pop("DISPLAY", None)
        session_runtime = os.environ.get("XDG_RUNTIME_DIR", "")
        display = os.environ.get("WAYLAND_DISPLAY", "")
        if session_runtime and display and not os.path.isabs(display):
            env["WAYLAND_DISPLAY"] = os.path.join(session_runtime, display)
        run = subprocess.run([QS, "-p", os.path.join(cfg, "shell.qml"), "--no-color"], env=env,
                             capture_output=True, text=True, timeout=90)
        log = run.stdout + run.stderr
        events = [line.split("qml: ", 1)[1] for line in log.splitlines() if "qml: " in line]
        return events, log[-4000:]
    finally:
        shutil.rmtree(workdir, ignore_errors=True)
        shutil.rmtree(runtime, ignore_errors=True)


@unittest.skipUnless(QS and os.environ.get("WAYLAND_DISPLAY") and os.path.exists("/usr/bin/python3"),
                     "Quickshell, a desktop session or /usr/bin/python3 is missing")
class AudibleSourceSignedOut(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.events, cls.log = run_scene()

    def find(self, prefix):
        return [e for e in self.events if e.startswith(prefix)]

    def test_starts_the_bridge_and_probes_it(self):
        self.assertIn("STATE bridgeUp true", self.events, self.log)
        probed = self.find("STATE probed")
        self.assertEqual(len(probed), 1, self.log)
        self.assertIn("authenticated=false", probed[0], self.log)
        self.assertNotIn("TIMEOUT", self.events, self.log)

    def test_signed_out_health_line(self):
        probed = self.find("STATE probed")[0]
        if "available=true" in probed:
            self.assertIn("health=Not signed in to Audible", probed, self.log)
        else:
            self.assertIn("health=The Audible helper needs the audible Python package", probed, self.log)

    def test_library_is_refused_signed_out(self):
        reply = self.find("REPLY library")
        self.assertEqual(len(reply), 1, self.log)
        self.assertIn("ok=false", reply[0], self.log)
        self.assertRegex(reply[0], r"code=(not_authenticated|missing_dependency)$", self.log)

    def test_player_answers_idle(self):
        self.assertIn("REPLY player ok=true active=false", self.events, self.log)
        self.assertIn("DONE active=false playing=false lastError=", self.events, self.log)

    def test_guards_never_reach_the_bridge(self):
        self.assertIn("LOGIN empty false Enter your Amazon email and password.", self.events, self.log)
        self.assertIn("PLAY signed-out false", self.events, self.log)

    def test_sort_orders_a_copy(self):
        # Recent is the bridge's order; title and author sort naturally ("Book 2"
        # before "book 10"), case aside, blanks last, ties by title; s cycles round.
        self.assertIn("SORT recent:Recent:A1,A2,A3,A4 title:Title:A3,A2,A1,A4 author:Author:A2,A3,A1,A4"
                      " recent:Recent:A1,A2,A3,A4 library=A1,A2,A3,A4", self.events, self.log)


if __name__ == "__main__":
    unittest.main()
