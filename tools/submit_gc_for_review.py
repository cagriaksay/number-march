#!/usr/bin/env python3
"""
Attach all Game Center achievements and leaderboards to an app store version
for review submission.

Usage:
    python submit_gc_for_review.py \
        --key-id YOUR_KEY_ID \
        --issuer-id YOUR_ISSUER_ID \
        --key-file /path/to/AuthKey_XXXX.p8 \
        --app-id YOUR_APP_ID \
        --version 1.0.1
"""

import argparse
import json
import sys
import time
import jwt
import requests
from datetime import datetime, timedelta, timezone

BASE_URL = "https://api.appstoreconnect.apple.com/v1"


def generate_token(key_id, issuer_id, key_file):
    with open(key_file, "r") as f:
        private_key = f.read()
    now = datetime.now(timezone.utc)
    payload = {
        "iss": issuer_id,
        "iat": now,
        "exp": now + timedelta(minutes=20),
        "aud": "appstoreconnect-v1",
    }
    headers = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    return jwt.encode(payload, private_key, algorithm="ES256", headers=headers)


def api_headers(token):
    return {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
    }


def api_get(token, path, params=None):
    url = f"{BASE_URL}{path}"
    resp = requests.get(url, headers=api_headers(token), params=params)
    if resp.status_code == 200:
        return resp.json()
    print(f"  GET ERROR {resp.status_code}: {resp.text[:500]}")
    return None


def api_post(token, path, data):
    url = f"{BASE_URL}{path}"
    resp = requests.post(url, headers=api_headers(token), json=data)
    if resp.status_code in (200, 201):
        return resp.json()
    print(f"  POST ERROR {resp.status_code}: {resp.text[:500]}")
    return None


def api_get_all_pages(token, path, params=None):
    all_data = []
    url = f"{BASE_URL}{path}"
    while url:
        resp = requests.get(url, headers=api_headers(token), params=params)
        params = None
        if resp.status_code != 200:
            print(f"  GET ERROR {resp.status_code}: {resp.text[:500]}")
            break
        result = resp.json()
        all_data.extend(result.get("data", []))
        url = result.get("links", {}).get("next")
    return all_data


def main():
    parser = argparse.ArgumentParser(description="Attach Game Center items to app version for review")
    parser.add_argument("--key-id", required=True)
    parser.add_argument("--issuer-id", required=True)
    parser.add_argument("--key-file", required=True)
    parser.add_argument("--app-id", required=True)
    parser.add_argument("--version", required=True, help="App store version string (e.g. 1.0.1)")
    args = parser.parse_args()

    print("Generating JWT token...")
    token = generate_token(args.key_id, args.issuer_id, args.key_file)
    print("  OK\n")

    # Step 1: Get Game Center Detail
    print("[1/5] Getting Game Center Detail...")
    gc_result = api_get(token, f"/apps/{args.app_id}/gameCenterDetail")
    if not gc_result or not gc_result.get("data"):
        print("  ERROR: No Game Center Detail found")
        sys.exit(1)
    gc_detail_id = gc_result["data"]["id"]
    print(f"  ID: {gc_detail_id}\n")

    # Step 2: Get all achievements and leaderboards
    print("[2/5] Fetching achievements and leaderboards...")
    achievements = api_get_all_pages(token, f"/gameCenterDetails/{gc_detail_id}/gameCenterAchievements", params={"limit": 200})
    leaderboards = api_get_all_pages(token, f"/gameCenterDetails/{gc_detail_id}/gameCenterLeaderboards", params={"limit": 200})
    print(f"  Achievements: {len(achievements)}")
    print(f"  Leaderboards: {len(leaderboards)}")
    print(f"  Total: {len(achievements) + len(leaderboards)}\n")

    # Step 3: Find the app store version
    print(f"[3/5] Finding app store version {args.version}...")
    versions = api_get(token, f"/apps/{args.app_id}/appStoreVersions", params={
        "filter[versionString]": args.version,
        "filter[platform]": "IOS",
    })
    if not versions or not versions.get("data"):
        print(f"  ERROR: Version {args.version} not found")
        sys.exit(1)
    app_store_version = versions["data"][0]
    app_store_version_id = app_store_version["id"]
    version_state = app_store_version["attributes"]["appStoreState"]
    print(f"  ID: {app_store_version_id}")
    print(f"  State: {version_state}\n")

    # Step 4: Create Game Center App Version (enable GC for this version)
    print("[4/5] Enabling Game Center for this app version...")
    gc_app_version_data = {
        "data": {
            "type": "gameCenterAppVersions",
            "relationships": {
                "appStoreVersion": {
                    "data": {
                        "type": "appStoreVersions",
                        "id": app_store_version_id,
                    }
                }
            },
        }
    }
    gc_app_version = api_post(token, "/gameCenterAppVersions", gc_app_version_data)
    if gc_app_version:
        print(f"  Created gameCenterAppVersion: {gc_app_version['data']['id']}\n")
    else:
        # Try to get existing one
        existing = api_get(token, f"/appStoreVersions/{app_store_version_id}/gameCenterAppVersion")
        if existing and existing.get("data"):
            print(f"  Already exists: {existing['data']['id']}\n")
        else:
            print("  WARNING: Could not create or find gameCenterAppVersion\n")

    # Step 5: Create Game Center Release with all achievements and leaderboards
    print("[5/5] Creating Game Center Release...")

    # Build relationship arrays
    achievement_refs = [{"type": "gameCenterAchievements", "id": a["id"]} for a in achievements]
    leaderboard_refs = [{"type": "gameCenterLeaderboards", "id": lb["id"]} for lb in leaderboards]

    release_data = {
        "data": {
            "type": "gameCenterDetailReleaseRequests",
            "relationships": {
                "gameCenterDetail": {
                    "data": {
                        "type": "gameCenterDetails",
                        "id": gc_detail_id,
                    }
                },
            },
        }
    }

    # Try the release request approach first
    release = api_post(token, "/gameCenterDetailReleaseRequests", release_data)
    if release:
        print(f"  Created release request: {release['data']['id']}")
    else:
        print("  Trying alternative approach...")
        # Alternative: try gameCenterReleases with individual items
        for i, ach in enumerate(achievements):
            vid = ach["attributes"]["vendorIdentifier"]
            rel_data = {
                "data": {
                    "type": "gameCenterAchievementReleases",
                    "relationships": {
                        "gameCenterDetail": {
                            "data": {"type": "gameCenterDetails", "id": gc_detail_id}
                        },
                        "gameCenterAchievement": {
                            "data": {"type": "gameCenterAchievements", "id": ach["id"]}
                        },
                    },
                }
            }
            result = api_post(token, "/gameCenterAchievementReleases", rel_data)
            status = "OK" if result else "FAILED"
            print(f"  Achievement [{vid}]: {status}")
            time.sleep(0.3)

        for i, lb in enumerate(leaderboards):
            vid = lb["attributes"]["vendorIdentifier"]
            rel_data = {
                "data": {
                    "type": "gameCenterLeaderboardReleases",
                    "relationships": {
                        "gameCenterDetail": {
                            "data": {"type": "gameCenterDetails", "id": gc_detail_id}
                        },
                        "gameCenterLeaderboard": {
                            "data": {"type": "gameCenterLeaderboards", "id": lb["id"]}
                        },
                    },
                }
            }
            result = api_post(token, "/gameCenterLeaderboardReleases", rel_data)
            status = "OK" if result else "FAILED"
            print(f"  Leaderboard [{vid}]: {status}")
            time.sleep(0.3)

    print("\nDone! Game Center items are now attached to version " + args.version)
    print("Submit the version for review in App Store Connect to include them.")


if __name__ == "__main__":
    main()
