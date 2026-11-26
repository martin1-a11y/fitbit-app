// Version 1 · Health-Daten per Kurzbefehl: Zusatz zu Pebble (github.com/medpar/pebble, Stand ac1b90f)
//
// Warum: AltStore signiert die App mit einer kostenlosen Apple-ID und lässt dabei
// die HealthKit-Berechtigung weg („Missing com.apple.developer.healthkit
// entitlement“, getestet am 26.11.2026). Die App darf Apple Health also nicht
// selbst lesen. Die Kurzbefehle-App darf es – ein Kurzbefehl sucht die Werte
// und reicht sie als Text an die Aktion „Health-Daten übernehmen“ weiter.
//
// Text je Wert, eine Zeile je Messung, Teile mit „;“ getrennt:
//   Ruhepuls, HRV, Schritte:  Datum;Wert;Quelle
//   Schlaf:                   Beginn;Ende;Art;Quelle
// Datum am liebsten ISO 8601 (im Kurzbefehl einstellbar), deutsche Formate gehen auch.
// Gespeichert wird wie beim echten Import: je Tag und Quelle ein Wert, Quellen
// getrennt (Auswahl unter Band → Apple Health). Ältere Tage bleiben erhalten,
// nur die gelieferten Tage werden ersetzt.

import AppIntents
import Foundation

@MainActor
enum KurzbefehlHealth {
    struct Zeile {
        let start: Date
        let ende: Date?
        let wert: Double?
        let art: String
        let quelle: String
    }

    private static let iso = ISO8601DateFormatter()
    private static let deutsch: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "de_DE"); f.timeZone = .current; return f
    }()
    private static let muster = ["dd.MM.yyyy, HH:mm:ss", "dd.MM.yyyy, HH:mm", "dd.MM.yy, HH:mm:ss", "dd.MM.yy, HH:mm",
                                 "d. MMMM yyyy 'um' HH:mm:ss", "d. MMMM yyyy 'um' HH:mm", "d. MMM yyyy 'um' HH:mm",
                                 "d. MMMM yyyy, HH:mm", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "dd.MM.yyyy"]
    private static let erkenner = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)

    static func datum(_ roh: String) -> Date? {
        let t = roh.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        for o: ISO8601DateFormatter.Options in [[.withInternetDateTime], [.withInternetDateTime, .withFractionalSeconds], [.withFullDate]] {
            iso.formatOptions = o
            if let d = iso.date(from: t) { return d }
        }
        for m in muster {
            deutsch.dateFormat = m
            if let d = deutsch.date(from: t) { return d }
        }
        return erkenner?.firstMatch(in: t, range: NSRange(t.startIndex..., in: t))?.date
    }

    /// Zahl aus dem Kurzbefehl („58“, „45,3“, „12.345“). `ganz` = Schritte: Punkte/Kommas sind Tausender.
    static func zahl(_ roh: String, ganz: Bool) -> Double? {
        var t = String(roh.filter { "0123456789,.-".contains($0) })
        if ganz { t = t.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: "") }
        else if t.contains(",") && t.contains(".") { t = t.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".") }
        else { t = t.replacingOccurrences(of: ",", with: ".") }
        return Double(t)
    }

    /// Zerlegt den Text. Gibt gelesene Zeilen und die erste unlesbare zurück.
    static func zeilen(_ roh: String?, schlaf: Bool, ganz: Bool = false) -> (ok: [Zeile], fehler: Int, beispiel: String?) {
        var ok: [Zeile] = []; var fehler = 0; var beispiel: String?
        for zeile in (roh ?? "").components(separatedBy: .newlines) {
            let z = zeile.trimmingCharacters(in: .whitespaces)
            if z.isEmpty { continue }
            let teile = z.components(separatedBy: z.contains(";") ? ";" : "\t").map { $0.trimmingCharacters(in: .whitespaces) }
            var gelesen: Zeile?
            if schlaf, teile.count >= 2, let a = datum(teile[0]), let b = datum(teile[1]) {
                gelesen = Zeile(start: a, ende: b, wert: nil, art: teile.count > 2 ? teile[2] : "",
                                quelle: teile.count > 3 ? teile[3...].joined(separator: ";") : "")
            } else if !schlaf, teile.count >= 2, let a = datum(teile[0]), let w = zahl(teile[1], ganz: ganz) {
                gelesen = Zeile(start: a, ende: nil, wert: w, art: "",
                                quelle: teile.count > 2 ? teile[2...].joined(separator: ";") : "")
            }
            if let gelesen { ok.append(gelesen) } else { fehler += 1; if beispiel == nil { beispiel = String(z.prefix(60)) } }
        }
        return (ok, fehler, beispiel)
    }

    static func quellenID(_ q: String) -> String { "kurzbefehl:" + (q.isEmpty ? "apple-health" : q.lowercased()) }
    static func quellenName(_ q: String) -> String { (q.isEmpty ? "Apple Health" : q) + " (Kurzbefehl)" }

    /// Mittelwert je Tag und Quelle (Ruhepuls, HRV) – wie der echte Import.
    static func mittel(_ z: [Zeile], art: MetricKind, bereich: ClosedRange<Double>) -> [DailyMetric] {
        let cal = Calendar.current
        let gruppen = Dictionary(grouping: z.filter { r in r.wert.map { bereich.contains($0) } ?? false }) { "\($0.quelle)|\(cal.startOfDay(for: $0.start).timeIntervalSince1970)" }
        return gruppen.values.compactMap { g in
            guard let erste = g.first, let m = FitnessMath.mean(g.compactMap(\.wert)) else { return nil }
            return DailyMetric(kind: art, date: cal.startOfDay(for: erste.start), value: m,
                               sourceID: quellenID(erste.quelle), sourceName: quellenName(erste.quelle))
        }
    }

    /// Summe je Tag und Quelle (Schritte). Heute (läuft noch) und der älteste
    /// Tag (vom Suchzeitraum evtl. angeschnitten) fallen weg.
    static func summe(_ z: [Zeile]) -> [DailyMetric] {
        let cal = Calendar.current; let heute = cal.startOfDay(for: Date())
        return Dictionary(grouping: z, by: \.quelle).flatMap { quelle, reihe -> [DailyMetric] in
            var tage: [Date: Double] = [:]
            for r in reihe { if let w = r.wert, w >= 0 { tage[cal.startOfDay(for: r.start), default: 0] += w } }
            tage[heute] = nil
            if tage.count > 1, let alt = tage.keys.min() { tage[alt] = nil }
            return tage.filter { $0.value > 0 && $0.value < 200_000 }.map {
                DailyMetric(kind: .steps, date: $0.key, value: $0.value, sourceID: quellenID(quelle), sourceName: quellenName(quelle))
            }
        }
    }

    /// Schlafdauer und Schlafmitte je Morgen und Quelle. „Wach“ und „Im Bett“ zählen nicht.
    static func schlaf(_ z: [Zeile]) -> [DailyMetric] {
        let nicht = ["wach", "awake", "bett", "bed"]
        let gut = z.filter { r in
            guard let e = r.ende, e > r.start, e.timeIntervalSince(r.start) < 24 * 3600 else { return false }
            let a = r.art.lowercased(); return !nicht.contains { a.contains($0) }
        }
        return Dictionary(grouping: gut, by: \.quelle).flatMap { quelle, reihe -> [DailyMetric] in
            let iv = reihe.map { DateInterval(start: $0.start, end: $0.ende!) }
            var dauer = FitnessMath.sleepByMorning(iv)
            var mitte = FitnessMath.sleepMidpoints(iv)
            if dauer.count > 1, let alt = dauer.keys.min() { dauer[alt] = nil; mitte[alt] = nil }
            let id = quellenID(quelle), name = quellenName(quelle)
            return dauer.filter { $0.value > 0 }.map { DailyMetric(kind: .sleepHours, date: $0.key, value: $0.value / 3600, sourceID: id, sourceName: name) }
                + mitte.map { DailyMetric(kind: .sleepMidpoint, date: $0.key, value: $0.value, sourceID: id, sourceName: name) }
        }
    }

    static func uebernehmen(ruhepuls: String?, hrv: String?, schlaf schlafText: String?, schritte: String?) -> String {
        let library = Services.shared.library
        if library.preview { return "Pebble läuft im Vorschau-Modus, es wurde nichts übernommen." }
        let p = zeilen(ruhepuls, schlaf: false), h = zeilen(hrv, schlaf: false)
        let s = zeilen(schlafText, schlaf: true), st = zeilen(schritte, schlaf: false, ganz: true)
        let neu = mittel(p.ok, art: .restingPulse, bereich: 25...150) + mittel(h.ok, art: .hrvSDNN, bereich: 1...400)
            + schlaf(s.ok) + summe(st.ok)
        let fehler = p.fehler + h.fehler + s.fehler + st.fehler
        let beispiel = p.beispiel ?? h.beispiel ?? s.beispiel ?? st.beispiel
        guard !neu.isEmpty else {
            if fehler > 0 { return "Nichts übernommen: \(fehler) Zeilen nicht lesbar, z. B. „\(beispiel ?? "")“." }
            return "Nichts übernommen: Der Kurzbefehl hat keine Werte geschickt."
        }
        func schluessel(_ m: DailyMetric) -> String { "\(m.kind.rawValue)|\(m.sourceID)|\(m.date.timeIntervalSince1970)" }
        let ersetzt = Set(neu.map(schluessel))
        let ok = library.change { data in
            data.metrics.removeAll { ersetzt.contains(schluessel($0)) }
            data.metrics += neu
            data.healthReadAt = Date()
        }
        guard ok else { return "Konnte nicht speichern." }
        func tage(_ art: MetricKind) -> Int { Set(neu.filter { $0.kind == art }.map(\.date)).count }
        var teile: [String] = []
        if tage(.restingPulse) > 0 { teile.append("Ruhepuls \(tage(.restingPulse)) Tage") }
        if tage(.hrvSDNN) > 0 { teile.append("HRV \(tage(.hrvSDNN)) Tage") }
        if tage(.sleepHours) > 0 { teile.append("Schlaf \(tage(.sleepHours)) Nächte") }
        if tage(.steps) > 0 { teile.append("Schritte \(tage(.steps)) Tage") }
        var satz = "Übernommen: " + teile.joined(separator: ", ") + "."
        if fehler > 0 { satz += " \(fehler) Zeilen nicht lesbar, z. B. „\(beispiel ?? "")“." }
        return satz
    }
}

struct HealthDatenUebernehmenIntent: AppIntent {
    static var title: LocalizedStringResource = "Health-Daten übernehmen"
    static var description = IntentDescription("Übernimmt Ruhepuls, HRV, Schlaf und Schritte, die der Kurzbefehl aus Apple Health gelesen hat. Je Zeile „Datum;Wert;Quelle“, beim Schlaf „Beginn;Ende;Art;Quelle“.")
    static var openAppWhenRun = false

    @Parameter(title: "Ruhepuls") var ruhepuls: String?
    @Parameter(title: "HRV") var hrv: String?
    @Parameter(title: "Schlaf") var schlaf: String?
    @Parameter(title: "Schritte") var schritte: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Health-Daten übernehmen") { \.$ruhepuls; \.$hrv; \.$schlaf; \.$schritte }
    }

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let satz = KurzbefehlHealth.uebernehmen(ruhepuls: ruhepuls, hrv: hrv, schlaf: schlaf, schritte: schritte)
        return .result(dialog: IntentDialog(stringLiteral: satz))
    }
}
// Ende Version 1
