"""HTTP API for the AI Cycling Coach.

Planned routes (Sprint 2+):
  GET  /workouts?from=...&to=...
  GET  /workouts/{activity_id}
  GET  /trends?metric=ctl|atl|tsb
  GET  /best-efforts
  POST /chat   { message, history? } -> { answer, citations[] }
"""
from __future__ import annotations

import json
import logging

import azure.functions as func


def main(req: func.HttpRequest) -> func.HttpResponse:
    logging.info("API request: %s %s", req.method, req.url)
    return func.HttpResponse(
        body=json.dumps({"status": "scaffold", "message": "API not yet implemented"}),
        mimetype="application/json",
        status_code=501,
    )
