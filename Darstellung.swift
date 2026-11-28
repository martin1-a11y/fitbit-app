// Version 1 · Einstellung „Darstellung“ (System / Hell / Dunkel): Zusatz zu Pebble (Stand ac1b90f)
// Eingehängt über einbauen.sh:
//   PebbleApp.swift → .modifier(DarstellungAnwenden()) an RootView
//   BandScreen.swift → DarstellungAuswahl() über „Methods & sources“
// Pebbles Farben (Tone) sind schon hell/dunkel-fähig, hier wird nur das Schema erzwungen.

import SwiftUI

enum Darstellung: String, CaseIterable, Identifiable {
    case system, hell, dunkel
    var id: String { rawValue }
    var name: String {
        switch self {
        case .system: "System"
        case .hell: "Hell"
        case .dunkel: "Dunkel"
        }
    }
    var schema: ColorScheme? {
        switch self {
        case .system: nil
        case .hell: .light
        case .dunkel: .dark
        }
    }
    static let schluessel = "fitbitTimer.darstellung"
}

struct DarstellungAnwenden: ViewModifier {
    @AppStorage(Darstellung.schluessel) private var wahl = Darstellung.system.rawValue
    func body(content: Content) -> some View {
        content.preferredColorScheme((Darstellung(rawValue: wahl) ?? .system).schema)
    }
}

struct DarstellungAuswahl: View {
    @AppStorage(Darstellung.schluessel) private var wahl = Darstellung.system.rawValue
    var body: some View {
        Picker("Darstellung", selection: $wahl) {
            ForEach(Darstellung.allCases) { Text($0.name).tag($0.rawValue) }
        }
    }
}
// Ende Version 1
