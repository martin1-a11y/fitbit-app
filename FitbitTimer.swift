// Version 1 · Fitbit-Timer: Zusatz zu Pebble (github.com/medpar/pebble, Stand ac1b90f)
//
// Idee: Statt dass das iPhone wartet und dann einen Vibrationsbefehl schickt
// (iOS bremst wartende Kurzbefehle bei gesperrtem iPhone aus), legt diese
// Datei einen EINMALIGEN Wecker auf dem Armband an: jetzt + N Minuten.
// Danach zählt das Armband selbst – iPhone gesperrt, Bluetooth aus, egal.
// (Vom Nutzer am 15.11.2026 getestet: einmaliger Wecker aus Google Health,
// Bluetooth sofort aus → Armband vibrierte pünktlich.)
//
// Nur diese Datei kommt dazu, Pebble selbst bleibt unverändert. Die Aktionen
// erscheinen automatisch in der Kurzbefehle-App unter „Pebble“.
//
// Sicherheit: Die App merkt sich die Kennungen der Wecker, die SIE angelegt
// hat (UserDefaults „fitbitTimer.timers“). Nur solche Wecker werden wieder-
// verwendet oder gelöscht – und nur, wenn sie noch einmalig sind und auf der
// gemerkten Uhrzeit stehen. Normale Wecker aus Google Health werden nie
// angefasst.

import AppIntents
import Foundation

/// Ein vom Fitbit-Timer angelegter Wecker auf dem Armband.
struct FitbitTimerEintrag: Codable {
    let id: UInt64
    let faellig: Date
    let hour: Int
    let minute: Int
}

@MainActor
enum FitbitTimer {
    private static let schluessel = "fitbitTimer.timers"
    /// Nicht dabei gedrückt (Doppeltippen) → das Armband meldet sich nach
    /// 9 Minuten erneut. So lange gilt ein abgelaufener Timer noch als „aktiv“
    /// und wird nicht wiederverwendet.
    private static let nachlauf: TimeInterval = 30 * 60

    static var eintraege: [FitbitTimerEintrag] {
        get {
            guard let data = UserDefaults.standard.data(forKey: schluessel),
                  let liste = try? JSONDecoder().decode([FitbitTimerEintrag].self, from: data) else { return [] }
            return liste
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: schluessel) }
    }

    /// Laufende Timer (noch nicht fällig), nach Zeit geordnet.
    static var laufend: [FitbitTimerEintrag] {
        eintraege.filter { $0.faellig > Date() }.sorted { $0.faellig < $1.faellig }
    }

    static func uhrzeit(_ datum: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "de_DE"); f.dateFormat = "HH:mm"
        return f.string(from: datum)
    }

    /// Ziel auf die nächste volle Minute gerundet (Wecker kennen nur Stunde und Minute
    /// sicher; das Sekundenfeld ist unerprobt). Abweichung höchstens ±30 s.
    static func ziel(minuten: Int, ab jetzt: Date = Date()) -> Date {
        let roh = jetzt.addingTimeInterval(TimeInterval(minuten * 60))
        let sekunden = Calendar.current.component(.second, from: roh)
        let ohne = roh.addingTimeInterval(-TimeInterval(sekunden))
        return sekunden >= 30 ? ohne.addingTimeInterval(60) : ohne
    }

    /// Wecker auf dem Armband, der zu einem gemerkten Eintrag passt (gleiche
    /// Kennung, einmalig, gleiche Uhrzeit). Sonst nil – dann gehört er uns nicht.
    private static func weckerZu(_ e: FitbitTimerEintrag, in liste: AlarmList?) -> BandAlarm? {
        liste?.alarms.first { $0.id == e.id && !$0.recurring && $0.hour == e.hour && $0.minute == e.minute }
    }

    /// Ergebnis als Satz für Siri / Kurzbefehle.
    static func starten(minuten: Int) async -> String {
        let band = Services.shared.band
        if Services.shared.library.preview { return "Pebble läuft im Vorschau-Modus, es wurde nichts ans Armband geschickt." }
        band.refreshKeys()
        guard band.keysReady else {
            return "Pebble hat noch keinen Schlüssel für dein Armband."
        }
        guard await band.waitUntilIdle(seconds: 20) else { return "Das Armband ist gerade beschäftigt. Versuch es gleich noch einmal." }

        let faellig = ziel(minuten: minuten)
        let teile = Calendar.current.dateComponents([.hour, .minute], from: faellig)
        let hour = teile.hour ?? 0, minute = teile.minute ?? 0

        // 1. Alten, abgelaufenen Timer-Wecker wiederverwenden (hält die Weckerliste klein).
        //    Liegt der letzte Abruf vor seiner Fälligkeit, könnte das Armband ihn
        //    inzwischen selbst ausgeschaltet haben → erst frisch lesen.
        let alt = eintraege.filter { $0.faellig.addingTimeInterval(nachlauf) < Date() }
        if let erster = alt.first, (band.lastRead ?? .distantPast) < erster.faellig.addingTimeInterval(nachlauf) {
            _ = await band.run { band.start() }
            _ = await band.waitUntilIdle(seconds: 10)
        }
        var ok = false
        var id: UInt64?
        if let wieder = alt.compactMap({ e in weckerZu(e, in: band.alarms).map { (e, $0) } }).first {
            ok = await band.run { band.save(wieder.1, hour: hour, minute: minute, enabled: true, smartWake: false) }
            if ok { id = wieder.1.id }
            _ = await band.waitUntilIdle(seconds: 10)
        }

        // 2. Sonst neuen einmaligen Wecker anlegen.
        if !ok {
            let vorher = Set(band.alarms?.alarms.map(\.id) ?? [])
            let draft = AlarmDraft(hour: hour, minute: minute, enabled: true, smartWake: false, days: 0)
            ok = await band.run { band.create(draft) }
            if ok {
                let neu = (band.alarms?.alarms ?? []).filter { !$0.recurring && $0.hour == hour && $0.minute == minute }
                id = (neu.first { !vorher.contains($0.id) } ?? neu.max { $0.id < $1.id })?.id
            } else if let liste = band.alarms, liste.alarms.count >= liste.maximum {
                return "Auf dem Armband ist kein Platz mehr (höchstens \(liste.maximum) Wecker). Lösch einen Wecker oder sag „Fitbit-Timer löschen“."
            }
        }

        guard ok else {
            return band.status == "Save needs checking"
                ? "Unklar, ob der Timer angekommen ist. Öffne Pebble und zieh die Wecker-Liste nach unten."
                : "Das Armband war nicht erreichbar (\(band.status)). Kein Timer gestellt."
        }

        // Merken (alte Einträge ohne passenden Wecker fallen raus).
        var liste = eintraege.filter { e in e.id != id && weckerZu(e, in: band.alarms) != nil }
        if let id { liste.append(FitbitTimerEintrag(id: id, faellig: faellig, hour: hour, minute: minute)) }
        eintraege = liste

        let rest = Int((faellig.timeIntervalSinceNow / 60).rounded())
        return "Fitbit-Timer läuft: Das Armband vibriert um \(uhrzeit(faellig)) (in \(rest) Minuten). Zum Beenden doppelt aufs Armband tippen."
    }

    /// Löscht alle vom Fitbit-Timer angelegten Wecker vom Armband.
    static func allesLoeschen() async -> String {
        let band = Services.shared.band
        if Services.shared.library.preview { return "Pebble läuft im Vorschau-Modus." }
        guard !eintraege.isEmpty else { return "Es läuft kein Fitbit-Timer." }
        guard await band.waitUntilIdle(seconds: 20) else { return "Das Armband ist gerade beschäftigt. Versuch es gleich noch einmal." }
        _ = await band.run { band.start() }   // frisch lesen: nur passende Wecker löschen
        var geloescht = 0, fehler = 0
        for e in eintraege {
            _ = await band.waitUntilIdle(seconds: 10)
            guard let wecker = weckerZu(e, in: band.alarms) else { continue }
            if await band.run({ band.delete(wecker) }) { geloescht += 1 } else { fehler += 1 }
        }
        _ = await band.waitUntilIdle(seconds: 10)
        eintraege = eintraege.filter { weckerZu($0, in: band.alarms) != nil }
        if fehler > 0 { return "\(geloescht) gelöscht, \(fehler) ließen sich nicht löschen. Versuch es noch einmal." }
        return geloescht == 0 ? "Es war kein Fitbit-Timer mehr auf dem Armband." : "Fitbit-Timer gelöscht (\(geloescht))."
    }
}

// MARK: - Aktionen für Kurzbefehle und Siri

struct FitbitTimerStartenIntent: AppIntent {
    static var title: LocalizedStringResource = "Fitbit-Timer starten"
    static var description = IntentDescription("Stellt einen einmaligen Wecker auf dem Fitbit Air: Er vibriert nach der gewählten Zahl an Minuten – auch wenn das iPhone gesperrt oder weit weg ist.")
    static var openAppWhenRun = false

    @Parameter(title: "Minuten", description: "Nach wie vielen Minuten das Armband vibrieren soll (1 bis 1380).",
               inclusiveRange: (1, 1380), requestValueDialog: IntentDialog("Wie viele Minuten?"))
    var minuten: Int

    static var parameterSummary: some ParameterSummary { Summary("Fitbit-Timer auf \(\.$minuten) Minuten") }

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let satz = await FitbitTimer.starten(minuten: minuten)
        return .result(dialog: IntentDialog(stringLiteral: satz))
    }
}

struct FitbitTimerLoeschenIntent: AppIntent {
    static var title: LocalizedStringResource = "Fitbit-Timer löschen"
    static var description = IntentDescription("Löscht alle Fitbit-Timer vom Armband. Normale Wecker bleiben.")
    static var openAppWhenRun = false

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let satz = await FitbitTimer.allesLoeschen()
        return .result(dialog: IntentDialog(stringLiteral: satz))
    }
}

struct FitbitTimerAnzeigenIntent: AppIntent {
    static var title: LocalizedStringResource = "Fitbit-Timer anzeigen"
    static var description = IntentDescription("Sagt, welche Fitbit-Timer noch laufen.")
    static var openAppWhenRun = false

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let liste = FitbitTimer.laufend
        guard !liste.isEmpty else { return .result(dialog: "Es läuft kein Fitbit-Timer.") }
        let teile = liste.map { e -> String in
            let rest = max(0, Int((e.faellig.timeIntervalSinceNow / 60).rounded()))
            return "\(FitbitTimer.uhrzeit(e.faellig)) (in \(rest) min)"
        }
        return .result(dialog: IntentDialog(stringLiteral: "Fitbit-Timer: " + teile.joined(separator: ", ")))
    }
}
// Ende Version 1
