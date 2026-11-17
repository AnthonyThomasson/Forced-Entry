"""tools/look_gate_sheets.py: the contact sheets of the look gate's shots (`tests/general/render_3d_look_gate_windowed_test.gd`).

A folder of `<scene>_z<zoom>_yaw<yaw>.png` becomes, per scene, one `<scene>.png` grid; a file that is not a shot is
left alone. Skipped where Pillow is not installed (the tool says so itself).
"""
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TOOL = ROOT / "tools" / "look_gate_sheets.py"

try:
    from PIL import Image
except ImportError:  # pragma: no cover
    Image = None


@unittest.skipIf(Image is None, "Pillow is not installed")
class LookGateSheetsTests(unittest.TestCase):
    def run_tool(self, folder: Path) -> subprocess.CompletedProcess:
        return subprocess.run(
            [sys.executable, "-I", str(TOOL), str(folder)], capture_output=True, text=True, check=False
        )

    def shot(self, folder: Path, name: str) -> None:
        Image.new("RGB", (64, 36), (120, 90, 60)).save(folder / name)

    def test_each_scene_gets_one_grid_and_a_file_that_is_no_shot_is_left_alone(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            for name in ("kitchen_z1_yaw0.png", "kitchen_z0p5_yaw90.png", "street_z2_yaw0.png"):
                self.shot(folder, name)
            (folder / "notes.png").write_bytes(b"not a shot")
            done = self.run_tool(folder)
            self.assertEqual(done.returncode, 0, done.stderr)
            sheets = sorted(p.name for p in (folder / "sheets").iterdir())
            self.assertEqual(sheets, ["kitchen.png", "street.png"])


if __name__ == "__main__":
    unittest.main()
