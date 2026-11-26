# Fitbit-App

Die App **Pebble** ([github.com/medpar/pebble](https://github.com/medpar/pebble), MIT) mit drei Zusätzen für das Fitbit Air:
Fitbit-Timer per Siri, Tab „Gym“ und Habit-Tracker. GitHub baut die App, installiert wird sie mit **AltStore**.

## AltStore-Quelle
In AltStore: **Sources → + →** diese Adresse einfügen:

```
https://raw.githubusercontent.com/martin1-a11y/fitbit-app/main/altstore.json
```

Danach steht die App unter **Browse**; neue Versionen erscheinen unter **My Apps** als **Update**.
Daten (Gym, Habits, Armband-Schlüssel) bleiben bei Updates erhalten – nur Löschen der App oder eine andere Apple-ID verliert sie.

## Was hier liegt
| Datei | Wofür |
|---|---|
| `FitbitTimer.swift` | Siri-Aktionen „Fitbit-Timer starten / löschen / anzeigen“ (einmaliger Wecker auf dem Armband, jetzt + N min) |
| `GymHabits.swift` | Tab „Gym“ und Chip „Habits“ unter Trends |
| `einbauen.sh` | legt beides in Pebble ab (fester Stand `ac1b90f`) |
| `quelle.py` | schreibt die AltStore-Quelle `altstore.json` |
| `.github/workflows/bauen.yml` | der Bauauftrag (Mac-Server von GitHub) |

Bauen von Hand: Reiter **Actions → App bauen → Run workflow**. Fertige Dateien unter **Releases**.

## Neu-Signieren alle 7 Tage
Macht AltStore selbst, wenn AltServer am Windows-PC läuft (Autostart an) und PC + iPhone im selben WLAN sind
(iTunes: „Mit diesem iPhone über WLAN synchronisieren“). Notfalls AltStore → My Apps → **Refresh All**.

## Noch offen
Ohne die zwei Geräte-Schlüssel des Armbands kann die App nicht mit dem Fitbit Air sprechen (Gym und Habits gehen trotzdem).
Die Schlüssel werden später über ein Android-Handy geholt – sie kommen **nie** in dieses Repo, nur in den geschützten Speicher des iPhones.

Siri-Kurzbefehl (wenn die Schlüssel da sind): Kurzbefehle → + → „Fitbit-Timer starten“ → Minuten: **Jedes Mal fragen** → Name **Fitbit Timer**.

## Apple Health über einen Kurzbefehl
Direkt lesen darf die App Apple Health nicht: AltStore lässt beim Signieren mit kostenloser Apple-ID die HealthKit-Berechtigung weg
(„Missing com.apple.developer.healthkit entitlement“). Die Kurzbefehle-App darf es. Sie gibt die Werte an die Aktion
**„Health-Daten übernehmen“** (App „Pebble“) weiter. Die Bezeichnungen der Aktionen können je nach iOS-Version leicht abweichen.

Je Wert ein Block, hier für den Ruhepuls:
1. **Gesundheitsproben suchen**: Typ = Ruhepuls, Startdatum = in den letzten **90** Tagen, Grenze aus.
2. **Wiederholen mit jedem** (Eingabe: Gesundheitsproben). Darin eine Aktion **Text**:
   `Startdatum;Wert;Quelle`. Die drei Teile sind Variablen: „Wiederholungsobjekt“ einsetzen, antippen und die Eigenschaft wählen.
   Beim Startdatum Datumsformat **ISO 8601**. Dazwischen steht jeweils ein Strichpunkt `;`.
3. Nach „Ende der Wiederholung“: **Text kombinieren** (Wiederholungsergebnisse, mit „Neue Zeilen“).

Genauso für **HRV** (Herzfrequenzvariabilität) und **Schritte**. Beim **Schlaf** lautet die Zeile
`Startdatum;Enddatum;Wert;Quelle`, mit beiden Daten als ISO 8601. „Wert“ ist hier die Art, z. B. Kernschlaf oder Wach. „Wach“ und „Im Bett“ zählen nicht.

Am Ende: **Health-Daten übernehmen** und die vier kombinierten Texte in Ruhepuls / HRV / Schlaf / Schritte einsetzen.
Die Antwort nennt, wie viele Tage übernommen wurden, und zeigt eine Beispielzeile, falls eine Zeile nicht lesbar war.

Nach dem ersten Lauf „90 Tage“ auf **7 Tage** stellen (geht schneller). Dann unter Kurzbefehle → Automation eine neue Automation anlegen:
Tageszeit (z. B. 10 Uhr), **Sofort ausführen**, diesen Kurzbefehl. Ältere Tage bleiben gespeichert.
Welche Quelle bei mehreren gilt (z. B. Google Health oder iPhone), wählst du unter Band → Apple Health.
