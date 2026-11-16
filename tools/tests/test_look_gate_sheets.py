"""tools/look_gate_sheets.py: the contact sheets of the look gate's shots (`tests/general/render_3d_look_gate_windowed_test.gd`).

A folder of `<scene>_<3d|2d>_z<zoom>_yaw<yaw>.png` becomes, per scene, `<scene>_3d.png` and `<scene>_2d_vs_3d.png`; a
file that is not a shot is left alone. Skipped where Pillow is not installed (the tool says so itself).
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

    def test_a_scene_with_both_modes_gets_a_grid_and_a_side_by_side_sheet(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            for name in ("kitchen_3d_z1_yaw0.png", "kitchen_3d_z0p5_yaw90.png", "kitchen_2d_z1_yaw0.png"):
                self.shot(folder, name)
            (folder / "notes.png").write_bytes(b"not a shot")
            done = self.run_tool(folder)
            self.assertEqual(done.returncode, 0, done.stderr)
            sheets = sorted(p.name for p in (folder / "sheets").iterdir())
            self.assertEqual(sheets, ["kitchen_2d_vs_3d.png", "kitchen_3d.png"])

    def test_a_scene_with_only_3d_shots_has_no_side_by_side_sheet(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            self.shot(folder, "street_3d_z2_yaw0.png")
            self.assertEqual(self.run_tool(folder).returncode, 0)
            self.assertEqual([p.name for p in (folder / "sheets").iterdir()], ["street_3d.png"])


if __name__ == "__main__":
    unittest.main()
