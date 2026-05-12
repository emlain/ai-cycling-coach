"""Graceful loading of Strava streams from blob storage."""
from __future__ import annotations

import json
import logging
from typing import Any

from azure.core.exceptions import ResourceNotFoundError
from azure.storage.blob import BlobServiceClient


def try_load_stream(
    bsc: BlobServiceClient,
    container: str,
    activity_id: str,
) -> dict[str, list[Any]] | None:
    """Load stream JSON for {activity_id}.

    Returns:
        Dict with keys watts/heartrate/time/cadence/distance/altitude
        (each a list of values), or None if the stream blob does not exist.
    """
    if not activity_id:
        return None
    blob_name = f"{activity_id}.json"
    try:
        bc = bsc.get_blob_client(container=container, blob=blob_name)
        raw = bc.download_blob().readall().decode("utf-8-sig")  # gestisce BOM
        parsed = json.loads(raw)
    except ResourceNotFoundError:
        logging.info("Stream not found: %s/%s (degrading to v2 baseline)", container, blob_name)
        return None
    except Exception as e:
        logging.warning("Stream load failed for %s/%s: %s", container, blob_name, e)
        return None

    # Strava restituisce {watts: {data: [...]}, hr: {data: [...]}, ...}
    out: dict[str, list[Any]] = {}
    if isinstance(parsed, dict):
        for key in ("watts", "heartrate", "time", "cadence", "distance", "altitude", "velocity_smooth"):
            section = parsed.get(key)
            if isinstance(section, dict) and isinstance(section.get("data"), list):
                out[key] = section["data"]
    return out or None
