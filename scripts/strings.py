#!/usr/bin/env python3
"""Puts the text of the app into App/Resources/Localizable.xcstrings.

Build the app first. The build writes the text of each Swift file into a .stringsdata file,
because SWIFT_EMIT_LOC_STRINGS is on. The script adds each new key, keeps each translation,
and marks a key that the code does not use now as stale.

Usage: python3 scripts/strings.py [derived data folder]   (default: build/derived)
"""
import glob, json, os, sys

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
derived = sys.argv[1] if len(sys.argv) > 1 else os.path.join(root, "build", "derived")
catalog_path = os.path.join(root, "App", "Resources", "Localizable.xcstrings")

keys = set()
pattern = os.path.join(derived, "Build", "Intermediates.noindex", "Asabunko.build", "*-iphonesimulator", "Asabunko.build", "**", "*.stringsdata")
for path in glob.glob(pattern, recursive=True):
    with open(path) as f:
        data = json.load(f)
    for entry in data.get("tables", {}).get("Localizable", []):
        keys.add(entry["key"])
if not keys:
    sys.exit("No strings found. Build the app for the simulator first.")

catalog = {"sourceLanguage": "en", "strings": {}, "version": "1.0"}
if os.path.exists(catalog_path):
    with open(catalog_path) as f:
        catalog = json.load(f)
strings = catalog["strings"]
for key in keys:
    strings.setdefault(key, {}).pop("extractionState", None)
for key, entry in strings.items():
    if key not in keys:
        entry["extractionState"] = "stale"
catalog["strings"] = dict(sorted(strings.items()))
with open(catalog_path, "w") as f:
    json.dump(catalog, f, ensure_ascii=False, indent=2, sort_keys=True)
    f.write("\n")
missing = [k for k, e in strings.items() if k in keys and "ja" not in e.get("localizations", {})]
print(f"{len(keys)} keys, {len(missing)} with no Japanese text.")
