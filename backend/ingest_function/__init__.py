"""Blob-triggered ingest of v2-coachready workouts into Cosmos DB.

TODO (Sprint 1):
  - Parse blob bytes -> WorkoutV2 (Pydantic)
  - Compute derived metrics (NP, IF, TSS, VI, decoupling, best efforts)
  - Upsert into Cosmos workouts collection
  - Update daily_metrics aggregate
"""
from __future__ import annotations

import logging

import azure.functions as func


def main(myblob: func.InputStream) -> None:
    logging.info(
        "Blob trigger fired: name=%s size=%s bytes",
        myblob.name,
        myblob.length,
    )
    # TODO: implement ingest pipeline (Sprint 1)
    raise NotImplementedError("ingest_function not yet implemented")
