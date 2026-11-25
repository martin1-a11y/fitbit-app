#!/bin/sh
# Version 1 · Baut unsere Zusätze in Pebble ein (wird von GitHub Actions aufgerufen, siehe
# .github/workflows/bauen.yml). Aufruf:  sh einbauen.sh <Pebble-Ordner>
# Pebble muss auf dem festen Stand ac1b90f stehen – die Änderungen unten passen genau dazu.
set -eu
HIER="$(cd "$(dirname "$0")" && pwd)"
cd "$1"

halt() { echo "FEHLER: $1" >&2; exit 1; }

# 1. Fitbit-Timer (Siri-Aktionen) und Gym/Habits als eigene Dateien dazulegen
cp "$HIER/FitbitTimer.swift" App/FitbitTimer.swift
cp "$HIER/GymHabits.swift" App/UI/GymHabits.swift

# 2. Tab „Gym“ in die Leiste unten, Chip „Habits“ unter Trends (zwei kleine Änderungen an Pebble)
perl -0pi -e 's/(\.tag\(2\)\n)/$1            GymScreen().tabItem { Label("Gym", systemImage: "dumbbell") }.tag(4)\n/' App/UI/PebbleApp.swift
perl -0pi -e 's/case metric\(MetricKind\), training\n/case metric(MetricKind), training, habits\n/; s/\.metric\(\.sleepMidpoint\), \.training\]/.metric(.sleepMidpoint), .training, .habits]/; s/return kind\.short \}; return "Training" \}/return kind.short }; return self == .habits ? "Habits" : "Training" }/; s/(case \.training: TrainingTrendView\(\)\n)/$1                    case .habits: HabitTrackerView()\n/' App/UI/TrendsScreen.swift
grep -q 'GymScreen()' App/UI/PebbleApp.swift || halt "Gym-Tab ließ sich nicht einbauen."
[ "$(grep -c 'habits' App/UI/TrendsScreen.swift)" -ge 4 ] || halt "Habits-Chip ließ sich nicht einbauen."

# 3. Eigene App-Kennung (die von Pebble gehört dem Entwickler). AltStore hängt beim
#    Installieren noch die Kennung deiner Apple-ID an.
perl -pi -e 's/PRODUCT_BUNDLE_IDENTIFIER "com\.medpar\.air\.companion"/PRODUCT_BUNDLE_IDENTIFIER "de.fitbittimer.app"/' App/CMakeLists.txt
grep -q 'de.fitbittimer.app' App/CMakeLists.txt || halt "App-Kennung ließ sich nicht setzen."

echo "Zusätze eingebaut."
# Ende Version 1
