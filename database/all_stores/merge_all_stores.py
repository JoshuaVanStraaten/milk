"""
Merge All Stores

Combines scraped store data from all 4 retailers into all_stores_combined.json.
Also enriches missing province/city via Nominatim reverse geocoding.

Usage:
    python merge_all_stores.py [--skip-enrich]

Input files (all optional — skips missing):
    pnp_stores_all.json
    checkers_stores_all.json
    shoprite_stores_all.json
    woolworths_stores_all.json

Output: all_stores_combined.json
"""

import json
import os
import sys
import time
import urllib.request
import urllib.parse

# Valid SA provinces
VALID_PROVINCES = {
    "Eastern Cape", "Free State", "Gauteng", "KwaZulu-Natal",
    "Limpopo", "Mpumalanga", "North West", "Northern Cape", "Western Cape",
}

# Common misspellings / alternate names
PROVINCE_NORMALIZE = {
    "kwazulu natal": "KwaZulu-Natal",
    "kwazulu-natal": "KwaZulu-Natal",
    "kzn": "KwaZulu-Natal",
    "northern province": "Limpopo",
    "freestate": "Free State",
    "free state": "Free State",
    "north-west": "North West",
    "north west": "North West",
    "eastern cape": "Eastern Cape",
    "western cape": "Western Cape",
    "gauteng": "Gauteng",
    "limpopo": "Limpopo",
    "mpumalanga": "Mpumalanga",
    "northern cape": "Northern Cape",
}

INPUT_FILES = {
    "pnp": "pnp_stores_all.json",
    "checkers": "checkers_stores_all.json",
    "shoprite": "shoprite_stores_all.json",
    "woolworths": "woolworths_stores_all.json",
}


def normalize_province(raw):
    """Normalize province name to standard form."""
    if not raw:
        return ""
    key = raw.strip().lower()
    return PROVINCE_NORMALIZE.get(key, raw.strip())


def validate_store(store):
    """Check if a store record is valid."""
    errors = []
    if not store.get("retailer"):
        errors.append("missing retailer")
    if not store.get("store_code"):
        errors.append("missing store_code")
    if not store.get("store_name"):
        errors.append("missing store_name")

    lat = store.get("latitude")
    lng = store.get("longitude")
    if lat is None or lng is None:
        errors.append("missing coordinates")
    elif not (-35 <= lat <= -22 and 16 <= lng <= 33):
        errors.append(f"coordinates out of SA bounds: ({lat}, {lng})")

    return errors


def reverse_geocode(lat, lng):
    """Reverse geocode coordinates using Nominatim."""
    url = (
        f"https://nominatim.openstreetmap.org/reverse?"
        f"lat={lat}&lon={lng}&format=json&addressdetails=1"
    )
    headers = {
        "User-Agent": "MilkApp-StoreEnrich/1.0 (grocery price comparison app)",
    }
    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read().decode())
            addr = data.get("address", {})
            province = addr.get("state", "")
            city = (
                addr.get("city")
                or addr.get("town")
                or addr.get("suburb")
                or addr.get("village")
                or ""
            )
            return province, city
    except Exception as e:
        print(f"    Geocode error for ({lat}, {lng}): {e}")
        return "", ""


def main():
    skip_enrich = "--skip-enrich" in sys.argv

    print("=" * 60)
    print("MERGE ALL STORES")
    print("=" * 60)

    # Load previously enriched data first (so we don't re-geocode)
    all_stores = {}  # key: (retailer, store_code)
    stats = {}

    prev_file = "all_stores_combined.json"
    prev_enriched = {}
    if os.path.exists(prev_file):
        with open(prev_file) as f:
            prev = json.load(f)
        for s in prev:
            key = (s["retailer"], s["store_code"])
            prev_enriched[key] = s
        print(f"\n  Loaded {len(prev_enriched)} previously enriched stores for reference")

    for retailer, filename in INPUT_FILES.items():
        if not os.path.exists(filename):
            print(f"\n  {filename}: NOT FOUND (skipping)")
            continue

        with open(filename) as f:
            stores = json.load(f)

        count = 0
        for store in stores:
            # Ensure retailer is set
            store["retailer"] = store.get("retailer", retailer)
            store["province"] = normalize_province(store.get("province", ""))

            key = (store["retailer"], store["store_code"])
            if key not in all_stores:
                # Apply previously enriched data
                if key in prev_enriched:
                    prev = prev_enriched[key]
                    for field in ["province", "city", "address"]:
                        if prev.get(field) and not store.get(field):
                            store[field] = prev[field]
                all_stores[key] = store
                count += 1
            else:
                # Merge: prefer new data but keep old fields if new is empty
                existing = all_stores[key]
                for field in ["province", "city", "address", "postal_code", "phone"]:
                    if store.get(field) and not existing.get(field):
                        existing[field] = store[field]

        stats[retailer] = count
        print(f"\n  {filename}: {len(stores)} entries, {count} new")

    print(f"\n  Total unique stores: {len(all_stores)}")

    # Enrich missing province/city
    if not skip_enrich:
        needs_province = [s for s in all_stores.values() if not s.get("province")]
        needs_city = [s for s in all_stores.values() if not s.get("city")]

        # Only enrich stores that need BOTH (or just province, since that's critical)
        to_enrich = [s for s in all_stores.values()
                     if not s.get("province") and s.get("latitude") and s.get("longitude")]

        if to_enrich:
            print(f"\n  Enriching {len(to_enrich)} stores missing province...")
            print(f"  (Rate limited to 1 req/sec — est. {len(to_enrich)} seconds)")

            for i, store in enumerate(to_enrich):
                province, city = reverse_geocode(store["latitude"], store["longitude"])
                if province:
                    store["province"] = normalize_province(province)
                if city and not store.get("city"):
                    store["city"] = city

                if (i + 1) % 20 == 0:
                    print(f"    Enriched {i+1}/{len(to_enrich)}...")

                time.sleep(1.1)  # Nominatim rate limit

            print(f"    Done enriching {len(to_enrich)} stores")
        else:
            print(f"\n  No stores need province enrichment")
    else:
        print(f"\n  Skipping enrichment (--skip-enrich)")

    # Remove stores outside SA (Eswatini, Botswana, Lesotho, etc.)
    non_sa_provinces = {
        "Manzini", "Hhohho", "Shiselweni", "Lubombo",  # Eswatini
        "Maseru District", "Leribe District", "Berea District",  # Lesotho
        "Jwaneng Town", "Gaborone",  # Botswana
    }
    before_filter = len(all_stores)
    all_stores = {
        k: v for k, v in all_stores.items()
        if v.get("province", "") not in non_sa_provinces
    }
    removed_foreign = before_filter - len(all_stores)
    if removed_foreign:
        print(f"\n  Removed {removed_foreign} non-SA stores (Eswatini/Botswana/Lesotho)")

    # Validate
    print(f"\n  Validating...")
    invalid = []
    for key, store in all_stores.items():
        errors = validate_store(store)
        if errors:
            invalid.append((store, errors))

    if invalid:
        print(f"  {len(invalid)} stores with issues:")
        for store, errors in invalid[:10]:
            print(f"    {store['retailer']}/{store['store_code']}: {', '.join(errors)}")
        if len(invalid) > 10:
            print(f"    ... and {len(invalid) - 10} more")

    # Build final output — only include fields matching our DB schema
    final = []
    for store in sorted(all_stores.values(), key=lambda s: (s["retailer"], s["store_code"])):
        final.append({
            "retailer": store["retailer"],
            "store_code": store["store_code"],
            "store_name": store["store_name"],
            "latitude": store.get("latitude"),
            "longitude": store.get("longitude"),
            "province": store.get("province", ""),
            "city": store.get("city", ""),
            "address": store.get("address", ""),
        })

    output_file = "all_stores_combined.json"
    with open(output_file, "w") as f:
        json.dump(final, f, indent=2)

    # Summary
    print(f"\n" + "=" * 60)
    print("FINAL SUMMARY")
    print("=" * 60)

    from collections import Counter
    by_retailer = Counter(s["retailer"] for s in final)
    print(f"\n  By retailer:")
    for r, c in by_retailer.most_common():
        print(f"    {r}: {c}")

    by_province = Counter(s["province"] for s in final if s["province"])
    empty_province = sum(1 for s in final if not s["province"])
    print(f"\n  By province:")
    for p, c in by_province.most_common():
        print(f"    {p}: {c}")
    if empty_province:
        print(f"    (empty): {empty_province}")

    print(f"\n  Total: {len(final)} stores")
    print(f"  Saved to: {output_file}")
    print(f"  Invalid: {len(invalid)}")


if __name__ == "__main__":
    main()
