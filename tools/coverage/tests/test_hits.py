"""Tests for tools/coverage/hits.py: the hit file format, merging shards, atomic writes.

  hits.load(path) -> dict          reads a hit file; raises ValueError for a file whose `format` or `version` it does
                                   not know (and OSError for a missing one)
  hits.write(path, data)           writes atomically: a temp file in the same folder, renamed over `path`, so a reader
                                   never sees half a file and a failed write leaves the old file as it was
  hits.merge(files) -> dict        the hit files of one run's shards as one: same `map_hash` and `source` or
                                   ValueError; units concatenated, units sharing an id summed
  hits.totals(data) -> {id: hits}  statement id (int) -> hits over every unit; ids never hit are absent
  hits.fired_in(data) -> {id: n}   statement id (int) -> how many units hit it at least once

The format (tools/coverage/README.md, "Hit file") is written out by hand below; so are the expected totals.
"""
import json
import unittest

from tools.coverage import hits
from tools.coverage.tests.support import TempDir

MAP = "a1b2c3"


def unit(uid: str, counts: dict, **extra) -> dict:
    return {"id": uid, "counts": {str(k): v for k, v in counts.items()}, **extra}


def matches(*units, map_hash: str = MAP) -> dict:
    return {"format": "fe-coverage-hits", "version": 1, "map_hash": map_hash, "source": "matches", "units": list(units)}


def tests(*units, map_hash: str = MAP) -> dict:
    return {"format": "fe-coverage-hits", "version": 1, "map_hash": map_hash, "source": "tests", "units": list(units)}


# One serial run over seeds 10..13 (seed 13 an Endless process of three matches), and the same matches spread over
# three shards as parallel processes would write them.
SERIAL = matches(
    unit("10-1", {0: 1, 1: 4, 2: 1}, seed=10, mode="watch", match=1, verdict="DEFENDER WINS", duration=40.0),
    unit("11-1", {0: 1, 1: 2, 3: 7}, seed=11, mode="watch", match=1, verdict="INVADER WINS", duration=55.5),
    unit("12-1", {0: 1, 4: 1}, seed=12, mode="watch", match=1, verdict="TIME UP - DRAW", duration=180.0),
    unit("13-1", {0: 1, 1: 1}, seed=13, mode="endless", match=1, verdict="DEFENDER WINS", duration=30.0),
    unit("13-2", {1: 3, 5: 2}, seed=13, mode="endless", match=2, verdict="DEFENDER WINS", duration=31.0),
    unit("13-3", {1: 1}, seed=13, mode="endless", match=3, verdict="INVADER WINS", duration=12.0),
)
SHARDS = [
    matches(SERIAL["units"][0], SERIAL["units"][3], SERIAL["units"][4], SERIAL["units"][5]),
    matches(SERIAL["units"][1]),
    matches(SERIAL["units"][2]),
]
SERIAL_TOTALS = {0: 4, 1: 11, 2: 1, 3: 7, 4: 1, 5: 2}
SERIAL_FIRED = {0: 4, 1: 5, 2: 1, 3: 1, 4: 1, 5: 1}


class FormatTests(unittest.TestCase):
    def test_write_then_load_round_trips(self):
        with TempDir() as d:
            path = d / "coverage_hits_123.json"
            hits.write(path, SERIAL)
            self.assertEqual(hits.load(path), SERIAL)
            self.assertEqual(json.loads(path.read_text()), SERIAL, "the file is plain JSON in the documented shape")

    def test_load_refuses_an_unknown_format_or_version(self):
        with TempDir() as d:
            for bad in ({**SERIAL, "format": "something-else"}, {**SERIAL, "version": 99}, {"units": []}):
                with self.subTest(bad=list(bad)[:2]):
                    path = d / "bad.json"
                    path.write_text(json.dumps(bad))
                    with self.assertRaises(ValueError):
                        hits.load(path)

    def test_load_of_a_missing_file_raises(self):
        with TempDir() as d, self.assertRaises(OSError):
            hits.load(d / "nope.json")


class AtomicWriteTests(unittest.TestCase):
    def test_a_write_leaves_no_temp_file_behind(self):
        with TempDir() as d:
            hits.write(d / "hits.json", SERIAL)
            hits.write(d / "hits.json", SHARDS[1])
            self.assertEqual([p.name for p in d.iterdir()], ["hits.json"])
            self.assertEqual(hits.load(d / "hits.json"), SHARDS[1])

    def test_a_failed_write_leaves_the_old_file_whole(self):
        with TempDir() as d:
            path = d / "hits.json"
            hits.write(path, SERIAL)
            unwritable = matches(unit("x", {0: 1}, seed=object()))  # not JSON: the write fails part-way
            with self.assertRaises(Exception):
                hits.write(path, unwritable)
            self.assertEqual(hits.load(path), SERIAL)
            self.assertEqual([p.name for p in d.iterdir()], ["hits.json"])


class MergeTests(unittest.TestCase):
    def test_shards_merge_to_the_serial_run_s_totals(self):
        merged = hits.merge(SHARDS)
        self.assertEqual(hits.totals(merged), SERIAL_TOTALS)
        self.assertEqual(hits.totals(SERIAL), SERIAL_TOTALS)
        self.assertEqual(sorted(u["id"] for u in merged["units"]), sorted(u["id"] for u in SERIAL["units"]))

    def test_merge_order_does_not_change_the_totals(self):
        self.assertEqual(hits.totals(hits.merge(list(reversed(SHARDS)))), SERIAL_TOTALS)

    def test_merged_file_keeps_the_format_and_each_unit_s_fields(self):
        merged = hits.merge(SHARDS)
        self.assertEqual((merged["format"], merged["version"], merged["map_hash"], merged["source"]),
                         ("fe-coverage-hits", 1, MAP, "matches"))
        by_id = {u["id"]: u for u in merged["units"]}
        self.assertEqual(by_id["13-2"]["mode"], "endless")
        self.assertEqual(by_id["12-1"]["verdict"], "TIME UP - DRAW")
        self.assertEqual(by_id["11-1"]["duration"], 55.5)

    def test_units_sharing_an_id_are_summed(self):
        a = tests(unit("ai/brain_thinks", {0: 1, 1: 2}))
        b = tests(unit("ai/brain_thinks", {1: 3, 2: 1}), unit("items/gun_fires", {3: 1}))
        merged = hits.merge([a, b])
        by_id = {u["id"]: u for u in merged["units"]}
        self.assertEqual(sorted(by_id), ["ai/brain_thinks", "items/gun_fires"])
        self.assertEqual(by_id["ai/brain_thinks"]["counts"], {"0": 1, "1": 5, "2": 1})

    def test_merge_refuses_files_of_different_maps_or_sources(self):
        with self.assertRaises(ValueError):
            hits.merge([SHARDS[0], matches(unit("20-1", {0: 1}), map_hash="other")])
        with self.assertRaises(ValueError):
            hits.merge([SHARDS[0], tests(unit("ai/x", {0: 1}))])

    def test_fired_in_counts_the_units_that_hit_each_statement(self):
        self.assertEqual(hits.fired_in(SERIAL), SERIAL_FIRED)
        self.assertEqual(hits.fired_in(hits.merge(SHARDS)), SERIAL_FIRED)

    def test_a_killed_shard_s_last_flush_still_counts(self):
        # A process killed mid-match leaves the flush it wrote last: that match's unit with the hits so far.
        killed = matches(unit("14-1", {0: 1, 1: 6}, seed=14, mode="watch", match=1))
        merged = hits.merge(SHARDS + [killed])
        self.assertEqual(hits.totals(merged), {**SERIAL_TOTALS, 0: 5, 1: 17})


class TotalsTests(unittest.TestCase):
    def test_totals_of_an_empty_run_is_empty(self):
        self.assertEqual(hits.totals(matches()), {})

    def test_statement_ids_are_ints_in_the_api_and_strings_in_the_file(self):
        self.assertTrue(all(isinstance(k, int) for k in hits.totals(SERIAL)))
        self.assertTrue(all(isinstance(k, str) for u in SERIAL["units"] for k in u["counts"]))


if __name__ == "__main__":
    unittest.main()
