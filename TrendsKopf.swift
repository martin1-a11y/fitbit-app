// Version 3 · Zusatz zu Pebble: einbauen.sh setzt diesen Block in App/UI/TrendsScreen.swift ein und ersetzt
// dort TrendTopic, TrendsScreen und TopicBar (alles vor MetricTrendView). Wird NICHT als eigene Datei mitgebaut.
// - Chip „Habits“ (HabitTrackerView aus GymHabits.swift)
// - Reihenfolge der Chips: Chip halten, dann nach links/rechts ziehen (gemerkt in „fitbitTimer.trendReihenfolge“)
// - Links/rechts wischen = voriger/nächster Trend (TabView als Seiten)
import UniformTypeIdentifiers

private enum TrendTopic: Hashable, CaseIterable, Identifiable {
    case metric(MetricKind), training, habits
    static var allCases: [TrendTopic] { [.metric(.steps), .metric(.sleepHours), .metric(.restingPulse), .metric(.hrvSDNN), .metric(.sleepMidpoint), .training, .habits] }
    var id: String { title }
    var title: String {
        switch self {
        case .metric(let kind): return kind.short
        case .training: return "Training"
        case .habits: return "Habits"
        }
    }

    /// Gemerkte Reihenfolge (Titel mit „|“ getrennt). Unbekanntes fliegt raus, Fehlendes kommt hinten dran.
    static func reihenfolge(_ text: String) -> [TrendTopic] {
        var liste: [TrendTopic] = []
        for teil in text.split(separator: "|") {
            if let t = allCases.first(where: { $0.id == teil }), !liste.contains(t) { liste.append(t) }
        }
        for t in allCases where !liste.contains(t) { liste.append(t) }
        return liste
    }
}

struct TrendsScreen: View {
    @EnvironmentObject private var library: AppStore
    @AppStorage("fitbitTimer.trendReihenfolge") private var gemerkt = ""
    @State private var topic = TrendTopic.metric(.steps)
    @State private var gestartet = false
    @State private var weeks = 4
    @State private var methods = false
    // Ziehen der Chips: Reihenfolge während des Ziehens, gezogener Chip, Lage der Chips (ohne Neuzeichnen gemerkt)
    @State private var reihe: [TrendTopic] = []
    @State private var gezogen: TrendTopic?
    @State private var verschoben = 0
    @State private var rahmen = ChipRahmen()

    var body: some View {
        let liste = TrendTopic.reihenfolge(gemerkt)
        NavigationStack {
            VStack(spacing: 0) {
                TopicBar(topic: $topic, reihe: $reihe, gezogen: $gezogen, rahmen: rahmen)
                .padding(.horizontal, 16).padding(.bottom, 6)
                TabView(selection: $topic) {
                    ForEach(liste) { item in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                seite(item)
                                if item != .habits {  // bei Habits gibt es nichts zu berechnen
                                    Button { methods = true } label: {
                                        Label("How these are calculated", systemImage: "book.closed").font(.footnote.weight(.medium)).foregroundStyle(Tone.ink2)
                                    }.buttonStyle(PressStyle()).padding(.horizontal, 4).padding(.top, 4)
                                }
                            }
                            .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 28)
                        }
                        .tag(item)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .screenBackground()
            .navigationTitle("Trends")
            .sheet(isPresented: $methods) { NavigationStack { MethodsScreen() } }
            .onAppear {
                // Beim ersten Öffnen mit dem Trend ganz links anfangen
                if !gestartet { gestartet = true; topic = liste.first ?? topic }
                if reihe.isEmpty { reihe = liste }
            }
            .onChange(of: liste) { _, neu in if neu != reihe { reihe = neu } }
        }
        // Ablage auf dem ganzen Bildschirm: der Finger darf beim Ziehen die Chip-Zeile verlassen,
        // zählt nur, wie weit links/rechts er ist.
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { rahmen.flaeche = $0 }
        .onDrop(of: [UTType.text], delegate: ChipAblage(reihe: $reihe, gezogen: $gezogen, rahmen: rahmen) { neu in
            verschoben += 1
            gemerkt = neu.map(\.id).joined(separator: "|")
        })
        .sensoryFeedback(.impact(weight: .light), trigger: verschoben)
    }

    @ViewBuilder private func seite(_ item: TrendTopic) -> some View {
        switch item {
        case .metric(let kind): MetricTrendView(kind: kind, weeks: $weeks)
        case .training: TrainingTrendView()
        case .habits: HabitTrackerView()
        }
    }
}

/// Lage der Chips auf dem Bildschirm. Klasse, damit Scrollen der Chip-Zeile nichts neu zeichnet.
private final class ChipRahmen {
    var chips: [TrendTopic: CGRect] = [:]
    var flaeche: CGRect = .zero
}

private struct TopicBar: View {
    @Binding var topic: TrendTopic
    @Binding var reihe: [TrendTopic]
    @Binding var gezogen: TrendTopic?
    let rahmen: ChipRahmen
    @Namespace private var selection

    var body: some View {
        ScrollViewReader { leser in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(reihe) { item in
                        Button { withAnimation(.snappy(duration: 0.25)) { topic = item } } label: { chip(item, gewaehlt: topic == item, mitAnimation: true) }
                            .buttonStyle(PressStyle())
                            .contentShape(.dragPreview, Capsule())
                            .accessibilityAddTraits(topic == item ? .isSelected : [])
                            .id(item)
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { rahmen.chips[item] = $0 }
                            .onDrag {
                                gezogen = item
                                return NSItemProvider(object: item.id as NSString)
                            } preview: {
                                chip(item, gewaehlt: topic == item, mitAnimation: false)
                            }
                    }
                }
            }
            .onChange(of: topic) { _, neu in
                withAnimation(.snappy(duration: 0.25)) { leser.scrollTo(neu, anchor: .center) }
            }
        }
        .sensoryFeedback(.selection, trigger: topic)
    }

    private func chip(_ item: TrendTopic, gewaehlt: Bool, mitAnimation: Bool) -> some View {
        Text(item.title).font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14).frame(height: 34)
            .foregroundStyle(gewaehlt ? Tone.onMoss : Tone.ink)
            .background {
                if gewaehlt {
                    if mitAnimation { Capsule().fill(Tone.moss).matchedGeometryEffect(id: "chip", in: selection) }
                    else { Capsule().fill(Tone.moss) }
                } else { Capsule().fill(Tone.surface) }
            }
    }
}

/// Schiebt den gezogenen Chip an die Stelle des Chips, über dem der Finger waagrecht steht (sofort, nicht erst
/// beim Loslassen). Die Höhe des Fingers ist egal; links/rechts neben allen Chips = ganz an den Anfang/ans Ende.
private struct ChipAblage: DropDelegate {
    @Binding var reihe: [TrendTopic]
    @Binding var gezogen: TrendTopic?
    let rahmen: ChipRahmen
    let geaendert: ([TrendTopic]) -> Void

    func validateDrop(info: DropInfo) -> Bool { gezogen != nil }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        schieben(x: rahmen.flaeche.minX + info.location.x)
        return DropProposal(operation: .move)
    }
    func dropEntered(info: DropInfo) { schieben(x: rahmen.flaeche.minX + info.location.x) }
    func performDrop(info: DropInfo) -> Bool { gezogen = nil; return true }

    private func schieben(x: CGFloat) {
        guard let g = gezogen, let von = reihe.firstIndex(of: g) else { return }
        let lagen = reihe.compactMap { t in rahmen.chips[t].map { (t, $0) } }
        guard let erster = lagen.first, let letzter = lagen.last else { return }
        let ziel: TrendTopic?
        if let treffer = lagen.first(where: { $0.1.minX <= x && x <= $0.1.maxX }) { ziel = treffer.0 }
        else if x < erster.1.minX { ziel = erster.0 }
        else if x > letzter.1.maxX { ziel = letzter.0 }
        else { ziel = nil }  // Lücke zwischen zwei Chips: nichts tun (sonst Zappeln)
        guard let ziel, ziel != g, let nach = reihe.firstIndex(of: ziel) else { return }
        var neu = reihe
        neu.move(fromOffsets: IndexSet(integer: von), toOffset: nach > von ? nach + 1 : nach)
        withAnimation(.snappy(duration: 0.25)) { reihe = neu }
        geaendert(neu)
    }
}

// Ende Version 3 (TrendsKopf)

