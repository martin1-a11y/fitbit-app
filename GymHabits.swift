// Version 5 · Gym-Tab und Habit-Tracker: Zusatz zu Pebble (github.com/medpar/pebble, Stand ac1b90f)
// Bauplan: siehe Repo „Projekte“ (privat), fitbit/archiv/GYM-HABITS.md. Braucht das Armband nicht – nur Oberfläche + Speicher auf dem iPhone.
// Eingehängt über zwei kleine Änderungen, die einbauen.sh macht:
//   PebbleApp.swift  → Tab „Gym“ (GymScreen) in RootView
//   TrendsScreen.swift → Chip „Habits“ (HabitTrackerView) in TrendTopic
// Eigener Speicher (UserDefaults „gymHabits.gym“ / „gymHabits.habits“), getrennt von Pebbles AppStore.

import SwiftUI

// MARK: - Speicher

struct GymUebung: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var gewicht: String
    /// Zeitpunkt des Abhakens. Kein Verlauf – der Haken verfällt nach ein paar Stunden von selbst,
    /// damit beim nächsten Training wieder alles offen ist.
    var erledigtAm: Date?

    static let hakenDauer: TimeInterval = 4 * 3600
    var erledigt: Bool {
        guard let erledigtAm else { return false }
        return Date().timeIntervalSince(erledigtAm) < Self.hakenDauer
    }
}

struct GymTag: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var uebungen: [GymUebung] = []
}

struct Habit: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var farbe: Int
    /// Erledigte Tage als „JJJJ-MM-TT“ (Ortszeit).
    var tage: Set<String> = []
}

final class GymHabitSpeicher: ObservableObject {
    static let shared = GymHabitSpeicher()

    @Published var tage: [GymTag] { didSet { Self.sichern(tage, "gymHabits.gym") } }
    @Published var habits: [Habit] { didSet { Self.sichern(habits, "gymHabits.habits") } }

    private init() {
        tage = Self.laden("gymHabits.gym") ?? []
        habits = Self.laden("gymHabits.habits") ?? []
    }

    private static func laden<T: Decodable>(_ schluessel: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: schluessel) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
    private static func sichern<T: Encodable>(_ wert: T, _ schluessel: String) {
        UserDefaults.standard.set(try? JSONEncoder().encode(wert), forKey: schluessel)
    }

    func tag(_ id: UUID, _ aendern: (inout GymTag) -> Void) {
        guard let i = tage.firstIndex(where: { $0.id == id }) else { return }
        aendern(&tage[i])
    }
    func habit(_ id: UUID, _ aendern: (inout Habit) -> Void) {
        guard let i = habits.firstIndex(where: { $0.id == id }) else { return }
        aendern(&habits[i])
    }
}

/// Feste Farbauswahl für Habits (hell / dunkel).
enum HabitFarbe {
    static let alle: [Color] = [
        Tone.moss,
        Color.adaptive(0x2F6FDB, 0x7FA9FF),
        Color.adaptive(0x7A4FD1, 0xB49BFF),
        Color.adaptive(0xC03A4F, 0xFF7586),
        Color.adaptive(0xD9661F, 0xFF9C5C),
        Color.adaptive(0xC99A00, 0xFFD24D),
        Color.adaptive(0x1F9BA6, 0x6FDCE6),
        Color.adaptive(0xC24F9B, 0xFF8FD2),
    ]
    static func farbe(_ i: Int) -> Color { alle[((i % alle.count) + alle.count) % alle.count] }
}

// MARK: - Gym-Tab

struct GymScreen: View {
    @ObservedObject private var s = GymHabitSpeicher.shared
    @State private var neuerTag = false
    @State private var name = ""

    var body: some View {
        NavigationStack {
            List {
                if s.tage.isEmpty {
                    ContentUnavailableView {
                        Label("Noch keine Workout-Tage", systemImage: "dumbbell")
                    } description: {
                        Text("Oben rechts mit + einen Tag anlegen, z. B. „Push“ oder „Beine“.")
                    }
                    .listRowBackground(Color.clear)
                } else {
                    Section {
                        ForEach(s.tage) { tag in
                            NavigationLink(value: tag.id) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tag.name).font(.headline).foregroundStyle(Tone.ink)
                                    Text(untertitel(tag)).font(.subheadline).foregroundStyle(Tone.ink2)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .onMove { s.tage.move(fromOffsets: $0, toOffset: $1) }
                        .onDelete { s.tage.remove(atOffsets: $0) }
                    } footer: {
                        Text("Halten und ziehen ändert die Reihenfolge, nach links wischen löscht.")
                            .font(.footnote).foregroundStyle(Tone.ink3).padding(.top, 6)
                    }
                    .listRowBackground(Tone.surface)
                }
            }
            .surfaceRows()
            .navigationTitle("Gym")
            .navigationDestination(for: UUID.self) { GymTagScreen(tagID: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Tag anlegen", systemImage: "plus") { name = ""; neuerTag = true }
                }
            }
            .alert("Neuer Workout-Tag", isPresented: $neuerTag) {
                TextField("z. B. Push", text: $name)
                Button("Abbrechen", role: .cancel) {}
                Button("Anlegen") {
                    let n = name.trimmingCharacters(in: .whitespaces)
                    if !n.isEmpty { s.tage.append(GymTag(name: n)) }
                }
            }
        }
    }

    private func untertitel(_ tag: GymTag) -> String {
        let anzahl = tag.uebungen.count
        if anzahl == 0 { return "Keine Übungen" }
        let fertig = tag.uebungen.filter(\.erledigt).count
        let text = anzahl == 1 ? "1 Übung" : "\(anzahl) Übungen"
        return fertig > 0 ? "\(text) · \(fertig) erledigt" : text
    }
}

private struct GymTagScreen: View {
    let tagID: UUID
    @ObservedObject private var s = GymHabitSpeicher.shared
    @State private var neu = false
    @State private var bearbeite: GymUebung?
    @State private var umbenennen = false
    @State private var liste = false
    @State private var name = ""

    var body: some View {
        let tag = s.tage.first { $0.id == tagID }
        List {
            if let tag {
                if tag.uebungen.isEmpty {
                    ContentUnavailableView {
                        Label("Noch keine Übungen", systemImage: "list.bullet")
                    } description: {
                        Text("Oben rechts mit + eine Übung anlegen oder über ⋯ eine ganze Liste einfügen.")
                    }
                    .listRowBackground(Color.clear)
                } else {
                    Section {
                        ForEach(tag.uebungen) { u in
                            UebungZeile(uebung: u) {
                                s.tag(tagID) { t in
                                    if let i = t.uebungen.firstIndex(where: { $0.id == u.id }) {
                                        t.uebungen[i].erledigtAm = u.erledigt ? nil : Date()
                                    }
                                }
                            } bearbeiten: { bearbeite = u }
                            .swipeActions(edge: .trailing) {
                                Button("Löschen", role: .destructive) {
                                    s.tag(tagID) { $0.uebungen.removeAll { $0.id == u.id } }
                                }
                                Button("Bearbeiten") { bearbeite = u }.tint(Tone.ink2)
                            }
                        }
                        .onMove { von, nach in s.tag(tagID) { $0.uebungen.move(fromOffsets: von, toOffset: nach) } }
                    }
                    .listRowBackground(Tone.surface)
                }
            }
        }
        .surfaceRows()
        .navigationTitle(tag?.name ?? "")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Liste einfügen", systemImage: "list.bullet.clipboard") { liste = true }
                    Button("Tag umbenennen", systemImage: "pencil") { name = tag?.name ?? ""; umbenennen = true }
                    Button("Alle Haken entfernen", systemImage: "arrow.counterclockwise") {
                        s.tag(tagID) { t in for i in t.uebungen.indices { t.uebungen[i].erledigtAm = nil } }
                    }
                } label: { Image(systemName: "ellipsis.circle") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Übung anlegen", systemImage: "plus") { neu = true }
            }
        }
        .sensoryFeedback(.selection, trigger: tag?.uebungen.filter(\.erledigt).count ?? 0)
        .sheet(isPresented: $neu) {
            UebungEditor(uebung: nil) { neueU in s.tag(tagID) { $0.uebungen.append(neueU) } }
        }
        .sheet(item: $bearbeite) { u in
            UebungEditor(uebung: u) { geaendert in
                s.tag(tagID) { t in
                    if let i = t.uebungen.firstIndex(where: { $0.id == geaendert.id }) { t.uebungen[i] = geaendert }
                }
            } loeschen: {
                s.tag(tagID) { $0.uebungen.removeAll { $0.id == u.id } }
            }
        }
        .sheet(isPresented: $liste) {
            UebungListeEinfuegen { neue in
                s.tag(tagID) { t in
                    for n in neue {
                        // Gleichnamige Übung: nur Gewicht übernehmen, nicht doppelt anlegen
                        if let i = t.uebungen.firstIndex(where: { $0.name.lowercased() == n.name.lowercased() }) {
                            if !n.gewicht.isEmpty { t.uebungen[i].gewicht = n.gewicht }
                        } else {
                            t.uebungen.append(n)
                        }
                    }
                }
            }
        }
        .alert("Tag umbenennen", isPresented: $umbenennen) {
            TextField("Name", text: $name)
            Button("Abbrechen", role: .cancel) {}
            Button("Sichern") {
                let n = name.trimmingCharacters(in: .whitespaces)
                if !n.isEmpty { s.tag(tagID) { $0.name = n } }
            }
        }
    }
}

private struct UebungZeile: View {
    let uebung: GymUebung
    let abhaken: () -> Void
    let bearbeiten: () -> Void
    var body: some View {
        let fertig = uebung.erledigt
        // Kompakt wie die Vorschau beim Einfügen: kein Kreis links, erledigt = grau + durchgestrichen
        HStack(spacing: 10) {
            Button(action: abhaken) {
                Text(uebung.name).font(.body)
                    .strikethrough(fertig, color: Tone.ink3)
                    .foregroundStyle(fertig ? Tone.ink3 : Tone.ink)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            Button(action: bearbeiten) {
                Text(uebung.gewicht.isEmpty ? "–" : uebung.gewicht)
                    .font(.figure(17)).monospacedDigit()
                    .foregroundStyle(fertig ? Tone.ink3 : Tone.ink)
                    .padding(.horizontal, 10).frame(minHeight: 28)
                    .background(Tone.sunken.opacity(fertig ? 0.5 : 1), in: Capsule())
            }
            .buttonStyle(PressStyle())
        }
        .animation(.easeOut(duration: 0.15), value: fertig)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(uebung.name), \(uebung.gewicht)\(fertig ? ", erledigt" : "")")
    }
}

/// Liste einfügen (z. B. von Claude): eine Übung je Zeile, am besten „Übung | Gewicht“.
/// Erkannt werden auch „Übung: 40 kg“, „Übung – 40 kg“, „Bankdrücken 3x10 40 kg“; Aufzählungszeichen und
/// Nummern vorne fallen weg, Zeilen mit Doppelpunkt am Ende gelten als Überschrift.
private struct UebungListeEinfuegen: View {
    let hinzufuegen: ([GymUebung]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        let erkannt = Self.lesen(text)
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 150)
                        .font(.body)
                        .autocorrectionDisabled()
                    PasteButton(payloadType: String.self) { teile in
                        if let t = teile.first { text = t }
                    }
                    .labelStyle(.titleAndIcon)
                } footer: {
                    Text("Eine Übung pro Zeile, z. B. „Bankdrücken | 40 kg“.")
                }
                if !erkannt.isEmpty {
                    Section("Erkannt: \(erkannt.count)") {
                        ForEach(erkannt) { u in
                            HStack {
                                Text(u.name).foregroundStyle(Tone.ink)
                                Spacer()
                                Text(u.gewicht.isEmpty ? "–" : u.gewicht).monospacedDigit().foregroundStyle(Tone.ink2)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Liste einfügen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hinzufügen") { hinzufuegen(erkannt); dismiss() }
                        .disabled(erkannt.isEmpty)
                }
            }
        }
        .presentationDetents([.large])
    }

    static func lesen(_ text: String) -> [GymUebung] {
        var ergebnis: [GymUebung] = []
        for roh in text.components(separatedBy: .newlines) {
            var zeile = roh.trimmingCharacters(in: .whitespaces)
            // Aufzählungszeichen, Nummern („1.“, „2)“), Kästchen und Markdown-Fett vorne weg
            zeile = zeile.replacingOccurrences(of: #"^(?:[-•*–·▪◦]|\d+[.)]|\[[ xX]?\])\s*"#, with: "", options: .regularExpression)
            zeile = zeile.replacingOccurrences(of: "**", with: "").trimmingCharacters(in: .whitespaces)
            if zeile.isEmpty || zeile.hasSuffix(":") { continue }
            var name = zeile
            var gewicht = ""
            if let strich = zeile.firstIndex(of: "|") {
                name = String(zeile[..<strich])
                gewicht = String(zeile[zeile.index(after: strich)...])
            } else if let kg = zeile.range(of: #"\d+(?:[.,]\d+)?\s*(?:kg|lbs?)\b"#, options: [.regularExpression, .caseInsensitive]) {
                gewicht = String(zeile[kg])
                name = zeile.replacingCharacters(in: kg, with: "")
            } else if let trenner = zeile.range(of: #"\s[–-]\s|:\s"#, options: .regularExpression) {
                name = String(zeile[..<trenner.lowerBound])
                gewicht = String(zeile[trenner.upperBound...])
            }
            let rand = CharacterSet.whitespaces.union(CharacterSet(charactersIn: "-–:,@|·"))
            name = name.trimmingCharacters(in: rand)
            gewicht = gewicht.trimmingCharacters(in: rand)
            if !name.isEmpty { ergebnis.append(GymUebung(name: name, gewicht: gewicht)) }
        }
        return ergebnis
    }
}

private struct UebungEditor: View {
    let uebung: GymUebung?
    let sichern: (GymUebung) -> Void
    var loeschen: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var gewicht = ""
    @FocusState private var fokus: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Übung, z. B. Bankdrücken", text: $name)
                    TextField("Gewicht, z. B. 40 kg", text: $gewicht)
                        .keyboardType(.numbersAndPunctuation)
                        .focused($fokus)
                }
                if let loeschen {
                    Section {
                        Button("Übung löschen", role: .destructive) { loeschen(); dismiss() }
                    }
                }
            }
            .navigationTitle(uebung == nil ? "Neue Übung" : "Übung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        var u = uebung ?? GymUebung(name: "", gewicht: "")
                        u.name = name.trimmingCharacters(in: .whitespaces)
                        u.gewicht = gewicht.trimmingCharacters(in: .whitespaces)
                        sichern(u)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                name = uebung?.name ?? ""
                gewicht = uebung?.gewicht ?? ""
                if uebung != nil { fokus = true }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Habit-Tracker (Chip „Habits“ unter Trends)

enum HabitDatum {
    static var kalender: Calendar { Calendar.current }
    static func schluessel(_ d: Date) -> String {
        let c = kalender.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
    static func plus(_ tage: Int, _ d: Date) -> Date { kalender.date(byAdding: .day, value: tage, to: d)! }
    /// Montag der Woche von d (0 Uhr).
    static func wochenAnfang(_ d: Date) -> Date {
        let heute = kalender.startOfDay(for: d)
        let wt = (kalender.component(.weekday, from: heute) + 5) % 7  // Mo = 0 … So = 6
        return plus(-wt, heute)
    }
    static func monatsAnfang(_ d: Date) -> Date {
        kalender.date(from: kalender.dateComponents([.year, .month], from: d))!
    }
    static func datum(_ schluessel: String) -> Date? {
        let t = schluessel.split(separator: "-").compactMap { Int($0) }
        guard t.count == 3 else { return nil }
        return kalender.date(from: DateComponents(year: t[0], month: t[1], day: t[2]))
    }
    /// Wie viele Wochen das Raster zeigt: mindestens ein Jahr, sonst bis zum ältesten Eintrag zurück.
    static func wochenAnzahl(_ h: Habit, bis letzteWoche: Date) -> Int {
        guard let aeltester = h.tage.min().flatMap(datum) else { return 53 }
        let tage = kalender.dateComponents([.day], from: wochenAnfang(aeltester), to: letzteWoche).day ?? 0
        return min(520, max(53, tage / 7 + 1))
    }
    static let monate = ["Jan", "Feb", "Mär", "Apr", "Mai", "Jun", "Jul", "Aug", "Sep", "Okt", "Nov", "Dez"]
    /// Monatsname über der Woche, in der ein Monat beginnt (sonst nil).
    static func monatsKopf(_ montag: Date) -> String? {
        let sonntag = plus(6, montag)
        guard kalender.component(.day, from: montag) == 1
                || kalender.component(.month, from: sonntag) != kalender.component(.month, from: montag) else { return nil }
        return monate[kalender.component(.month, from: sonntag) - 1]
    }
}

struct HabitTrackerView: View {
    @ObservedObject private var s = GymHabitSpeicher.shared
    @State private var neu = false
    @State private var offen: Habit?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if s.habits.isEmpty {
                Card {
                    Eyebrow("Habits")
                    Text("Noch keine Gewohnheiten. Lege eine an – dann je Tag ein Kästchen antippen, wenn erledigt.")
                        .font(.subheadline).foregroundStyle(Tone.ink2).padding(.top, 8)
                }
            }
            ForEach(s.habits) { h in
                HabitKarte(habit: h) { s.umschalten(h.id, $0) } oeffnen: { offen = h }
            }
            // Nur ein „+“ ohne Text (Wunsch des Nutzers)
            Button { neu = true } label: {
                Image(systemName: "plus").font(.title3.weight(.semibold)).foregroundStyle(Tone.ink)
                    .frame(width: 48, height: 48).background(Tone.surface, in: Circle())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Gewohnheit hinzufügen")
            .padding(.top, 4)
        }
        .sheet(isPresented: $neu) {
            HabitEditor(habit: nil, vorschlagFarbe: s.habits.count) { s.habits.append($0) }
        }
        .sheet(item: $offen) { h in HabitDetail(id: h.id) }
    }
}

extension GymHabitSpeicher {
    func umschalten(_ id: UUID, _ schluessel: String) {
        habit(id) { if $0.tage.contains(schluessel) { $0.tage.remove(schluessel) } else { $0.tage.insert(schluessel) } }
    }
}

private struct HabitKarte: View {
    let habit: Habit
    let umschalten: (String) -> Void
    let oeffnen: () -> Void

    var body: some View {
        let farbe = HabitFarbe.farbe(habit.farbe)
        let heute = HabitDatum.schluessel(Date())
        let heuteFertig = habit.tage.contains(heute)
        Card {
            HStack(spacing: 10) {
                // Antippen = Monatsübersicht (dort auch Bearbeiten)
                Button(action: oeffnen) {
                    HStack(spacing: 6) {
                        Text(habit.name).font(.headline).foregroundStyle(Tone.ink)
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Tone.ink3)
                    }
                    .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                Button { umschalten(heute) } label: {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.bold))
                        .foregroundStyle(heuteFertig ? Tone.surface : farbe)
                        .frame(width: 40, height: 40)
                        .background(heuteFertig ? farbe : farbe.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel(heuteFertig ? "Heute erledigt" : "Heute abhaken")
            }
            HabitRaster(habit: habit, farbe: farbe, umschalten: umschalten).padding(.top, 10)
        }
        .sensoryFeedback(.selection, trigger: habit.tage.count)
    }
}

/// Kästchen-Raster wie bei HabitKit: Spalten = Wochen (rechts die aktuelle), Zeilen = Mo … So,
/// oben der Monatsname. Nach rechts wischen = ältere Wochen.
private struct HabitRaster: View {
    let habit: Habit
    let farbe: Color
    let umschalten: (String) -> Void

    private let zelle: CGFloat = 18
    private let luecke: CGFloat = 4
    private let kopf: CGFloat = 14

    var body: some View {
        let heute = HabitDatum.kalender.startOfDay(for: Date())
        let letzteWoche = HabitDatum.wochenAnfang(heute)
        let anzahl = HabitDatum.wochenAnzahl(habit, bis: letzteWoche)
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: luecke) {
                ForEach(0..<anzahl, id: \.self) { sp in
                    let woche = HabitDatum.plus(-(anzahl - 1 - sp) * 7, letzteWoche)
                    VStack(spacing: luecke) {
                        Text(HabitDatum.monatsKopf(woche) ?? "")
                            .font(.caption2.weight(.medium)).foregroundStyle(Tone.ink3)
                            .fixedSize()
                            // letzte Spalte: Name nach links, sonst würde er am Rand abgeschnitten
                            .frame(width: zelle, height: kopf, alignment: sp == anzahl - 1 ? .trailing : .leading)
                        ForEach(0..<7, id: \.self) { z in
                            let tag = HabitDatum.plus(z, woche)
                            let k = HabitDatum.schluessel(tag)
                            if tag > heute {
                                Color.clear.frame(width: zelle, height: zelle)
                            } else {
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(habit.tage.contains(k) ? farbe : Tone.sunken)
                                    .overlay {
                                        if tag == heute {
                                            RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(farbe, lineWidth: 1.5)
                                        }
                                    }
                                    .frame(width: zelle, height: zelle)
                                    .contentShape(Rectangle())
                                    .onTapGesture { umschalten(k) }
                            }
                        }
                    }
                }
            }
        }
        .defaultScrollAnchor(.trailing)
        .frame(height: kopf + 7 * (zelle + luecke))
        .accessibilityHidden(true)
    }
}

/// Seite einer Gewohnheit: Raster + Monatsübersicht, Stift oben = Bearbeiten.
private struct HabitDetail: View {
    let id: UUID
    @ObservedObject private var s = GymHabitSpeicher.shared
    @Environment(\.dismiss) private var dismiss
    @State private var bearbeiten = false
    @State private var monat = HabitDatum.monatsAnfang(Date())

    var body: some View {
        let h = s.habits.first { $0.id == id }
        NavigationStack {
            ScrollView {
                if let h {
                    let farbe = HabitFarbe.farbe(h.farbe)
                    VStack(alignment: .leading, spacing: 12) {
                        Card { HabitRaster(habit: h, farbe: farbe) { s.umschalten(id, $0) } }
                        Card { MonatsKalender(habit: h, farbe: farbe, monat: $monat) { s.umschalten(id, $0) } }
                    }
                    .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 28)
                }
            }
            .screenBackground()
            .navigationTitle(h?.name ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Bearbeiten", systemImage: "pencil") { bearbeiten = true }
                }
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
            }
            .sheet(isPresented: $bearbeiten) {
                if let h {
                    HabitEditor(habit: h, vorschlagFarbe: h.farbe) { geaendert in
                        s.habit(geaendert.id) { $0 = geaendert }
                    } loeschen: {
                        s.habits.removeAll { $0.id == id }
                    } verschieben: { richtung in
                        guard let i = s.habits.firstIndex(where: { $0.id == id }) else { return }
                        let j = i + richtung
                        if s.habits.indices.contains(j) { s.habits.swapAt(i, j) }
                    }
                }
            }
            .onChange(of: h == nil) { _, weg in if weg { dismiss() } }
        }
        .sensoryFeedback(.selection, trigger: h?.tage.count ?? 0)
    }
}

/// Monatsübersicht: Mo–So, erledigte Tage farbig hinterlegt mit Punkt, antippen = umschalten.
private struct MonatsKalender: View {
    let habit: Habit
    let farbe: Color
    @Binding var monat: Date
    let umschalten: (String) -> Void

    var body: some View {
        let k = HabitDatum.kalender
        let heute = k.startOfDay(for: Date())
        let dieserMonat = HabitDatum.monatsAnfang(heute)
        let start = HabitDatum.wochenAnfang(monat)
        let tageImMonat = k.range(of: .day, in: .month, for: monat)?.count ?? 30
        let ende = HabitDatum.plus(tageImMonat - 1, monat)
        let wochen = (k.dateComponents([.day], from: start, to: HabitDatum.wochenAnfang(ende)).day ?? 28) / 7 + 1
        let anzahl = (0..<tageImMonat).filter { habit.tage.contains(HabitDatum.schluessel(HabitDatum.plus($0, monat))) }.count
        let spalten = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(monat, format: .dateTime.month(.wide).year().locale(Locale(identifier: "de_DE")))
                        .font(.headline).foregroundStyle(Tone.ink)
                    Text(anzahl == 1 ? "1 Tag" : "\(anzahl) Tage").font(.caption).foregroundStyle(Tone.ink2)
                }
                Spacer()
                if monat != dieserMonat {
                    Button("Heute") { blaettern(zu: dieserMonat) }
                        .font(.subheadline.weight(.medium)).foregroundStyle(Tone.ink)
                        .padding(.horizontal, 12).frame(height: 34)
                        .background(Tone.sunken, in: Capsule())
                        .buttonStyle(PressStyle())
                }
                rund("chevron.left") { blaettern(um: -1) }
                rund("chevron.right") { blaettern(um: 1) }.disabled(monat >= dieserMonat).opacity(monat >= dieserMonat ? 0.35 : 1)
            }
            LazyVGrid(columns: spalten, spacing: 6) {
                ForEach(["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"], id: \.self) { t in
                    Text(t).font(.caption.weight(.medium)).foregroundStyle(Tone.ink3)
                }
                ForEach(0..<(wochen * 7), id: \.self) { i in
                    let tag = HabitDatum.plus(i, start)
                    let schluessel = HabitDatum.schluessel(tag)
                    let fertig = habit.tage.contains(schluessel)
                    let imMonat = k.isDate(tag, equalTo: monat, toGranularity: .month)
                    VStack(spacing: 3) {
                        Text("\(k.component(.day, from: tag))")
                            .font(.figure(15)).monospacedDigit()
                            .foregroundStyle(fertig ? Tone.ink : Tone.ink2)
                        Circle().fill(fertig ? farbe : .clear).frame(width: 4, height: 4)
                    }
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .background(fertig ? farbe.opacity(0.22) : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        if tag == heute { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(farbe, lineWidth: 1.5) }
                    }
                    .opacity(tag > heute ? 0.3 : imMonat ? 1 : 0.4)
                    .contentShape(Rectangle())
                    .onTapGesture { if tag <= heute { umschalten(schluessel) } }
                }
            }
        }
        .contentShape(Rectangle())
        // Links/rechts wischen = anderer Monat
        .gesture(DragGesture(minimumDistance: 30).onEnded { g in
            guard abs(g.translation.width) > abs(g.translation.height) * 1.5 else { return }
            if g.translation.width < 0 { if monat < dieserMonat { blaettern(um: 1) } } else { blaettern(um: -1) }
        })
        .sensoryFeedback(.selection, trigger: monat)
    }

    private func rund(_ symbol: String, _ aktion: @escaping () -> Void) -> some View {
        Button(action: aktion) {
            Image(systemName: symbol).font(.subheadline.weight(.semibold)).foregroundStyle(Tone.ink)
                .frame(width: 34, height: 34).background(Tone.sunken, in: Circle())
        }
        .buttonStyle(PressStyle())
    }
    private func blaettern(um n: Int) {
        if let neu = HabitDatum.kalender.date(byAdding: .month, value: n, to: monat) { blaettern(zu: neu) }
    }
    private func blaettern(zu neu: Date) {
        withAnimation(.snappy(duration: 0.25)) { monat = HabitDatum.monatsAnfang(neu) }
    }
}

private struct HabitEditor: View {
    let habit: Habit?
    let vorschlagFarbe: Int
    let sichern: (Habit) -> Void
    var loeschen: (() -> Void)? = nil
    var verschieben: ((Int) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var farbe = 0
    @State private var fragLoeschen = false

    var body: some View {
        NavigationStack {
            Form {
                Section { TextField("Name, z. B. Lesen", text: $name) }
                Section("Farbe") {
                    HStack(spacing: 10) {
                        ForEach(HabitFarbe.alle.indices, id: \.self) { i in
                            Circle().fill(HabitFarbe.alle[i])
                                .frame(width: 30, height: 30)
                                .overlay { if farbe == i { Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(Tone.surface) } }
                                .onTapGesture { farbe = i }
                                .accessibilityAddTraits(farbe == i ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                }
                if let verschieben {
                    Section {
                        Button("Nach oben", systemImage: "arrow.up") { verschieben(-1) }
                        Button("Nach unten", systemImage: "arrow.down") { verschieben(1) }
                    }
                }
                if loeschen != nil {
                    Section { Button("Gewohnheit löschen", role: .destructive) { fragLoeschen = true } }
                }
            }
            .navigationTitle(habit == nil ? "Neue Gewohnheit" : "Gewohnheit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        var h = habit ?? Habit(name: "", farbe: 0)
                        h.name = name.trimmingCharacters(in: .whitespaces)
                        h.farbe = farbe
                        sichern(h)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("Gewohnheit samt allen Kästchen löschen?", isPresented: $fragLoeschen, titleVisibility: .visible) {
                Button("Löschen", role: .destructive) { loeschen?(); dismiss() }
            }
            .onAppear {
                name = habit?.name ?? ""
                farbe = habit?.farbe ?? (vorschlagFarbe % HabitFarbe.alle.count)
            }
        }
        .presentationDetents([.medium, .large])
    }
}
// Ende Version 5
