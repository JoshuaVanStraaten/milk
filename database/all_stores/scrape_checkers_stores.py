"""
Checkers Store Scraper

Uses the Hybris findStores endpoint (no auth required).
Same endpoint pattern as Shoprite — both are Shoprite Holdings Hybris sites.

Usage:
    python scrape_checkers_stores.py

Output: checkers_stores_all.json
"""

import json
import time
import urllib.request
import urllib.parse

QUERY_POINTS = [
    # ── Gauteng (dense metro — grid sweep) ────────────────────
    ("Gauteng",         -26.2041,    28.0473,    "Johannesburg CBD"),
    ("Gauteng",         -26.1076,    28.0567,    "Randburg"),
    ("Gauteng",         -26.0274,    28.0539,    "Sandton North"),
    ("Gauteng",         -26.1496,    28.0401,    "Rosebank"),
    ("Gauteng",         -25.9965,    28.1273,    "Midrand"),
    ("Gauteng",         -26.1844,    28.3163,    "Benoni"),
    ("Gauteng",         -26.2606,    28.1171,    "Alberton"),
    ("Gauteng",         -26.1142,    27.9474,    "Roodepoort"),
    ("Gauteng",         -26.2306,    27.8376,    "Soweto"),
    ("Gauteng",         -26.3691,    28.1463,    "Katlehong"),
    ("Gauteng",         -26.6625,    27.9713,    "Vereeniging"),
    ("Gauteng",         -26.0880,    27.7805,    "Krugersdorp"),
    ("Gauteng",         -26.1029,    28.2230,    "Kempton Park"),
    ("Gauteng",         -26.1885,    28.1225,    "Bedfordview"),
    ("Gauteng",         -26.2688,    28.2251,    "Germiston"),
    ("Gauteng",         -26.1626,    28.1707,    "Edenvale"),
    ("Gauteng",         -25.9650,    28.2108,    "Tembisa"),
    ("Gauteng",         -26.5605,    28.0181,    "Meyerton"),
    ("Gauteng",         -26.7251,    27.8448,    "Vanderbijlpark"),
    ("Gauteng",         -25.6722,    28.1100,    "Akasia"),
    ("Gauteng",         -26.3321,    28.3832,    "Springs"),
    ("Gauteng",         -25.7479,    28.2293,    "Pretoria"),
    ("Gauteng",         -25.8603,    28.1894,    "Centurion"),
    ("Gauteng",         -25.6145,    28.3565,    "Mamelodi"),
    ("Gauteng",         -26.4023,    27.6726,    "Carletonville"),
    ("Gauteng",         -26.2669,    28.0512,    "Oakdene/South JHB"),
    ("Gauteng",         -26.0673,    28.0736,    "Gallo Manor"),
    ("Gauteng",         -26.3432,    28.1820,    "Vosloorus"),
    ("Gauteng",         -25.7960,    28.3210,    "Pretoria East"),
    ("Gauteng",         -26.1034,    27.9247,    "Radiokop"),
    # ── Western Cape ──────────────────────────────────────────
    ("Western Cape",    -33.9249,    18.4241,    "Cape Town CBD"),
    ("Western Cape",    -33.8688,    18.5100,    "Bellville"),
    ("Western Cape",    -34.0836,    18.4681,    "Muizenberg"),
    ("Western Cape",    -33.9348,    18.8580,    "Stellenbosch"),
    ("Western Cape",    -33.7262,    18.9731,    "Paarl"),
    ("Western Cape",    -33.8727,    18.6346,    "Durbanville"),
    ("Western Cape",    -33.8259,    18.4877,    "Table View"),
    ("Western Cape",    -33.8526,    18.6967,    "Brackenfell"),
    ("Western Cape",    -34.0900,    18.8500,    "Somerset West"),
    ("Western Cape",    -33.5146,    18.5292,    "Malmesbury"),
    ("Western Cape",    -33.9631,    22.4576,    "George"),
    ("Western Cape",    -34.1825,    22.1467,    "Mossel Bay"),
    ("Western Cape",    -34.0473,    23.0475,    "Knysna"),
    ("Western Cape",    -33.0292,    17.8735,    "Saldanha"),
    ("Western Cape",    -34.4186,    19.2345,    "Hermanus"),
    ("Western Cape",    -33.3551,    19.0488,    "Worcester"),
    ("Western Cape",    -34.0573,    18.5100,    "Fish Hoek"),
    ("Western Cape",    -33.7900,    18.5000,    "Milnerton"),
    ("Western Cape",    -33.9400,    18.5800,    "Kenilworth"),
    ("Western Cape",    -33.8900,    18.6300,    "Kuils River/Kuilsrivier"),
    # ── KwaZulu-Natal ─────────────────────────────────────────
    ("KwaZulu-Natal",   -29.8587,    31.0218,    "Durban CBD"),
    ("KwaZulu-Natal",   -29.8047,    31.0403,    "Umhlanga"),
    ("KwaZulu-Natal",   -29.7271,    31.0852,    "Umhlanga Ridge"),
    ("KwaZulu-Natal",   -29.8493,    30.9356,    "Westville"),
    ("KwaZulu-Natal",   -29.9116,    30.8700,    "Chatsworth"),
    ("KwaZulu-Natal",   -29.6006,    30.3794,    "Pietermaritzburg"),
    ("KwaZulu-Natal",   -29.4960,    30.2335,    "Howick"),
    ("KwaZulu-Natal",   -27.7676,    29.9318,    "Newcastle"),
    ("KwaZulu-Natal",   -28.7810,    32.0377,    "Richards Bay"),
    ("KwaZulu-Natal",   -29.4519,    31.2179,    "Ballito"),
    ("KwaZulu-Natal",   -30.4490,    29.5383,    "Kokstad"),
    ("KwaZulu-Natal",   -28.3186,    30.3781,    "Dundee"),
    ("KwaZulu-Natal",   -29.6460,    31.0466,    "Verulam"),
    ("KwaZulu-Natal",   -30.5800,    30.5719,    "Port Shepstone"),
    ("KwaZulu-Natal",   -29.1163,    30.2230,    "Estcourt"),
    ("KwaZulu-Natal",   -29.9700,    30.9500,    "Amanzimtoti"),
    # ── Eastern Cape ──────────────────────────────────────────
    ("Eastern Cape",    -33.9608,    25.6022,    "Port Elizabeth"),
    ("Eastern Cape",    -33.9869,    25.6683,    "Summerstrand"),
    ("Eastern Cape",    -33.0153,    27.9116,    "East London"),
    ("Eastern Cape",    -31.5926,    29.1162,    "Mthatha"),
    ("Eastern Cape",    -33.3109,    26.5276,    "Makhanda"),
    ("Eastern Cape",    -33.9306,    24.9361,    "Jeffreys Bay"),
    ("Eastern Cape",    -31.9040,    26.8894,    "Queenstown"),
    ("Eastern Cape",    -32.8740,    27.3907,    "King Williams Town"),
    ("Eastern Cape",    -31.9017,    26.8842,    "Cradock"),
    # ── Free State ────────────────────────────────────────────
    ("Free State",      -29.1211,    26.2140,    "Bloemfontein"),
    ("Free State",      -27.9783,    26.7358,    "Welkom"),
    ("Free State",      -27.7694,    29.9379,    "Harrismith"),
    ("Free State",      -28.2309,    28.3169,    "Bethlehem"),
    ("Free State",      -27.6658,    27.2320,    "Kroonstad"),
    ("Free State",      -26.9035,    27.4581,    "Parys"),
    ("Free State",      -28.4418,    27.3247,    "Bethlehem area"),
    # ── North West ────────────────────────────────────────────
    ("North West",      -25.7751,    25.6419,    "Mafikeng"),
    ("North West",      -25.6700,    27.2426,    "Rustenburg"),
    ("North West",      -26.7150,    27.0976,    "Potchefstroom"),
    ("North West",      -26.8647,    26.6654,    "Klerksdorp"),
    ("North West",      -25.1719,    25.9229,    "Zeerust"),
    ("North West",      -25.7800,    27.7800,    "Brits"),
    ("North West",      -26.1550,    27.6760,    "Mogale City"),
    # ── Limpopo ───────────────────────────────────────────────
    ("Limpopo",         -23.8962,    29.4486,    "Polokwane"),
    ("Limpopo",         -24.1768,    29.0137,    "Mokopane"),
    ("Limpopo",         -23.8326,    30.1653,    "Tzaneen"),
    ("Limpopo",         -23.0399,    29.9010,    "Musina"),
    ("Limpopo",         -23.3968,    29.9780,    "Louis Trichardt"),
    ("Limpopo",         -24.5466,    29.2090,    "Marble Hall"),
    ("Limpopo",         -24.3158,    29.4785,    "Burgersfort"),
    ("Limpopo",         -23.5250,    30.2000,    "Giyani"),
    ("Limpopo",         -23.0800,    30.3800,    "Thohoyandou"),
    # ── Mpumalanga ────────────────────────────────────────────
    ("Mpumalanga",      -25.4753,    30.9694,    "Nelspruit"),
    ("Mpumalanga",      -25.7699,    29.2182,    "Witbank"),
    ("Mpumalanga",      -25.4425,    30.0395,    "Middelburg"),
    ("Mpumalanga",      -26.5449,    29.0772,    "Secunda"),
    ("Mpumalanga",      -26.4482,    29.9708,    "Ermelo"),
    ("Mpumalanga",      -26.9318,    29.2430,    "Standerton"),
    ("Mpumalanga",      -25.6619,    30.3538,    "Lydenburg"),
    ("Mpumalanga",      -25.4500,    31.0000,    "White River"),
    # ── Northern Cape ─────────────────────────────────────────
    ("Northern Cape",   -28.7282,    24.7499,    "Kimberley"),
    ("Northern Cape",   -28.4541,    21.2561,    "Upington"),
    ("Northern Cape",   -29.6680,    17.8838,    "Springbok"),
    ("Northern Cape",   -31.6340,    18.4879,    "Citrusdal area"),
    ("Northern Cape",   -30.6657,    18.0008,    "Vredendal"),
    ("Northern Cape",   -28.7668,    21.8542,    "Keimoes"),
]

BASE_URL = "https://products.checkers.co.za/store-finder/findStores"

HEADERS = {
    "accept": "application/json, text/javascript, */*; q=0.01",
    "accept-language": "en-US,en;q=0.9",
    "referer": "https://products.checkers.co.za/store-finder",
    "user-agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36",
    "x-requested-with": "XMLHttpRequest",
}


def get_session():
    """Get session cookies from initial page load."""
    req = urllib.request.Request(
        "https://products.checkers.co.za/store-finder",
        headers={
            "User-Agent": HEADERS["user-agent"],
            "Accept": "text/html",
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


def query_stores(lat, lng, cookies):
    """Query Checkers findStores for a given location."""
    params = urllib.parse.urlencode({
        "q": "",
        "latitude": str(lat),
        "longitude": str(lng),
        "filters": "",
    })
    url = f"{BASE_URL}?{params}"

    try:
        import requests as req_lib
        resp = req_lib.get(url, headers={**HEADERS, "Cookie": cookies}, timeout=15)
        resp.raise_for_status()
        return resp.json().get("data", [])
    except ImportError:
        req = urllib.request.Request(url, headers={**HEADERS, "Cookie": cookies})
        with urllib.request.urlopen(req, timeout=15) as resp:
            return json.loads(resp.read().decode()).get("data", [])
    except Exception as e:
        print(f"    Error: {e}")
        return []


def main():
    print("=" * 60)
    print("CHECKERS STORE SCRAPER (findStores — no WAF token needed)")
    print(f"Querying from {len(QUERY_POINTS)} locations across SA")
    print("=" * 60)

    print("\n[0] Getting session cookies...")
    cookies = get_session()
    time.sleep(1)

    all_stores = {}

    for i, (province, lat, lng, city) in enumerate(QUERY_POINTS):
        print(f"\n[{i+1}/{len(QUERY_POINTS)}] Querying near {city} ({province})...")
        stores = query_stores(lat, lng, cookies)

        new_count = 0
        for store in stores:
            store_id = store.get("name", "")
            display = store.get("displayName", "")
            # Skip liquor stores
            if "liquor" in display.lower():
                continue
            if store_id and store_id not in all_stores:
                all_stores[store_id] = store
                new_count += 1

        print(f"  Got {len(stores)} stores, {new_count} new (total: {len(all_stores)})")
        time.sleep(1.5)

    # Convert to standard format
    final = []
    for store_id, store in sorted(all_stores.items()):
        lat = store.get("latitude", "")
        lng = store.get("longitude", "")
        if not lat or not lng:
            print(f"  No coordinates for {store_id}: {store.get('displayName', '?')}")
            continue

        final.append({
            "retailer": "checkers",
            "store_code": store_id,
            "store_name": store.get("displayName", ""),
            "latitude": float(lat),
            "longitude": float(lng),
            "city": store.get("town", ""),
            "address": f"{store.get('line1', '')} {store.get('line2', '')}".strip(),
            "postal_code": store.get("postalCode", ""),
            "phone": store.get("phone", ""),
        })

    output_file = "checkers_stores_all.json"
    with open(output_file, "w") as f:
        json.dump(final, f, indent=2)

    print("\n" + "=" * 60)
    print("SUMMARY")
    print("=" * 60)
    print(f"  Total unique Checkers stores: {len(final)}")
    print(f"  Saved to: {output_file}")

    from collections import Counter
    cities = Counter(s["city"] for s in final)
    print(f"\n  Top 10 cities:")
    for c, count in cities.most_common(10):
        print(f"    {c}: {count}")


if __name__ == "__main__":
    main()
