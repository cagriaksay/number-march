#!/usr/bin/env python3
"""
Add Game Center achievement and leaderboard versions to an existing
App Store review submission draft.

The v2 App Store Connect API uses per-item "versions" for Game Center
resources. Each achievement/leaderboard version must be added as a
reviewSubmissionItem to appear in the review draft.

If old-style v1 releases (gameCenterAchievementReleases /
gameCenterLeaderboardReleases) exist, they will be deleted first since
they conflict with the v2 version-based flow.

Usage:
    python add_gc_to_review.py \
        --key-id YOUR_KEY_ID \
        --issuer-id YOUR_ISSUER_ID \
        --key-file /path/to/AuthKey_XXXX.p8 \
        --app-id YOUR_APP_ID
"""

import argparse
import json
import sys
import time
import jwt
import requests
from datetime import datetime, timedelta, timezone

BASE_V1 = "https://api.appstoreconnect.apple.com/v1"
BASE_V2 = "https://api.appstoreconnect.apple.com/v2"


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


def api_get(token, url, params=None):
    resp = requests.get(url, headers=api_headers(token), params=params)
    if resp.status_code == 200:
        return resp.json()
    print(f"  GET ERROR {resp.status_code}: {resp.text[:500]}")
    return None


def api_post(token, url, data):
    resp = requests.post(url, headers=api_headers(token), json=data)
    if resp.status_code in (200, 201):
        return resp.json()
    return resp


def api_delete(token, url):
    return requests.delete(url, headers=api_headers(token))


def get_all_pages(token, url, params=None):
    all_data = []
    while url:
        resp = requests.get(url, headers=api_headers(token), params=params)
        params = None
        if resp.status_code != 200:
            print(f"  GET ERROR {resp.status_code}: {resp.text[:300]}")
            break
        result = resp.json()
        all_data.extend(result.get("data", []))
        url = result.get("links", {}).get("next")
    return all_data


def main():
    parser = argparse.ArgumentParser(
        description="Add Game Center items to an existing review submission draft"
    )
    parser.add_argument("--key-id", required=True)
    parser.add_argument("--issuer-id", required=True)
    parser.add_argument("--key-file", required=True)
    parser.add_argument("--app-id", required=True)
    args = parser.parse_args()

    print("Generating JWT token...")
    token = generate_token(args.key_id, args.issuer_id, args.key_file)
    print("  OK\n")

    # Step 1: Get Game Center Detail
    print("[1/7] Getting Game Center Detail...")
    gc_result = api_get(token, f"{BASE_V1}/apps/{args.app_id}/gameCenterDetail")
    if not gc_result or not gc_result.get("data"):
        print("  ERROR: No Game Center Detail found")
        sys.exit(1)
    gc_detail_id = gc_result["data"]["id"]
    print(f"  ID: {gc_detail_id}\n")

    # Step 2: Find the active review submission draft
    print("[2/7] Finding review submission draft...")
    subs = api_get(
        token,
        f"{BASE_V1}/reviewSubmissions",
        params={
            "filter[app]": args.app_id,
            "filter[state]": "READY_FOR_REVIEW,WAITING_FOR_REVIEW",
        },
    )
    if not subs or not subs.get("data"):
        print("  ERROR: No active review submission found")
        sys.exit(1)
    # Pick the one that has items (the real draft)
    review_sub_id = None
    for sub in subs["data"]:
        items = api_get(
            token, f"{BASE_V1}/reviewSubmissions/{sub['id']}/items"
        )
        if items and items.get("data"):
            review_sub_id = sub["id"]
            break
    if not review_sub_id:
        # Fall back to first one
        review_sub_id = subs["data"][0]["id"]
    print(f"  ID: {review_sub_id}\n")

    # Step 3: Get all achievements and leaderboards
    print("[3/7] Fetching achievements and leaderboards...")
    achievements = get_all_pages(
        token,
        f"{BASE_V1}/gameCenterDetails/{gc_detail_id}/gameCenterAchievements",
        {"limit": 200},
    )
    leaderboards = get_all_pages(
        token,
        f"{BASE_V1}/gameCenterDetails/{gc_detail_id}/gameCenterLeaderboards",
        {"limit": 200},
    )
    print(f"  Achievements: {len(achievements)}")
    print(f"  Leaderboards: {len(leaderboards)}\n")

    # Step 4: Delete old-style achievement releases (v1)
    print("[4/7] Deleting old-style achievement releases...")
    deleted_ach = 0
    for ach in achievements:
        ach_id = ach["id"]
        vid = ach["attributes"]["vendorIdentifier"]
        releases_resp = api_get(
            token, f"{BASE_V1}/gameCenterAchievements/{ach_id}/releases"
        )
        if releases_resp:
            for rel in releases_resp.get("data", []):
                if not rel["attributes"].get("live", False):
                    r = api_delete(
                        token,
                        f"{BASE_V1}/gameCenterAchievementReleases/{rel['id']}",
                    )
                    deleted_ach += 1
                    if deleted_ach <= 3 or deleted_ach % 20 == 0:
                        status = "OK" if r.status_code == 204 else f"ERR {r.status_code}"
                        print(f"  [{vid}]: {status}")
        time.sleep(0.1)
    print(f"  Deleted {deleted_ach} achievement releases\n")

    # Step 5: Delete old-style leaderboard releases (v1)
    print("[5/7] Deleting old-style leaderboard releases...")
    deleted_lb = 0
    for lb in leaderboards:
        lb_id = lb["id"]
        vid = lb["attributes"]["vendorIdentifier"]
        releases_resp = api_get(
            token, f"{BASE_V1}/gameCenterLeaderboards/{lb_id}/releases"
        )
        if releases_resp:
            for rel in releases_resp.get("data", []):
                if not rel["attributes"].get("live", False):
                    r = api_delete(
                        token,
                        f"{BASE_V1}/gameCenterLeaderboardReleases/{rel['id']}",
                    )
                    deleted_lb += 1
                    if deleted_lb <= 3 or deleted_lb % 20 == 0:
                        status = "OK" if r.status_code == 204 else f"ERR {r.status_code}"
                        print(f"  [{vid}]: {status}")
        time.sleep(0.1)
    print(f"  Deleted {deleted_lb} leaderboard releases\n")

    # Step 6: Add achievement versions to review draft
    print("[6/7] Adding achievement versions to review draft...")
    added_ach = 0
    errors_ach = 0
    for ach in achievements:
        ach_id = ach["id"]
        vid = ach["attributes"]["vendorIdentifier"]
        ver_resp = api_get(
            token, f"{BASE_V2}/gameCenterAchievements/{ach_id}/versions"
        )
        if not ver_resp or not ver_resp.get("data"):
            # Create a version if none exists
            create_data = {
                "data": {
                    "type": "gameCenterAchievementVersions",
                    "relationships": {
                        "achievement": {
                            "data": {
                                "type": "gameCenterAchievements",
                                "id": ach_id,
                            }
                        }
                    },
                }
            }
            cr = api_post(token, f"{BASE_V2}/gameCenterAchievementVersions", create_data)
            if isinstance(cr, dict):
                ver_id = cr["data"]["id"]
            else:
                errors_ach += 1
                if errors_ach <= 3:
                    print(f"  [{vid}]: ERR creating version - {cr.text[:200]}")
                continue
        else:
            ver_id = ver_resp["data"][0]["id"]

        item_data = {
            "data": {
                "type": "reviewSubmissionItems",
                "relationships": {
                    "reviewSubmission": {
                        "data": {
                            "type": "reviewSubmissions",
                            "id": review_sub_id,
                        }
                    },
                    "gameCenterAchievementVersion": {
                        "data": {
                            "type": "gameCenterAchievementVersions",
                            "id": ver_id,
                        }
                    },
                },
            }
        }
        r = api_post(token, f"{BASE_V1}/reviewSubmissionItems", item_data)
        if isinstance(r, dict):
            added_ach += 1
            if added_ach <= 3 or added_ach % 10 == 0:
                print(f"  [{vid}]: OK")
        else:
            errors_ach += 1
            err = r.json().get("errors", [{}])[0].get("detail", r.text[:200])
            if errors_ach <= 3:
                print(f"  [{vid}]: ERR {r.status_code} - {err}")
        time.sleep(0.15)
    print(f"  Added: {added_ach}, Errors: {errors_ach}\n")

    # Step 7: Add leaderboard versions to review draft
    print("[7/7] Adding leaderboard versions to review draft...")
    added_lb = 0
    errors_lb = 0
    for lb in leaderboards:
        lb_id = lb["id"]
        vid = lb["attributes"]["vendorIdentifier"]
        ver_resp = api_get(
            token, f"{BASE_V2}/gameCenterLeaderboards/{lb_id}/versions"
        )
        if not ver_resp or not ver_resp.get("data"):
            create_data = {
                "data": {
                    "type": "gameCenterLeaderboardVersions",
                    "relationships": {
                        "leaderboard": {
                            "data": {
                                "type": "gameCenterLeaderboards",
                                "id": lb_id,
                            }
                        }
                    },
                }
            }
            cr = api_post(token, f"{BASE_V2}/gameCenterLeaderboardVersions", create_data)
            if isinstance(cr, dict):
                ver_id = cr["data"]["id"]
            else:
                errors_lb += 1
                if errors_lb <= 3:
                    print(f"  [{vid}]: ERR creating version - {cr.text[:200]}")
                continue
        else:
            ver_id = ver_resp["data"][0]["id"]

        item_data = {
            "data": {
                "type": "reviewSubmissionItems",
                "relationships": {
                    "reviewSubmission": {
                        "data": {
                            "type": "reviewSubmissions",
                            "id": review_sub_id,
                        }
                    },
                    "gameCenterLeaderboardVersion": {
                        "data": {
                            "type": "gameCenterLeaderboardVersions",
                            "id": ver_id,
                        }
                    },
                },
            }
        }
        r = api_post(token, f"{BASE_V1}/reviewSubmissionItems", item_data)
        if isinstance(r, dict):
            added_lb += 1
            if added_lb <= 3 or added_lb % 10 == 0:
                print(f"  [{vid}]: OK")
        else:
            errors_lb += 1
            err = r.json().get("errors", [{}])[0].get("detail", r.text[:200])
            if errors_lb <= 3:
                print(f"  [{vid}]: ERR {r.status_code} - {err}")
        time.sleep(0.15)
    print(f"  Added: {added_lb}, Errors: {errors_lb}\n")

    print("=== Summary ===")
    print(f"Achievement releases deleted: {deleted_ach}")
    print(f"Leaderboard releases deleted: {deleted_lb}")
    print(f"Achievement versions added to draft: {added_ach}")
    print(f"Leaderboard versions added to draft: {added_lb}")
    print(
        "\nDone! Check App Store Connect to verify Game Center items "
        "appear in the review submission."
    )


if __name__ == "__main__":
    main()
