"""
Shoprite Store Scraper

Shoprite's store finder is location-based, returning ~117 nearest stores per query.
We query from multiple points across South Africa to capture all stores.

Usage:
    python scrape_shoprite_stores.py

Output: shoprite_stores_all.json
"""

import json
import time
import urllib.request
import urllib.parse

# Query points spread across all 9 provinces of South Africa
QUERY_POINTS = [
    # Province,         Lat,         Lng,        City
    # Gauteng (dense — many stores)
    ("Gauteng",         -26.2041,    28.0473,    "Johannesburg CBD"),
    ("Gauteng",         -26.1076,    28.0567,    "Randburg"),
    ("Gauteng",         -26.1496,    28.0401,    "Rosebank"),
    ("Gauteng",         -26.0274,    28.0539,    "Sandton"),
    ("Gauteng",         -26.3321,    28.3832,    "Springs"),
    ("Gauteng",         -26.1929,    28.3048,    "Benoni"),
    ("Gauteng",         -26.2650,    28.1350,    "Alberton"),
    ("Gauteng",         -26.1825,    27.9987,    "Roodepoort"),
    ("Gauteng",         -26.6833,    27.9167,    "Vanderbijlpark"),
    ("Gauteng",         -25.7479,    28.2293,    "Pretoria"),
    ("Gauteng",         -25.8603,    28.1894,    "Centurion"),
    ("Gauteng",         -25.6145,    28.3565,    "Mamelodi"),
    ("Gauteng",         -26.0884,    27.7747,    "Krugersdorp"),
    ("Gauteng",         -26.4023,    27.6726,    "Carletonville"),
    # Western Cape
    ("Western Cape",    -33.9249,    18.4241,    "Cape Town CBD"),
    ("Western Cape",    -33.8688,    18.5100,    "Bellville"),
    ("Western Cape",    -34.0836,    18.4681,    "Muizenberg"),
    ("Western Cape",    -33.7262,    18.9731,    "Paarl"),
    ("Western Cape",    -33.9348,    18.8580,    "Stellenbosch"),
    ("Western Cape",    -33.5146,    18.5292,    "Malmesbury"),
    ("Western Cape",    -33.9631,    22.4576,    "George"),
    ("Western Cape",    -34.1825,    22.1467,    "Mossel Bay"),
    ("Western Cape",    -34.0473,    23.0475,    "Knysna"),
    ("Western Cape",    -33.0292,    17.8735,    "Saldanha"),
    ("Western Cape",    -33.0137,    18.2249,    "Citrusdal"),
    ("Western Cape",    -32.3504,    18.7281,    "Clanwilliam"),
    ("Western Cape",    -34.4186,    19.2345,    "Hermanus"),
    ("Western Cape",    -33.3551,    19.0488,    "Worcester"),
    # KwaZulu-Natal
    ("KwaZulu-Natal",   -29.8587,    31.0218,    "Durban"),
    ("KwaZulu-Natal",   -29.8047,    31.0403,    "Umhlanga"),
    ("KwaZulu-Natal",   -29.6006,    30.3794,    "Pietermaritzburg"),
    ("KwaZulu-Natal",   -27.7676,    29.9318,    "Newcastle"),
    ("KwaZulu-Natal",   -28.7810,    32.0377,    "Richards Bay"),
    ("KwaZulu-Natal",   -29.4519,    31.2179,    "Ballito"),
    ("KwaZulu-Natal",   -30.4490,    29.5383,    "Kokstad"),
    ("KwaZulu-Natal",   -28.3186,    30.3781,    "Dundee"),
    ("KwaZulu-Natal",   -29.1163,    30.2230,    "Estcourt"),
    # Eastern Cape
    ("Eastern Cape",    -33.9608,    25.6022,    "Port Elizabeth"),
    ("Eastern Cape",    -33.0153,    27.9116,    "East London"),
    ("Eastern Cape",    -31.5926,    29.1162,    "Mthatha"),
    ("Eastern Cape",    -33.3109,    26.5276,    "Makhanda"),
    ("Eastern Cape",    -33.9306,    24.9361,    "Jeffreys Bay"),
    ("Eastern Cape",    -32.3558,    26.8736,    "Queenstown"),
    ("Eastern Cape",    -31.9017,    26.8842,    "Cradock"),
    # Free State
    ("Free State",      -29.1211,    26.2140,    "Bloemfontein"),
    ("Free State",      -27.9783,    26.7358,    "Welkom"),
    ("Free State",      -27.7694,    29.9379,    "Harrismith"),
    ("Free State",      -29.7850,    27.2375,    "Trompsburg"),
    ("Free State",      -28.4418,    27.3247,    "Bethlehem"),
    # North West
    ("North West",      -25.7751,    25.6419,    "Mafikeng"),
    ("North West",      -25.6700,    27.2426,    "Rustenburg"),
    ("North West",      -26.7150,    27.0976,    "Potchefstroom"),
    ("North West",      -26.8647,    26.6654,    "Klerksdorp"),
    ("North West",      -25.1719,    25.9229,    "Zeerust"),
    # Limpopo
    ("Limpopo",         -23.8962,    29.4486,    "Polokwane"),
    ("Limpopo",         -24.1768,    29.0137,    "Mokopane"),
    ("Limpopo",         -23.8326,    30.1653,    "Tzaneen"),
    ("Limpopo",         -23.0399,    29.9010,    "Musina"),
    ("Limpopo",         -24.5466,    29.2090,    "Marble Hall"),
    ("Limpopo",         -23.3968,    29.9780,    "Louis Trichardt"),
    # Mpumalanga
    ("Mpumalanga",      -25.4753,    30.9694,    "Nelspruit"),
    ("Mpumalanga",      -25.7699,    29.2182,    "Witbank"),
    ("Mpumalanga",      -25.4425,    30.0395,    "Middelburg"),
    ("Mpumalanga",      -26.4482,    29.9708,    "Ermelo"),
    ("Mpumalanga",      -25.6619,    30.3538,    "Lydenburg"),
    # Northern Cape
    ("Northern Cape",   -28.7282,    24.7499,    "Kimberley"),
    ("Northern Cape",   -28.4541,    21.2561,    "Upington"),
    ("Northern Cape",   -29.6680,    17.8838,    "Springbok"),
    ("Northern Cape",   -30.6657,    18.0008,    "Vredendal"),
    ("Northern Cape",   -31.6340,    18.4879,    "Citrusdal area"),
    ("Northern Cape",   -28.7668,    21.8542,    "Keimoes"),
]

BASE_URL = "https://www.shoprite.co.za/store-finder/findStores"

HEADERS = {
    "accept": "application/json, text/javascript, */*; q=0.01",
    "accept-language": "en-US,en;q=0.9",
    "referer": "https://www.shoprite.co.za/store-finder",
    "user-agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
    "x-requested-with": "XMLHttpRequest",
}

# We need a session cookie - get one first
SESSION_COOKIES = ""  # Will be set by initial request


def get_session():
    """Make initial request to get session cookies."""
    req = urllib.request.Request(
        "https://www.shoprite.co.za/store-finder",
        headers={
            "User-Agent": HEADERS["user-agent"],
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        }
    )
    try:
        resp = urllib.request.urlopen(req, timeout=15)
        cookies = resp.headers.get_all("Set-Cookie") or []
        cookie_str = "; ".join(c.split(";")[0] for c in cookies)
        print(f"  Session cookies: {cookie_str[:80]}...")
        return cookie_str
    except Exception as e:
        print(f"  Failed to get session: {e}")
        return ""


def query_stores(lat: float, lng: float, cookies: str) -> list:
    """Query Shoprite store finder for a given location."""
    params = urllib.parse.urlencode({
        "q": "",
        "latitude": str(lat),
        "longitude": str(lng),
        "filters": "",
    })

    url = f"{BASE_URL}?{params}"
    headers = dict(HEADERS)
    if cookies:
        headers["Cookie"] = cookies

    req = urllib.request.Request(url, headers=headers)

    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = json.loads(resp.read().decode())
            return data.get("data", [])
    except Exception as e:
        print(f"    Error: {e}")
        return []


def main():
    print("=" * 60)
    print("SHOPRITE STORE SCRAPER")
    print(f"Querying from {len(QUERY_POINTS)} locations across SA")
    print("=" * 60)

    # Get session
    print("\n[0] Getting session cookies...")
    cookies = get_session()
    time.sleep(1)

    # Query from each point
    all_stores = {}  # keyed by store name (ID) to deduplicate

    for i, (province, lat, lng, city) in enumerate(QUERY_POINTS):
        print(f"\n[{i+1}/{len(QUERY_POINTS)}] Querying near {city} ({province})...")
        stores = query_stores(lat, lng, cookies)

        new_count = 0
        for store in stores:
            store_id = store.get("name", "")  # "name" is the store code/ID
            if store_id and store_id not in all_stores:
                all_stores[store_id] = store
                new_count += 1

        print(f"  Got {len(stores)} stores, {new_count} new (total: {len(all_stores)})")
        time.sleep(1.5)  # Be nice to their servers

    # Convert to our standard format
    final_stores = []
    for store_id, store in sorted(all_stores.items()):
        lat = store.get("latitude", "")
        lng = store.get("longitude", "")

        if not lat or not lng:
            print(f"  ⚠️ No coordinates for {store_id}: {store.get('displayName', '?')}")
            continue

        final_stores.append({
            "retailer": "shoprite",
            "store_code": store_id,
            "store_name": store.get("displayName", ""),
            "latitude": float(lat),
            "longitude": float(lng),
            "city": store.get("town", ""),
            "address": f"{store.get('line1', '')} {store.get('line2', '')}".strip(),
            "postal_code": store.get("postalCode", ""),
            "phone": store.get("phone", ""),
        })

    # Save
    output_file = "shoprite_stores_all.json"
    with open(output_file, "w") as f:
        json.dump(final_stores, f, indent=2)

    # Summary
    print("\n" + "=" * 60)
    print("SUMMARY")
    print("=" * 60)
    print(f"  Total unique stores: {len(final_stores)}")
    print(f"  Saved to: {output_file}")

    # City breakdown
    from collections import Counter
    cities = Counter(s["city"] for s in final_stores)
    print(f"\n  Top 10 cities:")
    for city, count in cities.most_common(10):
        print(f"    {city}: {count}")


if __name__ == "__main__":
    main()
