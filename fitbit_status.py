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

import keyring
import requests
from google.auth.exceptions import GoogleAuthError
from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import InstalledAppFlow

CONFIG_DIR = Path.home() / ".config" / "fit-gauge"
# Legacy plaintext locations - read once for a one-time migration into the
# keyring (see load_client_config/load_stored_credentials_json below), then
# deleted. Nothing writes to these paths anymore.
CLIENT_SECRET_PATH = CONFIG_DIR / "client_secret.json"
CREDENTIALS_PATH = CONFIG_DIR / "credentials.json"
API_BASE = "https://health.googleapis.com/v4"

KEYRING_SERVICE = "fit-gauge"
KEYRING_CREDENTIALS_ACCOUNT = "google-health-credentials"
KEYRING_CLIENT_SECRET_ACCOUNT = "google-health-client-secret"

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


def migrate_client_secret_if_present() -> None:
    """One-time migration: if client_secret.json still exists on disk (first
    run, or a pre-keyring install upgrading in place), move it into the
    keyring and delete it.

    Called unconditionally at the top of get_credentials(), not just from
    the fresh-OAuth-flow branch - client_secret.json is only ever *read*
    when starting a new interactive flow, which for an install with
    already-valid stored credentials may never happen again. Migrating it
    only as a side effect of that branch would leave it sitting in
    plaintext indefinitely for exactly the accounts least likely to need
    it read again.
    """
    if not CLIENT_SECRET_PATH.exists():
        return
    if not keyring.get_password(KEYRING_SERVICE, KEYRING_CLIENT_SECRET_ACCOUNT):
        config = json.loads(CLIENT_SECRET_PATH.read_text())
        keyring.set_password(KEYRING_SERVICE, KEYRING_CLIENT_SECRET_ACCOUNT, json.dumps(config))
    CLIENT_SECRET_PATH.unlink()


def load_client_config() -> dict:
    """OAuth client config (this app's id/secret) from the keyring - only
    needed when starting a fresh interactive OAuth flow. migrate_client_
    secret_if_present() already ran by this point (see get_credentials()),
    so the plaintext file fallback here is defensive, not the normal path.
    """
    stored = keyring.get_password(KEYRING_SERVICE, KEYRING_CLIENT_SECRET_ACCOUNT)
    if stored:
        return json.loads(stored)
    return json.loads(CLIENT_SECRET_PATH.read_text())


def load_stored_credentials_json() -> str | None:
    """Stored OAuth token JSON, preferring the keyring. Falls back to the
    plaintext file only for a pre-keyring install upgrading in place, then
    migrates it into the keyring and deletes the file, same as
    load_client_config()."""
    stored = keyring.get_password(KEYRING_SERVICE, KEYRING_CREDENTIALS_ACCOUNT)
    if stored:
        return stored
    if CREDENTIALS_PATH.exists():
        raw = CREDENTIALS_PATH.read_text()
        keyring.set_password(KEYRING_SERVICE, KEYRING_CREDENTIALS_ACCOUNT, raw)
        CREDENTIALS_PATH.unlink()
        return raw
    return None


def get_credentials() -> Credentials:
    migrate_client_secret_if_present()
    stored = load_stored_credentials_json()
    if stored:
        parsed = json.loads(stored)
        creds = Credentials.from_authorized_user_info(parsed, parsed.get("scopes") or SCOPES)
        if creds.expired and creds.refresh_token:
            creds.refresh(Request())
            save_credentials(creds)
        return creds

    flow = InstalledAppFlow.from_client_config(load_client_config(), SCOPES)
    creds = flow.run_local_server(port=0)
    save_credentials(creds)
    return creds


def save_credentials(creds: Credentials) -> None:
    keyring.set_password(KEYRING_SERVICE, KEYRING_CREDENTIALS_ACCOUNT, creds.to_json())


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


def fetch_latest_data_point(creds: Credentials, data_type: str, json_field: str):
    """GETs the single most recent data point for `data_type`, unfiltered.

    daily-resting-heart-rate and sleep both reject the interval.start_time
    filter fetch_data_points uses (400 INVALID_DATA_POINT_FILTER_DATA_TYPE_MEMBER
    - confirmed against the live API, not documented anywhere), but return
    results most-recent-first when queried with no filter at all.

    A page can come back with zero dataPoints but still carry a
    nextPageToken (confirmed live: page_size=1 on sleep returned only a
    token, no data) - pagination is over raw underlying records, not
    merged output points. So this follows nextPageToken across a few pages
    rather than trusting the first one to have data.
    """
    url = f"{API_BASE}/users/me/dataTypes/{data_type}/dataPoints"
    params = {"page_size": 10}
    for _ in range(5):
        response = requests.get(
            url,
            headers={"Authorization": f"Bearer {creds.token}", "Accept": "application/json"},
            params=params,
            timeout=10,
        )
        response.raise_for_status()
        body = response.json()
        points = body.get("dataPoints", [])
        if points:
            return points[0].get(json_field)
        next_token = body.get("nextPageToken")
        if not next_token:
            return None
        params = {**params, "page_token": next_token}
    return None


def fetch_history(
    creds: Credentials, data_type: str, json_field: str, max_points: int = 40,
    page_size: int = 20, max_pages: int = 6,
) -> list:
    """Fetches up to `max_points` most-recent raw points for `data_type`,
    unfiltered (most-recent-first) - the same query shape
    fetch_latest_data_point uses for data types that reject the
    interval.start_time filter, extended across multiple pages instead of
    stopping at the first hit. Used for the multi-day baselines behind
    "Overnight Signals" (issue #26). Same empty-page-with-a-token quirk as
    fetch_latest_data_point, so this follows nextPageToken rather than
    trusting any one page to carry data."""
    url = f"{API_BASE}/users/me/dataTypes/{data_type}/dataPoints"
    params = {"page_size": page_size}
    points = []
    for _ in range(max_pages):
        response = requests.get(
            url,
            headers={"Authorization": f"Bearer {creds.token}", "Accept": "application/json"},
            params=params,
            timeout=10,
        )
        response.raise_for_status()
        body = response.json()
        points.extend(p[json_field] for p in body.get("dataPoints", []) if json_field in p)
        if len(points) >= max_points:
            return points[:max_points]
        next_token = body.get("nextPageToken")
        if not next_token:
            return points
        params = {**params, "page_token": next_token}
    return points


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
    # Local midnight, not UTC midnight - datetime.now(timezone.utc) would put
    # "today" on a UTC day boundary instead of the user's own, e.g. a CDT
    # (UTC-5) user's steps/AZM/distance totals would span ~7PM-to-7PM local
    # time instead of midnight-to-midnight. astimezone() with no argument
    # picks up the system's local timezone, correct for a script that only
    # ever runs on the user's own machine.
    local_midnight = datetime.now().astimezone().replace(hour=0, minute=0, second=0, microsecond=0)
    start_time = local_midnight.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

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

    # Same list+filter+sum shape as steps/AZM - each point is one minute's
    # distance in millimeters (confirmed live), summed and converted to
    # meters. Same "pages can come back empty but still carry a
    # nextPageToken" quirk as everything else here, already handled by
    # fetch_data_points's unbounded pagination loop.
    distance_points = (
        safe_metric(warnings, "distance", fetch_data_points, creds, "distance", start_time, "distance") or []
    )
    distance_meters_total = (
        round(sum(int(p.get("millimeters", 0)) for p in distance_points) / 1000) if distance_points else None
    )

    # UNVERIFIED: this account's device reports no floors data at all (the
    # dailyRollUp call returns 200 with an empty body no matter the date
    # range tried), so this field name is inferred from total-calories'
    # working shape (rollupDataPoints[].totalCalories.kcalSum), not
    # confirmed against a real response. safe_metric degrades a wrong
    # guess to null + a warning rather than crashing - re-check the actual
    # field name the first time this comes back with real data.
    floors_bucket = safe_metric(warnings, "floors", fetch_daily_rollup, creds, "floors")
    floors_total = (
        round(floors_bucket["floors"]["count"]) if floors_bucket and "floors" in floors_bucket else None
    )

    resting_hr_point = safe_metric(
        warnings, "restingHeartRate", fetch_latest_data_point,
        creds, "daily-resting-heart-rate", "dailyRestingHeartRate",
    )
    resting_hr = int(resting_hr_point["beatsPerMinute"]) if resting_hr_point else None

    sleep_point = safe_metric(warnings, "sleep", fetch_latest_data_point, creds, "sleep", "sleep")
    sleep_summary = sleep_point.get("summary") if sleep_point else None

    return {
        "ok": True,
        "fetchedAtIso": datetime.now(timezone.utc).isoformat(),
        "steps": steps_total,
        "activeZoneMinutes": azm_total,
        "calories": calories_total,
        "distanceMeters": distance_meters_total,
        "floors": floors_total,
        "restingHeartRate": resting_hr,
        "sleep": (
            {
                "minutesAsleep": int(sleep_summary["minutesAsleep"]),
                "minutesAwake": int(sleep_summary["minutesAwake"]),
            }
            if sleep_summary
            else None
        ),
        "warnings": warnings,
    }


BASELINE_WINDOW_DAYS = 14


def point_date_str(point: dict) -> str | None:
    """Which calendar day a history point belongs to, for splitting
    "today's" reading out of its own baseline. Resting-HR/HRV points carry
    an explicit {year,month,day} date; sleep points don't, so the sleep
    session's end time (converted to local calendar date - sleep ends
    mid-morning, which is when it becomes "today's" reading) stands in."""
    d = point.get("date")
    if d:
        return f"{d['year']:04d}-{d['month']:02d}-{d['day']:02d}"
    interval = point.get("interval")
    if interval and interval.get("endTime"):
        end = datetime.fromisoformat(interval["endTime"].replace("Z", "+00:00"))
        return end.astimezone().date().isoformat()
    return None


def find_current_point(points: list, today_str: str) -> dict | None:
    for point in points:
        if point_date_str(point) == today_str:
            return point
    return None


def collect_baseline_avg(points: list, today_str: str, value_fn, filter_fn=None, window: int = BASELINE_WINDOW_DAYS):
    """Averages `value_fn` over the next `window` points that aren't dated
    today, optionally restricted to `filter_fn` (e.g. resting-HR's
    higher-confidence-only rule) - so today's own reading and low-confidence
    points never leak into the average it's compared against."""
    values = []
    for point in points:
        if point_date_str(point) == today_str:
            continue
        if filter_fn and not filter_fn(point):
            continue
        values.append(value_fn(point))
        if len(values) >= window:
            break
    return sum(values) / len(values) if values else None


def resting_hr_reading(point: dict) -> float:
    return float(point["beatsPerMinute"])


def is_high_confidence_hr(point: dict) -> bool:
    return point.get("dailyRestingHeartRateMetadata", {}).get("calculationMethod") == "WITH_SLEEP"


def hrv_reading(point: dict) -> float:
    return float(point["averageHeartRateVariabilityMilliseconds"])


def sleep_minutes_asleep(point: dict) -> int:
    return int(point["summary"]["minutesAsleep"])


def sleep_efficiency(point: dict) -> float | None:
    summary = point["summary"]
    in_period = int(summary["minutesInSleepPeriod"])
    return int(summary["minutesAsleep"]) / in_period if in_period > 0 else None


def score_resting_hr(current, baseline) -> int:
    """Higher resting HR than usual is the caution direction (unlike HRV/
    sleep, where lower is caution) - thresholds are raw bpm deltas, not
    percent, sanity-checked in issue #26 against ~1-3bpm of real day-to-day
    noise in this account's own history."""
    if current is None or baseline is None:
        return 0
    delta = current - baseline
    if delta >= 5:
        return -1
    if delta <= -3:
        return 1
    return 0


def score_relative_pct(current, baseline, caution_pct: float, good_pct: float) -> int:
    """Percent-of-baseline scoring for signals where lower-than-usual is
    the caution direction (HRV, sleep duration) - percent rather than an
    absolute delta since personal baselines vary widely between people."""
    if current is None or baseline is None or baseline == 0:
        return 0
    delta_pct = (current - baseline) / baseline * 100
    if delta_pct <= -caution_pct:
        return -1
    if delta_pct >= good_pct:
        return 1
    return 0


def score_sleep_efficiency(efficiency) -> int:
    """Absolute 85% threshold (real sleep-science convention), not
    baseline-relative like the other 3 signals - and deliberately has no
    'good' tier above 85%, per issue #26's locked spec."""
    if efficiency is None:
        return 0
    return -1 if efficiency < 0.85 else 0


def combine_verdict(scores: list) -> str:
    """Worst-signal-wins in both directions: any caution signal pulls the
    whole verdict to "below", every signal has to agree for "above" -
    matches issue #26's locked combination logic exactly (not an average)."""
    if any(s == -1 for s in scores):
        return "below"
    if all(s == 1 for s in scores):
        return "above"
    return "typical"


def build_baseline() -> dict:
    """Multi-day-history counterpart to build_status() (issue #26) - run on
    its own slower, once-a-day cadence (see Service.qml) since a 7-14 day
    average barely moves within a day and this makes 3x the API calls of
    the 5-minute live poll."""
    creds = get_credentials()
    warnings: list[str] = []
    today_str = datetime.now().astimezone().date().isoformat()

    hr_points = safe_metric(warnings, "restingHeartRateHistory", fetch_history, creds, "daily-resting-heart-rate", "dailyRestingHeartRate") or []
    hr_current_point = find_current_point(hr_points, today_str)
    hr_current = resting_hr_reading(hr_current_point) if hr_current_point else None
    hr_baseline = collect_baseline_avg(hr_points, today_str, resting_hr_reading, is_high_confidence_hr)

    hrv_points = safe_metric(warnings, "hrvHistory", fetch_history, creds, "daily-heart-rate-variability", "dailyHeartRateVariability") or []
    hrv_current_point = find_current_point(hrv_points, today_str)
    hrv_current = hrv_reading(hrv_current_point) if hrv_current_point else None
    hrv_baseline = collect_baseline_avg(hrv_points, today_str, hrv_reading)

    sleep_points = safe_metric(warnings, "sleepHistory", fetch_history, creds, "sleep", "sleep") or []
    sleep_current_point = find_current_point(sleep_points, today_str)
    sleep_current_minutes = sleep_minutes_asleep(sleep_current_point) if sleep_current_point else None
    sleep_current_efficiency = sleep_efficiency(sleep_current_point) if sleep_current_point else None
    sleep_baseline_minutes = collect_baseline_avg(sleep_points, today_str, sleep_minutes_asleep)

    scores = [
        score_resting_hr(hr_current, hr_baseline),
        score_relative_pct(hrv_current, hrv_baseline, caution_pct=15, good_pct=15),
        score_relative_pct(sleep_current_minutes, sleep_baseline_minutes, caution_pct=15, good_pct=5),
        score_sleep_efficiency(sleep_current_efficiency),
    ]
    any_signal_available = any(
        v is not None for v in (hr_current, hrv_current, sleep_current_minutes, sleep_current_efficiency)
    )
    verdict = combine_verdict(scores) if any_signal_available else None

    return {
        "ok": True,
        "computedAtIso": datetime.now(timezone.utc).isoformat(),
        "verdict": verdict,
        "restingHeartRate": round(hr_current) if hr_current is not None else None,
        "hrv": round(hrv_current, 1) if hrv_current is not None else None,
        "sleepMinutes": sleep_current_minutes,
        "warnings": warnings,
    }


if __name__ == "__main__":
    # This only wraps get_credentials() failures (the one call in
    # build_status() not already isolated per-metric by safe_metric) - a
    # single metric's own network/API hiccup degrades to a warning, not a
    # crash here. So realistically this outer catch is almost always
    # either a broken/expired OAuth token (needs re-auth) or a network
    # failure during the token refresh call itself - map both to a plain
    # sentence with a next step, fall back to the raw message for anything
    # genuinely unexpected rather than hiding it.
    build = build_baseline if len(sys.argv) > 1 and sys.argv[1] == "baseline" else build_status
    try:
        print(json.dumps(build()))
    except GoogleAuthError:
        print(json.dumps({
            "ok": False,
            "error": "Reconnect needed - run 'python fitbit_status.py' in a terminal to re-authenticate.",
        }))
        sys.exit(1)
    except requests.exceptions.RequestException:
        print(json.dumps({
            "ok": False,
            "error": "Can't reach Fitbit right now - will retry automatically.",
        }))
        sys.exit(1)
    except Exception as exc:  # keep the widget's Process handler simple: one line, always
        print(json.dumps({"ok": False, "error": str(exc)}))
        sys.exit(1)
