#!/usr/bin/env python3
"""One-off script to prove the Google Health API OAuth setup works end to end.

Runs the desktop OAuth flow (browser + local redirect), saves the resulting
tokens, then fetches today's step data points as a sanity check.
"""

import json
from datetime import datetime, timezone
from pathlib import Path

import requests
from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import InstalledAppFlow

CONFIG_DIR = Path.home() / ".config" / "fit-gauge"
CLIENT_SECRET_PATH = CONFIG_DIR / "client_secret.json"
CREDENTIALS_PATH = CONFIG_DIR / "credentials.json"

SCOPES = ["https://www.googleapis.com/auth/googlehealth.activity_and_fitness.readonly"]

API_BASE = "https://health.googleapis.com/v4"


def get_credentials() -> Credentials:
    if CREDENTIALS_PATH.exists():
        creds = Credentials.from_authorized_user_file(str(CREDENTIALS_PATH), SCOPES)
        if creds.valid:
            return creds
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


def fetch_todays_steps(creds: Credentials) -> dict:
    from datetime import timedelta

    start_of_day = datetime.now(timezone.utc) - timedelta(days=3)
    start_time = start_of_day.strftime("%Y-%m-%dT%H:%M:%SZ")

    response = requests.get(
        f"{API_BASE}/users/me/dataTypes/steps/dataPoints",
        headers={
            "Authorization": f"Bearer {creds.token}",
            "Accept": "application/json",
        },
        params={
            "page_size": 10,
            "filter": f'steps.interval.start_time >= "{start_time}"',
        },
        timeout=10,
    )
    if not response.ok:
        print(response.status_code, response.text)
    response.raise_for_status()
    return response.json()


if __name__ == "__main__":
    credentials = get_credentials()
    data = fetch_todays_steps(credentials)
    print(json.dumps(data, indent=2))
