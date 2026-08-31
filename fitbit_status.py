#!/usr/bin/env python3
"""Fetches today's Fitbit stats from the Google Health API.

Prints one JSON object to stdout for the Fit Gauge bar widget to consume.
A metric that fails (missing OAuth scope, API quirk, etc.) comes back as
null with a note in "warnings" rather than failing the whole call - the
widget should always get a valid JSON line to parse, even in degraded
form. Run standalone to (re)authenticate: python fitbit_status.py
"""

import json
import sys
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

import requests
from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import InstalledAppFlow

CONFIG_DIR = Path.home() / ".config" / "fit-gauge"
CLIENT_SECRET_PATH = CONFIG_DIR / "client_secret.json"
CREDENTIALS_PATH = CONFIG_DIR / "credentials.json"
API_BASE = "https://health.googleapis.com/v4"

# Union of every scope the metrics below need. Google only grants what the
# user actually consents to on the OAuth screen; a metric whose scope wasn't
# granted 403s with MISSING_OAUTH_SCOPE, which fetch_* turns into a warning
# instead of failing the whole run. Re-run this script interactively after
# adding a scope here to pick up the broader consent.
SCOPES = [
    "https://www.googleapis.com/auth/googlehealth.activity_and_fitness.readonly",
    "https://www.googleapis.com/auth/googlehealth.health_metrics_and_measurements.readonly",
    "https://www.googleapis.com/auth/googlehealth.sleep.readonly",
]


def get_credentials() -> Credentials:
    if CREDENTIALS_PATH.exists():
        stored_scopes = json.loads(CREDENTIALS_PATH.read_text()).get("scopes") or SCOPES
        creds = Credentials.from_authorized_user_file(str(CREDENTIALS_PATH), stored_scopes)
        if creds.expired and creds.refresh_token:
            creds.refresh(Request())
            save_credentials(creds)
        return creds

    flow = InstalledAppFlow.from_client_secrets_file(str(CLIENT_SECRET_PATH), SCOPES)
    creds = flow.run_local_server(port=0)
    save_credentials(creds)
    return creds


def save_credentials(creds: Credentials) -> None:
    CREDENTIALS_PATH.write_text(creds.to_json())
    CREDENTIALS_PATH.chmod(0o600)


def fetch_data_points(creds: Credentials, data_type: str, start_time: str, json_field: str) -> list:
    """Lists raw data points for `data_type` since `start_time`, paging
    through nextPageToken. Returns the list of values found under
    `json_field` in each point."""
    filter_field = data_type.replace("-", "_")
    url = f"{API_BASE}/users/me/dataTypes/{data_type}/dataPoints"
    params = {"page_size": 1000, "filter": f'{filter_field}.interval.start_time >= "{start_time}"'}
    points = []
    while True:
        response = requests.get(
            url,
            headers={"Authorization": f"Bearer {creds.token}", "Accept": "application/json"},
            params=params,
            timeout=10,
        )
        response.raise_for_status()
        body = response.json()
        points.extend(p[json_field] for p in body.get("dataPoints", []) if json_field in p)
        next_token = body.get("nextPageToken")
        if not next_token:
            return points
        params = {**params, "page_token": next_token}


def fetch_daily_rollup(creds: Credentials, data_type: str) -> dict | None:
    """POSTs a 1-day rollup for `data_type` and returns today's bucket."""
    today = date.today()
    tomorrow = today + timedelta(days=1)
    url = f"{API_BASE}/users/me/dataTypes/{data_type}/dataPoints:dailyRollUp"
    body = {
        "range": {
            "start": {"date": {"year": today.year, "month": today.month, "day": today.day}},
            "end": {"date": {"year": tomorrow.year, "month": tomorrow.month, "day": tomorrow.day}},
        },
        "windowSizeDays": 1,
    }
    response = requests.post(
        url,
        headers={"Authorization": f"Bearer {creds.token}", "Accept": "application/json"},
        json=body,
        timeout=10,
    )
    response.raise_for_status()
    buckets = response.json().get("rollupDataPoints", [])
    return buckets[0] if buckets else None


def safe_metric(warnings: list, label: str, fn, *args):
    """Runs one metric fetch; on any failure, records a warning and
    degrades that single metric to None instead of failing the whole run."""
    try:
        return fn(*args)
    except Exception as exc:  # noqa: BLE001 - deliberately broad, see docstring
        warnings.append(f"{label}: {exc}")
        return None


def build_status() -> dict:
    creds = get_credentials()
    warnings: list[str] = []
    start_of_day = datetime.now(timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0)
    start_time = start_of_day.strftime("%Y-%m-%dT%H:%M:%SZ")

    steps_points = safe_metric(warnings, "steps", fetch_data_points, creds, "steps", start_time, "steps") or []
    steps_total = sum(int(p.get("count", 0)) for p in steps_points) if steps_points else None

    azm_points = (
        safe_metric(
            warnings, "activeZoneMinutes", fetch_data_points,
            creds, "active-zone-minutes", start_time, "activeZoneMinutes",
        )
        or []
    )
    azm_total = sum(int(p.get("activeZoneMinutes", 0)) for p in azm_points) if azm_points else None

    calories_bucket = safe_metric(warnings, "calories", fetch_daily_rollup, creds, "total-calories")
    calories_total = (
        round(calories_bucket["totalCalories"]["kcalSum"]) if calories_bucket else None
    )

    # Field names below (dailyRestingHeartRate / sleep) follow the
    # <camelCase of the data type> convention confirmed for steps and
    # active-zone-minutes, but are UNVERIFIED - both currently 403 with
    # MISSING_OAUTH_SCOPE until a re-consent grants health_metrics_and_
    # measurements.readonly and sleep.readonly. Re-check the actual JSON
    # shape the first time these come back with real data.
    resting_hr_points = (
        safe_metric(
            warnings, "restingHeartRate", fetch_data_points,
            creds, "daily-resting-heart-rate", start_time, "dailyRestingHeartRate",
        )
        or []
    )
    resting_hr = resting_hr_points[-1].get("beatsPerMinute") if resting_hr_points else None

    sleep_points = (
        safe_metric(warnings, "sleep", fetch_data_points, creds, "sleep", start_time, "sleep") or []
    )
    sleep_summary = sleep_points[-1] if sleep_points else None

    return {
        "ok": True,
        "fetchedAtIso": datetime.now(timezone.utc).isoformat(),
        "steps": steps_total,
        "activeZoneMinutes": azm_total,
        "calories": calories_total,
        "restingHeartRate": resting_hr,
        "sleep": (
            {"minutesAsleep": sleep_summary.get("minutesAsleep"), "minutesAwake": sleep_summary.get("minutesAwake")}
            if sleep_summary
            else None
        ),
        "warnings": warnings,
    }


if __name__ == "__main__":
    try:
        print(json.dumps(build_status()))
    except Exception as exc:  # keep the widget's Process handler simple: one line, always
        print(json.dumps({"ok": False, "error": str(exc)}))
        sys.exit(1)
