"""tools/dump_sounds.gd, the dev aid that renders the SoundBank's sounds to .wav files (domain-audio): a smoke test on
the real engine. Run headless on this checkout with `--filter=tinnitus/whine`, a profile name no other profile
contains, it exits 0, says it rendered one sound and writes that profile's one file, a WAV, and nothing else: the
filter kept that profile alone. Skipped with no Godot to be had, as the other real-engine tool tests are.
"""
import subprocess
import tempfile
import unittest
from pathlib import Path

from tools.coverage.tests.support import env_with_godot, godot_binary, needs_godot

ROOT = Path(__file__).resolve().parents[2]
DUMP = ROOT / "tools" / "dump_sounds.gd"
# The profile it renders is the grenade family's (SoundGrenades), listed by the bank and rendered by the synth.
SOURCES = (ROOT / "scenes" / "audio" / "sound_bank.gd", ROOT / "scenes" / "audio" / "sound_grenades.gd",
           ROOT / "scenes" / "audio" / "sound_synth.gd")
PROFILE = "tinnitus/whine"
WAV = "tinnitus_whine_v0.wav"


@needs_godot
class DumpSoundsTests(unittest.TestCase):

    def test_a_filtered_dump_writes_that_profile_alone(self):
        for path in (DUMP,) + SOURCES:
            self.assertTrue(path.is_file(), f"premise: {path.relative_to(ROOT)} exists")
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "out"
            # A log of its own, so the run does not rotate the project's shared user://logs/godot.log.
            r = subprocess.run(
                [godot_binary(), "--headless", "--path", str(ROOT), "--log-file", str(Path(tmp) / "godot.log"),
                 "-s", "res://tools/dump_sounds.gd", "--", f"--out={out}", f"--filter={PROFILE}"],
                cwd=ROOT, capture_output=True, text=True, timeout=300, env=env_with_godot(GODOT_CMD_PORT="off"))
            said = r.stdout + r.stderr
            self.assertEqual(r.returncode, 0, said)
            self.assertNotIn("SCRIPT ERROR", said)
            self.assertIn(PROFILE, said, "it prints the profile's line")
            self.assertIn("1 sounds,", said, "it rendered that one sound")
            written = sorted(p.name for p in out.iterdir()) if out.is_dir() else []
            self.assertEqual(written, [WAV], "the filter kept that profile alone")
            data = (out / WAV).read_bytes()
            self.assertEqual((data[:4], data[8:12]), (b"RIFF", b"WAVE"), "a WAV file")
            self.assertGreater(len(data), 44, "with samples past its header")


if __name__ == "__main__":
    unittest.main()
