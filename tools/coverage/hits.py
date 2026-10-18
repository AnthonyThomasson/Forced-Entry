"""The hit file (tools/coverage/README.md, "Hit file"): reading, atomic writing, merging a run's shards, totals.

  load(path) -> dict          a hit file; ValueError for a `format` or `version` it does not know, OSError if missing
  write(path, data)           atomically: a temp file in the same folder renamed over `path`, so a reader never sees
                              half a file and a failed write leaves the old file whole
  merge(files) -> dict        one run's shard files as one: the same `map_hash` and `source` or ValueError; units
                              concatenated, units sharing an id summed (the first keeps its other fields)
  totals(data) -> {id: hits}  statement id (int) -> hits over every unit; ids never hit are absent
  fired_in(data) -> {id: n}   statement id (int) -> how many units hit it at least once

The probe (probe.gd) writes the same format from inside the game, one `coverage_hits_<pid>.json` per process.
"""
import json
import os
import tempfile
from pathlib import Path

FORMAT = "fe-coverage-hits"
VERSION = 1


def check(data, where="hit file") -> dict:
    """`data` if it is a hit file of this format and version, else ValueError."""
    if not isinstance(data, dict) or data.get("format") != FORMAT or data.get("version") != VERSION:
        raise ValueError(f"{where} is not a {FORMAT} version {VERSION} file")
    return data


def load(path) -> dict:
    with open(path, encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as err:
            raise ValueError(f"{path} is not JSON: {err}") from err
    return check(data, str(path))


def write(path, data) -> None:
    write_json(path, data)


def write_json(path, data) -> None:
    """Write `data` as JSON to `path` atomically (also used for the other run files)."""
    text = json.dumps(data, indent=1)  # fails here, before any file is touched, for data that is not JSON
    path = Path(path)
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(text)
        os.replace(tmp, path)
    except BaseException:
        Path(tmp).unlink(missing_ok=True)
        raise


def merge(files) -> dict:
    """The shard files of one run as one hit file."""
    files = [check(f) for f in files]
    if not files:
        raise ValueError("nothing to merge")
    first = files[0]
    for f in files[1:]:
        if f["map_hash"] != first["map_hash"]:
            raise ValueError(f"hit files of different maps: {first['map_hash']} and {f['map_hash']}")
        if f["source"] != first["source"]:
            raise ValueError(f"hit files of different sources: {first['source']} and {f['source']}")
    units: dict[str, dict] = {}
    for f in files:
        for u in f["units"]:
            if u["id"] not in units:
                units[u["id"]] = {**u, "counts": dict(u["counts"])}
                continue
            counts = units[u["id"]]["counts"]
            for sid, n in u["counts"].items():
                counts[sid] = counts.get(sid, 0) + n
    return {"format": FORMAT, "version": VERSION, "map_hash": first["map_hash"], "source": first["source"],
            "units": list(units.values())}


def totals(data) -> dict[int, int]:
    found: dict[int, int] = {}
    for u in data["units"]:
        for sid, n in u["counts"].items():
            if n > 0:
                found[int(sid)] = found.get(int(sid), 0) + n
    return found


def fired_in(data) -> dict[int, int]:
    found: dict[int, int] = {}
    for u in data["units"]:
        for sid, n in u["counts"].items():
            if n > 0:
                found[int(sid)] = found.get(int(sid), 0) + 1
    return found
