"""
PnP Store Normalizer

Reads pnp_stores_v2.json (2473 entries from PnP API) and extracts
relevant grocery stores with coordinates into our standard format.

Usage:
    python normalize_pnp_stores.py

Output: pnp_stores_all.json
"""

import json

# Store types that are actual grocery stores customers can shop at
GROCERY_TYPES = {
    "SUPER", "FAMILY", "EXPRESS", "LOCAL", "MARKET",
    "HYPER", "MINI", "WHOLESALE", "DAILY", "PNPGO",
}

# Province name normalization (PnP uses non-standard names)
PROVINCE_MAP = {
    "Northern Province": "Limpopo",
    "Freestate": "Free State",
    "North-West": "North West",
}


def main():
    with open("pnp_stores_v2.json", "r") as f:
        raw = json.load(f)

    print(f"Total entries in pnp_stores_v2.json: {len(raw)}")

    # Filter to grocery stores with coordinates
    stores = []
    skipped_no_geo = 0
    skipped_type = 0

    for s in raw:
        if s.get("storeType") not in GROCERY_TYPES:
            skipped_type += 1
            continue

        geo = s.get("geolocation")
        if not geo or not geo.get("latitude") or not geo.get("longitude"):
            skipped_no_geo += 1
            continue

        # Filter out stores outside South Africa (e.g. Zimbabwe FB* stores)
        lat = float(geo["latitude"])
        lng = float(geo["longitude"])
        if not (-35 <= lat <= -22 and 16 <= lng <= 33):
            skipped_type += 1  # count as wrong type
            continue

        addr = s.get("storeAddress", {})
        province_raw = (addr.get("province") or {}).get("name", "")
        province = PROVINCE_MAP.get(province_raw, province_raw)

        store_name = s.get("storeName", "")
        store_type = s.get("storeType", "")

        # Build display name like "Pick n Pay Sandton"
        display_prefix = "Pick n Pay"
        if store_type == "HYPER":
            display_prefix = "Pick n Pay Hyper"
        elif store_type == "FAMILY":
            display_prefix = "Pick n Pay Family"
        elif store_type == "EXPRESS":
            display_prefix = "Pick n Pay Express"
        elif store_type == "LOCAL":
            display_prefix = "Pick n Pay Local"
        elif store_type == "WHOLESALE":
            display_prefix = "Wholesale"
        elif store_type == "MINI":
            display_prefix = "Pick n Pay Mini"
        elif store_type == "PNPGO":
            display_prefix = "PnP Go"
        elif store_type == "DAILY":
            display_prefix = "Pick n Pay Daily"
        elif store_type == "MARKET":
            display_prefix = "Pick n Pay Market"

        display_name = f"{display_prefix} {store_name}"

        stores.append({
            "retailer": "pnp",
            "store_code": s.get("storeId", ""),
            "store_name": display_name,
            "latitude": float(geo["latitude"]),
            "longitude": float(geo["longitude"]),
            "province": province,
            "city": addr.get("city", ""),
            "address": addr.get("street", ""),
            "postal_code": addr.get("postalCode", ""),
        })

    # Save
    output_file = "pnp_stores_all.json"
    with open(output_file, "w") as f:
        json.dump(stores, f, indent=2)

    print(f"Skipped (wrong type): {skipped_type}")
    print(f"Skipped (no coords): {skipped_no_geo}")
    print(f"Grocery stores with coords: {len(stores)}")
    print(f"Saved to: {output_file}")

    from collections import Counter
    provinces = Counter(s["province"] for s in stores if s["province"])
    print(f"\nBy province:")
    for p, c in provinces.most_common():
        print(f"  {p}: {c}")

    types_in = Counter(s.get("storeType") for s in raw if s.get("storeType") in GROCERY_TYPES)
    print(f"\nBy store type:")
    for t, c in types_in.most_common():
        print(f"  {t}: {c}")


if __name__ == "__main__":
    main()
