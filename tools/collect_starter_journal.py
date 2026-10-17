#!/usr/bin/env python3
"""Save a small, varied archive collection without changing observation metadata.

This performs the same persisted change as the app's Save to Journal action:
only ``collected`` becomes true on existing, non-sample archive observations.
Stop the app before replacing its journal, and back up the original first.
No photographs, locations, identifiers, notes, or source credits are printed.
"""

from __future__ import annotations

import argparse
import copy
import json
import os
from pathlib import Path
import tempfile


# Public iNaturalist catalog records bundled with Nature Relay. These names are
# fixed public labels, rather than values read from a person's private journal.
STARTER_SPECIES = (
    (108094155, "California poppy"),
    (190730575, "California fuchsia"),
    (3504980, "California Wild Rose"),
    (41089404, "Miniature Lupine"),
    (38921878, "Pacific trillium"),
    (57183487, "blue oak"),
    (80177721, "California buckeye"),
    (144270631, "giant chain fern"),
    (198368689, "dendroalsia moss"),
    (115013259, "Broad-leaved Stonecrop"),
    (250218495, "Anna's Hummingbird"),
    (193261218, "California Quail"),
    (144885874, "California Scrub-Jay"),
    (73117506, "Great Horned Owl"),
    (363792117, "California Tortoiseshell"),
    (341559440, "Painted Lady"),
    (173325997, "Anise Swallowtail"),
    (122179989, "California Ground Squirrel"),
    (73589287, "Western Fence Lizard"),
    (172197511, "Black-tailed Jackrabbit"),
)
TARGET_COUNT = 20


def visible_collected(records: list[dict]) -> int:
    return sum(record["collected"] and not record["isSample"] for record in records)


def reject_nonfinite(_value: str) -> None:
    raise ValueError("Journal contains a non-finite number.")


def prepare_collection(original: list[dict]) -> tuple[list[dict], list[str]]:
    if not isinstance(original, list) or not all(isinstance(row, dict) for row in original):
        raise ValueError("Journal must be an array of observation objects.")
    for row in original:
        if type(row.get("collected")) is not bool or type(row.get("isSample")) is not bool:
            raise ValueError("Every observation must contain boolean collected and isSample fields.")
    updated = copy.deepcopy(original)
    missing = max(0, TARGET_COUNT - visible_collected(original))
    selected: list[str] = []
    if not missing:
        return updated, selected

    # Validate all selectable records before mutating anything or writing output.
    candidates: list[tuple[dict, str]] = []
    for source_id, public_name in STARTER_SPECIES:
        matches = [row for row in updated if row.get("sourceRecordID") == source_id]
        if len(matches) != 1:
            raise ValueError("A required public catalog record is absent or duplicated.")
        record = matches[0]
        if record["isSample"] or record.get("isSourceArchive") is not True:
            raise ValueError("A selected catalog record is not a visible source archive observation.")
        if not record["collected"]:
            candidates.append((record, public_name))
    if len(candidates) < missing:
        raise ValueError("There are not enough eligible archive observations to reach twenty.")
    for record, public_name in candidates[:missing]:
        record["collected"] = True
        selected.append(public_name)

    # Fail closed if this tool ever changes anything besides false -> true flags.
    for before, after in zip(original, updated):
        before_fields = {key: value for key, value in before.items() if key != "collected"}
        after_fields = {key: value for key, value in after.items() if key != "collected"}
        if before_fields != after_fields or (before["collected"] and not after["collected"]):
            raise ValueError("Observation preservation check failed.")
    if visible_collected(updated) != TARGET_COUNT:
        raise ValueError("Collection count check failed.")
    return updated, selected


def atomic_write(destination: Path, data: bytes) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary: str | None = None
    try:
        with tempfile.NamedTemporaryFile(dir=destination.parent, prefix=".journal-", delete=False) as handle:
            temporary = handle.name
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, destination)
        temporary = None
    finally:
        if temporary is not None:
            Path(temporary).unlink(missing_ok=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    try:
        original_bytes = args.input.read_bytes()
        original = json.loads(original_bytes, parse_constant=reject_nonfinite)
        updated, selected = prepare_collection(original)
        # An already populated journal is not rewritten when input == output.
        if selected:
            data = json.dumps(updated, ensure_ascii=False, allow_nan=False, separators=(",", ":")).encode("utf-8")
            atomic_write(args.output, data)
        elif args.input.resolve() != args.output.resolve():
            atomic_write(args.output, original_bytes)
        print(json.dumps({
            "records": len(original),
            "visibleCollectedBefore": visible_collected(original),
            "visibleCollectedAfter": visible_collected(updated),
            "addedCount": len(selected),
            "selectedPublicNames": selected,
        }, ensure_ascii=False))
    except (OSError, ValueError, TypeError) as error:
        # Do not echo file paths, journal contents, or JSON parser excerpts.
        if isinstance(error, json.JSONDecodeError):
            message = "Journal is not valid JSON."
        elif isinstance(error, OSError):
            message = "Could not read or atomically write the journal file."
        else:
            message = str(error)
        parser.exit(1, message + "\n")


if __name__ == "__main__":
    main()
