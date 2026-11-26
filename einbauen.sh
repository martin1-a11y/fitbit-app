#!/bin/sh
# Version 4 · Baut unsere Zusätze in Pebble ein (wird von GitHub Actions aufgerufen, siehe
# .github/workflows/bauen.yml). Aufruf:  sh einbauen.sh <Pebble-Ordner>
# Pebble muss auf dem festen Stand ac1b90f stehen – die Änderungen unten passen genau dazu.
set -eu
HIER="$(cd "$(dirname "$0")" && pwd)"
cd "$1"

halt() { echo "FEHLER: $1" >&2; exit 1; }

# 1. Fitbit-Timer (Siri-Aktionen) und Gym/Habits als eigene Dateien dazulegen
cp "$HIER/FitbitTimer.swift" App/FitbitTimer.swift
cp "$HIER/GymHabits.swift" App/UI/GymHabits.swift
# Health-Daten per Kurzbefehl (AltStore lässt die HealthKit-Berechtigung weg)
cp "$HIER/KurzbefehlHealth.swift" App/KurzbefehlHealth.swift

# 2. Tab „Gym“ in die Leiste unten, Chip „Habits“ unter Trends
perl -0pi -e 's/(\.tag\(2\)\n)/$1            GymScreen().tabItem { Label("Gym", systemImage: "dumbbell") }.tag(4)\n/' App/UI/PebbleApp.swift
# Trends: TrendTopic/TrendsScreen/TopicBar komplett durch TrendsKopf.swift ersetzen
# (Chip „Habits“, Reihenfolge per Halten + Ziehen, Wischen zwischen den Trends)
KOPF="$HIER/TrendsKopf.swift" perl -0pi -e 'BEGIN { local $/; open my $f, "<", $ENV{KOPF} or die; $k = <$f>; close $f } s/private enum TrendTopic.*?(?=private struct MetricTrendView)/$k/s or die "kein Treffer\n"' App/UI/TrendsScreen.swift
grep -q 'fitbitTimer.trendReihenfolge' App/UI/TrendsScreen.swift || halt "Trends-Leiste ließ sich nicht einbauen."
[ "$(grep -c 'private enum TrendTopic' App/UI/TrendsScreen.swift)" -eq 1 ] || halt "TrendTopic doppelt."

# 3. Eigene App-Kennung (die von Pebble gehört dem Entwickler). AltStore hängt beim
#    Installieren noch die Kennung deiner Apple-ID an.
perl -pi -e 's/PRODUCT_BUNDLE_IDENTIFIER "com\.medpar\.air\.companion"/PRODUCT_BUNDLE_IDENTIFIER "de.fitbittimer.app"/' App/CMakeLists.txt
grep -q 'de.fitbittimer.app' App/CMakeLists.txt || halt "App-Kennung ließ sich nicht setzen."

# 4. Apple Health: echten Fehlertext zeigen; fehlt die Berechtigung (AltStore), auf den Kurzbefehl verweisen
perl -0pi -e 's/message = "Apple Health import didn\x{2019}t finish\. Your history is unchanged\."/message = error.localizedDescription.contains("entitlement") ? "Direkt lesen ist bei dieser Installation gesperrt (AltStore). Nimm den Kurzbefehl mit der Aktion \x{201E}Health-Daten \x{FC}bernehmen\x{201C}." : "Apple Health import didn\x{2019}t finish: \\(error.localizedDescription)"/ or die "kein Treffer\n"' -CSD App/HealthImport.swift
grep -q 'error.localizedDescription' App/HealthImport.swift || halt "Health-Fehlertext ließ sich nicht einbauen."

echo "Zusätze eingebaut."
# Ende Version 4
