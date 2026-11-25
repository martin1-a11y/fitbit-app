# Version 1 · Schreibt die AltStore-Quelle altstore.json (Katalog: welche Version gibt es, wo liegt die .ipa).
# Aufruf (im Bauauftrag):  python3 quelle.py <Pebble.app> <Fitbit-App.ipa> <Build-Nr> <Release-Tag>
# AltStore installiert nur, wenn alle Berechtigungen der App hier aufgeführt sind – darum liest das
# Skript sie direkt aus der gebauten App (Info.plist + Signatur), statt sie von Hand zu pflegen.
import json, os, plistlib, subprocess, sys, datetime
from pathlib import Path

app, ipa, nr, tag = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
repo = os.environ.get("GITHUB_REPOSITORY", "martin1-a11y/fitbit-app")
info = plistlib.loads(Path(app, "Info.plist").read_bytes())
roh = subprocess.run(["codesign", "-d", "--entitlements", ":-", app], capture_output=True).stdout
rechte = sorted(plistlib.loads(roh).keys()) if roh.strip() else []
privat = {k: v for k, v in info.items() if k.startswith("NS") and k.endswith("UsageDescription")}

datei = Path(__file__).with_name("altstore.json")
alt = json.loads(datei.read_text()) if datei.exists() else {}
alteVersionen = (alt.get("apps") or [{}])[0].get("versions", [])
neu = {
    "version": info["CFBundleShortVersionString"],
    "buildVersion": str(info["CFBundleVersion"]),
    "date": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "localizedDescription": f"Build {nr}",
    "downloadURL": f"https://github.com/{repo}/releases/download/{tag}/Fitbit-App.ipa",
    "size": os.path.getsize(ipa),
    "minOSVersion": "18.0",
}
quelle = {
    "name": "Fitbit-App",
    "identifier": "de.fitbittimer.quelle",
    "sourceURL": f"https://raw.githubusercontent.com/{repo}/main/altstore.json",
    "apps": [{
        "name": "Pebble",
        "bundleIdentifier": "de.fitbittimer.app",
        "developerName": "privat",
        "subtitle": "Fitbit Air: Timer, Gym, Habits",
        "localizedDescription": "Pebble (github.com/medpar/pebble) mit Fitbit-Timer, Gym-Tab und Habit-Tracker.",
        "iconURL": "https://raw.githubusercontent.com/medpar/pebble/ac1b90fc08f923efe0d5f2d3621119f7835fea35/App/Assets.xcassets/AppIcon.appiconset/AppIcon.png",
        "tintColor": "#3478F6",
        "versions": [neu] + [v for v in alteVersionen if v.get("buildVersion") != neu["buildVersion"]][:4],
        "appPermissions": {"entitlements": rechte, "privacy": privat},
    }],
    "news": [],
}
datei.write_text(json.dumps(quelle, ensure_ascii=False, indent=2) + "\n")
print(f"altstore.json: Version {neu['version']} (Build {neu['buildVersion']}), Rechte {rechte}, Datenschutz {sorted(privat)}")
# Ende Version 1
