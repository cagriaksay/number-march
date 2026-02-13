#!/usr/bin/env python3
"""
Upload Game Center achievement and leaderboard images via App Store Connect API.

Prerequisites:
    pip install requests pyjwt cryptography

Usage:
    python upload_gc_images.py \
        --key-id YOUR_KEY_ID \
        --issuer-id YOUR_ISSUER_ID \
        --key-file /path/to/AuthKey_XXXX.p8 \
        --app-id YOUR_APP_ID

    # Upload only achievements or leaderboards:
    python upload_gc_images.py ... --achievements-only
    python upload_gc_images.py ... --leaderboards-only
"""

import argparse
import json
import os
import sys
import time
import jwt
import requests
from datetime import datetime, timedelta, timezone

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ACH_DIR = os.path.join(SCRIPT_DIR, "gc_images", "achievements")
LB_DIR = os.path.join(SCRIPT_DIR, "gc_images", "leaderboards")

BASE_URL = "https://api.appstoreconnect.apple.com/v1"


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
    return jwt.encode(payload, private_key, algorithm="ES256", headers=headers)


# ── API Helpers ────────────────────────────────────────────────

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
    else:
        print(f"    GET ERROR {resp.status_code}: {resp.text[:500]}")
        return None


def api_post(token, path, data):
    url = f"{BASE_URL}{path}"
    resp = requests.post(url, headers=api_headers(token), json=data)
    if resp.status_code in (200, 201):
        return resp.json()
    else:
        print(f"    POST ERROR {resp.status_code}: {resp.text[:500]}")
        return None


def api_patch(token, path, data):
    url = f"{BASE_URL}{path}"
    resp = requests.patch(url, headers=api_headers(token), json=data)
    if resp.status_code == 200:
        return resp.json()
    else:
        print(f"    PATCH ERROR {resp.status_code}: {resp.text[:500]}")
        return None


def api_delete(token, path):
    url = f"{BASE_URL}{path}"
    resp = requests.delete(url, headers=api_headers(token))
    if resp.status_code in (200, 204):
        return True
    else:
        print(f"    DELETE ERROR {resp.status_code}: {resp.text[:500]}")
        return False


def api_get_all_pages(token, path, params=None):
    """Fetch all pages of a paginated response."""
    all_data = []
    url = f"{BASE_URL}{path}"
    while url:
        resp = requests.get(url, headers=api_headers(token), params=params)
        params = None  # only use params for first request
        if resp.status_code != 200:
            print(f"    GET ERROR {resp.status_code}: {resp.text[:500]}")
            break
        result = resp.json()
        all_data.extend(result.get("data", []))
        url = result.get("links", {}).get("next")
    return all_data


# ── Image Upload ──────────────────────────────────────────────

def upload_image_data(upload_operations, file_path):
    """Upload binary data according to the uploadOperations from the API."""
    with open(file_path, "rb") as f:
        file_data = f.read()

    for op in upload_operations:
        method = op["method"]
        url = op["url"]
        req_headers = {h["name"]: h["value"] for h in op["requestHeaders"]}
        offset = op.get("offset", 0)
        length = op["length"]

        chunk = file_data[offset:offset + length]

        resp = requests.request(method, url, headers=req_headers, data=chunk)
        if resp.status_code not in (200, 201, 204):
            print(f"    UPLOAD ERROR {resp.status_code}: {resp.text[:300]}")
            return False
    return True


def commit_image(token, resource_path, image_id):
    """Commit the uploaded image by patching with uploaded=true."""
    data = {
        "data": {
            "type": resource_path.strip("/").split("/")[-1] if "/" in resource_path else resource_path,
            "id": image_id,
            "attributes": {
                "uploaded": True,
            },
        }
    }
    # The type needs to match the resource type
    return api_patch(token, f"/{resource_path}/{image_id}", data)


def delete_existing_image(token, resource_type, localization_type, localization_id):
    """Delete existing image for a localization if one exists."""
    # Derive singular image relationship name from resource_type
    # gameCenterAchievementImages -> gameCenterAchievementImage
    # gameCenterLeaderboardImages -> gameCenterLeaderboardImage
    image_rel = resource_type.rstrip("s")
    result = api_get(token, f"/{localization_type}s/{localization_id}/{image_rel}")
    if result and result.get("data"):
        image_id = result["data"]["id"]
        print(f"    Deleting existing image {image_id}...", end=" ")
        if api_delete(token, f"/{resource_type}/{image_id}"):
            print("OK")
            return True
        else:
            print("FAILED")
            return False
    return True  # No existing image, that's fine


def create_and_upload_image(token, resource_type, localization_type, localization_id, image_path):
    """
    Full image upload flow:
    0. Delete existing image if any
    1. Create image resource (reservation)
    2. Upload binary data
    3. Commit the upload
    """
    # Delete old image first
    delete_existing_image(token, resource_type, localization_type, localization_id)
    time.sleep(0.3)

    file_size = os.path.getsize(image_path)
    file_name = os.path.basename(image_path)

    # Step 1: Create image resource
    data = {
        "data": {
            "type": resource_type,
            "attributes": {
                "fileSize": file_size,
                "fileName": file_name,
            },
            "relationships": {
                localization_type: {
                    "data": {
                        "type": f"{localization_type}s",
                        "id": localization_id,
                    }
                }
            },
        }
    }
    result = api_post(token, f"/{resource_type}", data)
    if not result:
        return False

    image_id = result["data"]["id"]
    upload_ops = result["data"]["attributes"].get("uploadOperations", [])
    asset_state = result["data"]["attributes"].get("assetDeliveryState", {}).get("state", "")

    if not upload_ops:
        print(f"    No upload operations returned (state: {asset_state})")
        return False

    # Step 2: Upload binary data
    print(f"    Uploading {file_name} ({file_size} bytes, {len(upload_ops)} ops)...", end=" ")
    success = upload_image_data(upload_ops, image_path)
    if not success:
        print("FAILED")
        return False

    # Step 3: Commit
    commit_data = {
        "data": {
            "type": resource_type,
            "id": image_id,
            "attributes": {
                "uploaded": True,
            },
        }
    }
    commit_result = api_patch(token, f"/{resource_type}/{image_id}", commit_data)
    if commit_result:
        state = commit_result["data"]["attributes"].get("assetDeliveryState", {}).get("state", "UNKNOWN")
        print(f"OK (state: {state})")
        return True
    else:
        print("COMMIT FAILED")
        return False


# ── Achievement Image Upload ──────────────────────────────────

def upload_achievement_images(token, app_id):
    print("\n[1/2] Uploading achievement images...")

    # Get Game Center detail
    gc_result = api_get(token, f"/apps/{app_id}/gameCenterDetail")
    if not gc_result or not gc_result.get("data"):
        print("  ERROR: Could not find Game Center Detail")
        return
    gc_detail_id = gc_result["data"]["id"]
    print(f"  Game Center Detail: {gc_detail_id}")

    # Get all achievements
    achievements = api_get_all_pages(
        token,
        f"/gameCenterDetails/{gc_detail_id}/gameCenterAchievements",
        params={"limit": 200},
    )
    print(f"  Found {len(achievements)} achievements")

    uploaded = 0
    skipped = 0
    failed = 0

    for ach in achievements:
        vendor_id = ach["attributes"]["vendorIdentifier"]
        ach_id = ach["id"]
        ref_name = ach["attributes"]["referenceName"]

        # Find matching image
        image_path = os.path.join(ACH_DIR, f"{vendor_id}.png")
        if not os.path.exists(image_path):
            print(f"  [{vendor_id}] No image file found at {image_path}, skipping")
            skipped += 1
            continue

        # Get localizations for this achievement
        locs = api_get_all_pages(
            token,
            f"/gameCenterAchievements/{ach_id}/localizations",
        )
        if not locs:
            print(f"  [{vendor_id}] No localizations found, skipping")
            skipped += 1
            continue

        # Use the first (en-US) localization
        loc_id = locs[0]["id"]
        loc_locale = locs[0]["attributes"]["locale"]
        print(f"  [{vendor_id}] {ref_name} (loc: {loc_locale}, id: {loc_id})")

        success = create_and_upload_image(
            token,
            "gameCenterAchievementImages",
            "gameCenterAchievementLocalization",
            loc_id,
            image_path,
        )
        if success:
            uploaded += 1
        else:
            failed += 1

        time.sleep(0.5)  # Rate limiting

    print(f"\n  Achievement images: {uploaded} uploaded, {skipped} skipped, {failed} failed")


# ── Leaderboard Image Upload ─────────────────────────────────

def upload_leaderboard_images(token, app_id):
    print("\n[2/2] Uploading leaderboard images...")

    # Get Game Center detail
    gc_result = api_get(token, f"/apps/{app_id}/gameCenterDetail")
    if not gc_result or not gc_result.get("data"):
        print("  ERROR: Could not find Game Center Detail")
        return
    gc_detail_id = gc_result["data"]["id"]
    print(f"  Game Center Detail: {gc_detail_id}")

    # Get all leaderboards
    leaderboards = api_get_all_pages(
        token,
        f"/gameCenterDetails/{gc_detail_id}/gameCenterLeaderboards",
        params={"limit": 200},
    )
    print(f"  Found {len(leaderboards)} leaderboards")

    uploaded = 0
    skipped = 0
    failed = 0

    for lb in leaderboards:
        vendor_id = lb["attributes"]["vendorIdentifier"]
        lb_id = lb["id"]
        ref_name = lb["attributes"]["referenceName"]

        # Find matching image
        image_path = os.path.join(LB_DIR, f"{vendor_id}.png")
        if not os.path.exists(image_path):
            print(f"  [{vendor_id}] No image file found at {image_path}, skipping")
            skipped += 1
            continue

        # Get localizations for this leaderboard
        locs = api_get_all_pages(
            token,
            f"/gameCenterLeaderboards/{lb_id}/localizations",
        )
        if not locs:
            print(f"  [{vendor_id}] No localizations found, skipping")
            skipped += 1
            continue

        # Use the first (en-US) localization
        loc_id = locs[0]["id"]
        loc_locale = locs[0]["attributes"]["locale"]
        print(f"  [{vendor_id}] {ref_name} (loc: {loc_locale}, id: {loc_id})")

        success = create_and_upload_image(
            token,
            "gameCenterLeaderboardImages",
            "gameCenterLeaderboardLocalization",
            loc_id,
            image_path,
        )
        if success:
            uploaded += 1
        else:
            failed += 1

        time.sleep(0.5)  # Rate limiting

    print(f"\n  Leaderboard images: {uploaded} uploaded, {skipped} skipped, {failed} failed")


# ── Main ──────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="Upload Game Center images via App Store Connect API")
    parser.add_argument("--key-id", required=True, help="App Store Connect API Key ID")
    parser.add_argument("--issuer-id", required=True, help="App Store Connect Issuer ID")
    parser.add_argument("--key-file", required=True, help="Path to .p8 private key file")
    parser.add_argument("--app-id", required=True, help="App Store Connect App ID (numeric)")
    parser.add_argument("--achievements-only", action="store_true", help="Only upload achievement images")
    parser.add_argument("--leaderboards-only", action="store_true", help="Only upload leaderboard images")
    parser.add_argument("--dry-run", action="store_true", help="List what would be uploaded without calling API")
    args = parser.parse_args()

    if args.dry_run:
        print("DRY RUN - listing image files\n")
        print("Achievement images:")
        for f in sorted(os.listdir(ACH_DIR)):
            if f.endswith(".png"):
                size = os.path.getsize(os.path.join(ACH_DIR, f))
                print(f"  {f:40s}  {size:>8,d} bytes")
        print(f"\nLeaderboard images:")
        for f in sorted(os.listdir(LB_DIR)):
            if f.endswith(".png"):
                size = os.path.getsize(os.path.join(LB_DIR, f))
                print(f"  {f:40s}  {size:>8,d} bytes")
        return

    print("Generating JWT token...")
    token = generate_token(args.key_id, args.issuer_id, args.key_file)
    print("  Token generated.\n")

    do_both = not args.achievements_only and not args.leaderboards_only

    if do_both or args.achievements_only:
        upload_achievement_images(token, args.app_id)
    if do_both or args.leaderboards_only:
        upload_leaderboard_images(token, args.app_id)

    print("\nDone!")


if __name__ == "__main__":
    main()
