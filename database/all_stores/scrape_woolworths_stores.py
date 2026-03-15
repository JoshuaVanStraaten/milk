"""
Woolworths Store Scraper v2

Two-step approach:
1. getPrediction: Convert address text -> Google Place ID
2. validatePlace: Use Place ID -> get nearby stores

Usage:
    python scrape_woolworths_stores.py

Output: woolworths_stores_all.json
"""

import json
import time
import sys
import uuid

try:
    import requests
    USE_REQUESTS = True
except ImportError:
    import urllib.request
    import urllib.parse
    USE_REQUESTS = False

QUERY_ADDRESSES = [
    ("Gauteng - Pretoria", "2 Saltus Street, Centurion"),
    ("Gauteng - JHB North", "Sandton Drive, Sandton"),
    ("Gauteng - JHB South", "Main Road, Alberton"),
    ("Gauteng - JHB East", "North Rand Road, Boksburg"),
    ("Gauteng - JHB West", "Ontdekkers Road, Roodepoort"),
    ("Gauteng - Soweto", "Maponya Mall, Soweto"),
    ("Western Cape - CBD", "Adderley Street, Cape Town"),
    ("Western Cape - South", "Main Road, Constantia"),
    ("Western Cape - North", "Durbanville Road, Durbanville"),
    ("Western Cape - Somerset", "Main Road, Somerset West"),
    ("Western Cape - Stellenbosch", "Dorp Street, Stellenbosch"),
    ("Western Cape - Paarl", "Main Street, Paarl"),
    ("Western Cape - George", "York Street, George"),
    ("KZN - Durban North", "Umhlanga Rocks Drive, Umhlanga"),
    ("KZN - Durban South", "South Coast Road, Durban"),
    ("KZN - PMB", "Church Street, Pietermaritzburg"),
    ("KZN - Ballito", "Ballito Drive, Ballito"),
    ("KZN - Newcastle", "Scott Street, Newcastle"),
    ("Eastern Cape - PE", "Main Street, Port Elizabeth"),
    ("Eastern Cape - EL", "Oxford Street, East London"),
    ("Free State - Bloem", "Nelson Mandela Drive, Bloemfontein"),
    ("North West - Rustenburg", "Fatima Bhayat Street, Rustenburg"),
    ("North West - Klerksdorp", "Emily Hobhouse Street, Klerksdorp"),
    ("Limpopo - Polokwane", "Landros Mare Street, Polokwane"),
    ("Mpumalanga - Nelspruit", "Samora Machel Drive, Nelspruit"),
    ("Mpumalanga - Witbank", "Mandela Street, Witbank"),
    ("Northern Cape - Kimberley", "Du Toitspan Road, Kimberley"),
]

BASE_URL = "https://www.woolworths.co.za"

HEADERS = {
    "accept": "application/json, text/plain, */*",
    "accept-language": "en-US,en;q=0.9",
    "referer": "https://www.woolworths.co.za/",
    "user-agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
    "x-requested-by": "Woolworths Online",
    "iscognito": "true",
}


def make_request(url, cookies_str=""):
    headers = dict(HEADERS)
    if cookies_str:
        headers["Cookie"] = cookies_str
    try:
        if USE_REQUESTS:
            resp = requests.get(url, headers=headers, timeout=20)
            if resp.status_code == 403:
                return None
            resp.raise_for_status()
            return resp.json()
        else:
            req = urllib.request.Request(url, headers=headers)
            with urllib.request.urlopen(req, timeout=20) as resp:
                return json.loads(resp.read().decode())
    except Exception as e:
        if "403" in str(e):
            return None
        print(f"    Error: {e}")
        return {}


def get_prediction(address, session_token, cookies_str=""):
    encoded = urllib.parse.quote(address) if not USE_REQUESTS else address.replace(" ", "+")
    url = f"{BASE_URL}/google/getPrediction/?id={session_token}&input={encoded}"
    result = make_request(url, cookies_str)
    if not result:
        return None
    predictions = result.get("predictions", [])
    if predictions:
        return {
            "place_id": predictions[0]["place_id"],
            "main_text": predictions[0].get("structured_formatting", {}).get("main_text", address),
            "description": predictions[0].get("description", ""),
        }
    return None


def validate_place(place_id, main_text, session_token, cookies_str=""):
    encoded_text = urllib.parse.quote(main_text) if not USE_REQUESTS else main_text.replace(" ", "+")
    url = (
        f"{BASE_URL}/server/validatePlace?"
        f"placeId={place_id}&sessionToken={session_token}"
        f"&mainText={encoded_text}&inventoryCheck=false"
    )
    result = make_request(url, cookies_str)
    if not result:
        return None
    return result.get("stores", [])


def main():
    print("=" * 60)
    print("WOOLWORTHS STORE SCRAPER v2")
    print(f"Querying from {len(QUERY_ADDRESSES)} locations across SA")
    print("=" * 60)

    session_token = str(uuid.uuid4())
    cookies_str = ""

    print("\n[0] Testing getPrediction without cookies...")
    test = get_prediction("Sandton Drive, Sandton", session_token)

    if test is None:
        print("  Got 403. Need browser cookies.")
        print("\n  Copy the Cookie header from your Woolworths network request.\n")
        cookies_str = input("Paste cookie string (or Enter to skip): ").strip()
        if cookies_str:
            test = get_prediction("Sandton Drive, Sandton", session_token, cookies_str)
            if test is None:
                print("  Still 403. Cookies may have expired.")
                sys.exit(1)

    if test:
        print(f"  Got Place ID: {test['place_id']}")
        print(f"  Description: {test['description']}")
    else:
        print("  No predictions but no 403. Continuing...")

    all_stores = {}
    failed = []

    for i, (label, address) in enumerate(QUERY_ADDRESSES):
        print(f"\n[{i+1}/{len(QUERY_ADDRESSES)}] {label}: {address}")

        session_token = str(uuid.uuid4())
        prediction = get_prediction(address, session_token, cookies_str)

        if prediction is None:
            print("  403 on getPrediction")
            failed.append((label, address, "403"))
            continue
        if not prediction:
            print("  No prediction found")
            failed.append((label, address, "no prediction"))
            continue

        place_id = prediction["place_id"]
        main_text = prediction["main_text"]
        print(f"  -> Place ID: {place_id} ({prediction['description'][:60]})")

        time.sleep(1)

        stores = validate_place(place_id, main_text, session_token, cookies_str)

        if stores is None:
            print("  403 on validatePlace")
            failed.append((label, address, "403 validate"))
            continue

        new_count = 0
        for store in stores:
            sid = store.get("storeId", "")
            if not sid or not sid.isdigit():
                continue
            if sid not in all_stores:
                all_stores[sid] = {
                    "retailer": "woolworths",
                    "store_code": sid,
                    "store_name": store.get("storeName", ""),
                    "latitude": store.get("latitude"),
                    "longitude": store.get("longitude"),
                    "address": store.get("storeAddress", ""),
                    "delivery_type": store.get("storeDeliveryType", ""),
                }
                new_count += 1

        print(f"  Got {len(stores)} entries, {new_count} new stores (total: {len(all_stores)})")
        time.sleep(2)

    final = sorted(all_stores.values(), key=lambda s: s["store_code"])
    output_file = "woolworths_stores_all.json"
    with open(output_file, "w") as f:
        json.dump(final, f, indent=2)

    print("\n" + "=" * 60)
    print("SUMMARY")
    print("=" * 60)
    print(f"  Total unique Woolworths stores: {len(final)}")
    print(f"  Failed locations: {len(failed)}")
    print(f"  Saved to: {output_file}")

    if failed:
        print(f"\n  Failed:")
        for label, addr, reason in failed:
            print(f"    {label}: {reason}")

    from collections import Counter
    dtypes = Counter(s["delivery_type"] for s in final)
    print(f"\n  By delivery type:")
    for t, c in dtypes.most_common():
        print(f"    {t}: {c}")


if __name__ == "__main__":
    main()
