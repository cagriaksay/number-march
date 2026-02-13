#!/usr/bin/env python3
"""
Bulk-create Game Center leaderboards and achievements via App Store Connect API.

Prerequisites:
    pip install requests pyjwt cryptography

Usage:
    python setup_game_center.py \
        --key-id YOUR_KEY_ID \
        --issuer-id YOUR_ISSUER_ID \
        --key-file /path/to/AuthKey_XXXX.p8 \
        --app-id YOUR_APP_ID

To find your App ID:
    Go to App Store Connect > Your App > General > App Information
    The Apple ID is the numeric ID (e.g., 6758360927)

To create an API key:
    App Store Connect > Users and Access > Integrations > App Store Connect API > Generate
    Download the .p8 file (you can only download it once!)
"""

import argparse
import json
import time
import sys
import jwt
import requests
from datetime import datetime, timedelta, timezone

BASE_URL = "https://api.appstoreconnect.apple.com/v1"

# ── Configuration ──────────────────────────────────────────────

NUM_LEVELS = 60

# One leaderboard per level: best score (remaining HP, higher is better)
SCORE_LEADERBOARDS = [
    {
        "referenceName": f"Level {i} - Best Score",
        "vendorIdentifier": f"level_{i}_score",
        "submissionType": "BEST_SCORE",
        "scoreSortType": "DESC",  # Higher HP = better
        "scoreRangeStart": "0",
        "scoreRangeEnd": "9999",
        "defaultFormatter": "INTEGER",
    }
    for i in range(1, NUM_LEVELS + 1)
]

# Achievement per level + one for completing all
ACHIEVEMENTS = [
    *[
        {
            "referenceName": f"Level {i} Complete",
            "vendorIdentifier": f"level_{i}_complete",
            "points": 1,  # 60 levels * 1 = 60 points, + 40 for all_complete
            "repeatable": False,
            "showBeforeEarned": True,
        }
        for i in range(1, NUM_LEVELS + 1)
    ],
    {
        "referenceName": "All Levels Complete",
        "vendorIdentifier": "all_levels_complete",
        "points": 40,  # bonus achievement (60 + 40 = 100 total)
        "repeatable": False,
        "showBeforeEarned": True,
    },
]

ACHIEVEMENT_LOCALIZATIONS = {
    **{
        f"level_{i}_complete": {
            "name": f"Level {i} Clear",
            "beforeEarnedDescription": f"Complete Level {i}",
            "afterEarnedDescription": f"Cleared Level {i}!",
        }
        for i in range(1, NUM_LEVELS + 1)
    },
    "all_levels_complete": {
        "name": "Number Master",
        "beforeEarnedDescription": "Complete all 60 levels",
        "afterEarnedDescription": "Cleared all 60 levels! You are the Number Master!",
    },
}


# ── JWT Token Generation ──────────────────────────────────────

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
    headers = {
        "alg": "ES256",
        "kid": key_id,
        "typ": "JWT",
    }
    token = jwt.encode(payload, private_key, algorithm="ES256", headers=headers)
    return token


# ── API Helpers ────────────────────────────────────────────────

def api_headers(token):
    return {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
    }


def api_post(token, path, data):
    url = f"{BASE_URL}{path}"
    resp = requests.post(url, headers=api_headers(token), json=data)
    if resp.status_code in (200, 201):
        return resp.json()
    else:
        print(f"  ERROR {resp.status_code}: {resp.text[:500]}")
        return None


def api_get(token, path):
    url = f"{BASE_URL}{path}"
    resp = requests.get(url, headers=api_headers(token))
    if resp.status_code == 200:
        return resp.json()
    else:
        print(f"  ERROR {resp.status_code}: {resp.text[:500]}")
        return None


# ── Step 1: Get or Create Game Center Detail ──────────────────

def get_or_create_gc_detail(token, app_id):
    print("\n[1/4] Getting Game Center Detail...")

    # Try getting it via the app's relationship
    result = api_get(token, f"/apps/{app_id}/gameCenterDetail")
    if result and result.get("data"):
        gc_detail_id = result["data"]["id"]
        print(f"  Found existing Game Center Detail: {gc_detail_id}")
        return gc_detail_id

    print("  Creating new Game Center Detail...")
    data = {
        "data": {
            "type": "gameCenterDetails",
            "relationships": {
                "app": {
                    "data": {
                        "type": "apps",
                        "id": str(app_id),
                    }
                }
            },
        }
    }
    result = api_post(token, "/gameCenterDetails", data)
    if result:
        gc_detail_id = result["data"]["id"]
        print(f"  Created Game Center Detail: {gc_detail_id}")
        return gc_detail_id

    print("  FAILED to get or create Game Center Detail!")
    sys.exit(1)


# ── Step 2: Create Leaderboards ───────────────────────────────

def create_leaderboard(token, gc_detail_id, lb_config):
    data = {
        "data": {
            "type": "gameCenterLeaderboards",
            "attributes": {
                "referenceName": lb_config["referenceName"],
                "vendorIdentifier": lb_config["vendorIdentifier"],
                "submissionType": lb_config["submissionType"],
                "scoreSortType": lb_config["scoreSortType"],
                "scoreRangeStart": lb_config["scoreRangeStart"],
                "scoreRangeEnd": lb_config["scoreRangeEnd"],
                "defaultFormatter": lb_config["defaultFormatter"],
            },
            "relationships": {
                "gameCenterDetail": {
                    "data": {
                        "type": "gameCenterDetails",
                        "id": gc_detail_id,
                    }
                }
            },
        }
    }
    return api_post(token, "/gameCenterLeaderboards", data)


def create_leaderboard_localization(token, leaderboard_id, name, formatter_suffix=""):
    attrs = {
        "locale": "en-US",
        "name": name,
    }
    if formatter_suffix:
        attrs["formatterSuffix"] = formatter_suffix
    data = {
        "data": {
            "type": "gameCenterLeaderboardLocalizations",
            "attributes": attrs,
            "relationships": {
                "gameCenterLeaderboard": {
                    "data": {
                        "type": "gameCenterLeaderboards",
                        "id": leaderboard_id,
                    }
                }
            },
        }
    }
    return api_post(token, "/gameCenterLeaderboardLocalizations", data)


def create_all_leaderboards(token, gc_detail_id):
    print(f"\n[2/4] Creating {len(SCORE_LEADERBOARDS)} leaderboards...")

    for i, lb in enumerate(SCORE_LEADERBOARDS):
        print(f"  Creating: {lb['referenceName']}...", end=" ")
        result = create_leaderboard(token, gc_detail_id, lb)
        if result:
            lb_id = result["data"]["id"]
            print(f"OK (id: {lb_id})")
            create_leaderboard_localization(token, lb_id, lb["referenceName"], " pts")
        else:
            print("FAILED")
        time.sleep(0.3)  # Rate limiting


# ── Step 3: Create Achievements ───────────────────────────────

def create_achievement(token, gc_detail_id, ach_config):
    data = {
        "data": {
            "type": "gameCenterAchievements",
            "attributes": {
                "referenceName": ach_config["referenceName"],
                "vendorIdentifier": ach_config["vendorIdentifier"],
                "points": ach_config["points"],
                "repeatable": ach_config["repeatable"],
                "showBeforeEarned": ach_config["showBeforeEarned"],
            },
            "relationships": {
                "gameCenterDetail": {
                    "data": {
                        "type": "gameCenterDetails",
                        "id": gc_detail_id,
                    }
                }
            },
        }
    }
    return api_post(token, "/gameCenterAchievements", data)


def create_achievement_localization(token, achievement_id, loc_config):
    data = {
        "data": {
            "type": "gameCenterAchievementLocalizations",
            "attributes": {
                "locale": "en-US",
                "name": loc_config["name"],
                "beforeEarnedDescription": loc_config["beforeEarnedDescription"],
                "afterEarnedDescription": loc_config["afterEarnedDescription"],
            },
            "relationships": {
                "gameCenterAchievement": {
                    "data": {
                        "type": "gameCenterAchievements",
                        "id": achievement_id,
                    }
                }
            },
        }
    }
    return api_post(token, "/gameCenterAchievementLocalizations", data)


def create_all_achievements(token, gc_detail_id):
    print(f"\n[3/4] Creating {len(ACHIEVEMENTS)} achievements...")

    for ach in ACHIEVEMENTS:
        vid = ach["vendorIdentifier"]
        print(f"  Creating: {ach['referenceName']}...", end=" ")
        result = create_achievement(token, gc_detail_id, ach)
        if result:
            ach_id = result["data"]["id"]
            print(f"OK (id: {ach_id})")
            loc = ACHIEVEMENT_LOCALIZATIONS[vid]
            create_achievement_localization(token, ach_id, loc)
        else:
            print("FAILED")
        time.sleep(0.3)


# ── Step 4: Summary ───────────────────────────────────────────

def print_summary():
    print("\n[4/4] Summary")
    print("=" * 60)
    print(f"  Score leaderboards: {len(SCORE_LEADERBOARDS)}")
    print(f"  Achievements:       {len(ACHIEVEMENTS)}")
    print(f"  Total:              {len(SCORE_LEADERBOARDS) + len(ACHIEVEMENTS)}")
    print("=" * 60)
    print()
    print("Next steps:")
    print("  1. Verify in App Store Connect > Game Center")
    print("  2. Achievement images are optional but recommended")
    print("  3. Create a Game Center release when submitting your app")
    print("  4. Test with TestFlight sandbox before going live")


# ── Main ──────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="Bulk-create Game Center leaderboards and achievements for Number March")
    parser.add_argument("--key-id", required=True, help="App Store Connect API Key ID")
    parser.add_argument("--issuer-id", required=True, help="App Store Connect Issuer ID")
    parser.add_argument("--key-file", required=True, help="Path to .p8 private key file")
    parser.add_argument("--app-id", required=True, help="App Store Connect App ID (numeric)")
    parser.add_argument("--dry-run", action="store_true", help="Print what would be created without calling API")
    parser.add_argument("--leaderboards-only", action="store_true", help="Only create leaderboards, skip achievements")
    parser.add_argument("--achievements-only", action="store_true", help="Only create achievements, skip leaderboards")
    args = parser.parse_args()

    if args.dry_run:
        print("DRY RUN - No API calls will be made\n")
        print("Leaderboards to create:")
        for lb in SCORE_LEADERBOARDS:
            print(f"  {lb['vendorIdentifier']:30s}  {lb['referenceName']}")
        print(f"\nAchievements to create:")
        for ach in ACHIEVEMENTS:
            print(f"  {ach['vendorIdentifier']:30s}  {ach['referenceName']}  ({ach['points']} pts)")
        print_summary()
        return

    print("Generating JWT token...")
    token = generate_token(args.key_id, args.issuer_id, args.key_file)
    print("  Token generated.")

    gc_detail_id = get_or_create_gc_detail(token, args.app_id)
    if not args.achievements_only:
        create_all_leaderboards(token, gc_detail_id)
    if not args.leaderboards_only:
        create_all_achievements(token, gc_detail_id)
    print_summary()

    print("\nDone!")


if __name__ == "__main__":
    main()
