#!/usr/bin/env python3
"""The panel's Audiobooks source: sign-in card, loading, library, play.

Renders the real Panel.qml (tests/qml/AudiblePanelScene.qml) on the Audiobooks
source with a fake service and a fake Audible source, offscreen, the same way
test_panel_settings.py does (the shell's KeyboardPanel swapped for
tests/qml/stub/KeyboardPanel.qml). Set SOLFA_AUDIBLE_FRAMES to a directory to
keep a PNG of each state. Skips when Quickshell, the Omarchy shell or a
desktop session is not available.
"""
import testenv  # noqa: F401 - isolates HOME/XDG_*/SOLFA_* before anything else runs
import json
import os
import re
import shutil
import subprocess
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SHELL_DIR = os.path.join(os.environ.get("OMARCHY_PATH", "/usr/share/omarchy"), "shell")
QS = shutil.which(os.environ.get("QS_TOOL", "qs"))


def render(workdir, frames=None):
    cfg = os.path.join(workdir, "scene")
    ui = os.path.join(cfg, "Ui")
    os.makedirs(ui)
    shell_ui = os.path.join(SHELL_DIR, "Ui")
    for name in os.listdir(shell_ui):
        src = os.path.join(HERE, "qml", "stub", name) if name == "KeyboardPanel.qml" else os.path.join(shell_ui, name)
        os.symlink(src, os.path.join(ui, name))
    for name, target in (("Commons", os.path.join(SHELL_DIR, "Commons")),
                         ("views", os.path.join(ROOT, "views")), ("lib", os.path.join(ROOT, "lib")),
                         ("VibeStagePanel.qml", os.path.join(ROOT, "Panel.qml")),
                         ("shell.qml", os.path.join(HERE, "qml", "AudiblePanelScene.qml"))):
        os.symlink(target, os.path.join(cfg, name))
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen", XDG_RUNTIME_DIR=workdir)
    if frames:
        for n in (1, 2, 3, 4):
            env["SOLFA_SCENE_OUT_%d" % n] = os.path.join(frames, "audible-%d.png" % n)
    runtime = os.environ.get("XDG_RUNTIME_DIR", "")
    display = os.environ.get("WAYLAND_DISPLAY", "")
    if runtime and display and not os.path.isabs(display):
        env["WAYLAND_DISPLAY"] = os.path.join(runtime, display)
    run = subprocess.run([QS, "-p", os.path.join(cfg, "shell.qml"), "--no-color"], env=env,
                         capture_output=True, text=True, timeout=60)
    m = re.search(r"STATE (\{.*\})", run.stdout + run.stderr)
    return (json.loads(m.group(1)) if m else None), (run.stdout + run.stderr)[-3000:]


@unittest.skipUnless(QS and os.path.isdir(os.path.join(SHELL_DIR, "Ui")) and os.environ.get("WAYLAND_DISPLAY"),
                     "Quickshell, the Omarchy shell or a desktop session is missing")
class AudiblePanel(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.workdir = tempfile.mkdtemp(prefix="vibe-abp-")
        cls.state, cls.log = render(cls.workdir, os.environ.get("SOLFA_AUDIBLE_FRAMES"))

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.workdir, ignore_errors=True)

    def test_scene_ran(self):
        self.assertIsNotNone(self.state, self.log)

    def test_signed_out_is_the_sign_in_card(self):
        s = self.state["signedOut"]
        self.assertTrue(s["signIn"], self.log)
        self.assertFalse(s["loading"], self.log)
        self.assertTrue(s["hero"], self.log)
        # Opening the panel on Audiobooks wakes the source.
        self.assertIn("refreshIfStale", s["shownCalls"], self.log)

    def test_library_on_its_way_is_the_loading_line(self):
        s = self.state["loading"]
        self.assertFalse(s["signIn"], self.log)
        self.assertTrue(s["loading"], self.log)

    def test_library_lists_the_books_and_marks_the_one_playing(self):
        s = self.state["library"]
        self.assertTrue(s["view"], self.log)
        self.assertFalse(s["signIn"], self.log)
        self.assertFalse(s["loading"], self.log)
        # It opens on In Progress: the one book started; All has the three.
        self.assertEqual(s["tab"], "progress", self.log)
        self.assertEqual(s["rows"], 1, self.log)
        self.assertEqual(len(s["keys"]["allTitles"]), 3, self.log)
        self.assertTrue(s["firstCurrent"], self.log)
        self.assertEqual(s["firstSubtitle"], "Ada Example · read by Sam Reader", self.log)
        self.assertEqual(s["firstItem"]["progressText"], "1% · 9 h 50 min left", self.log)

    def test_keys_leave_the_hidden_sign_in_fields(self):
        # Signed in, the card hides: its fields must not keep the keyboard.
        self.assertTrue(self.state["signedOut"]["inputFocused"], self.log)
        self.assertFalse(self.state["library"]["inputFocused"], self.log)

    def test_keys(self):
        self.assertEqual(self.state["library"]["calls"], ["play:B0AAAAAAA2", "playPause", "cycleSpeed", "stop"], self.log)


if __name__ == "__main__":
    unittest.main()
