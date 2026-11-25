// Version 1 · Zusatz zu Pebble: einbauen.sh setzt diesen Block in App/UI/TrendsScreen.swift ein und ersetzt
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

    var body: some View {
        let liste = TrendTopic.reihenfolge(gemerkt)
        NavigationStack {
            VStack(spacing: 0) {
                TopicBar(topic: $topic, liste: liste) { neu in
                    gemerkt = neu.map(\.id).joined(separator: "|")
                }
                .padding(.horizontal, 16).padding(.bottom, 6)
                TabView(selection: $topic) {
                    ForEach(liste) { item in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                seite(item)
                                Button { methods = true } label: {
                                    Label("How these are calculated", systemImage: "book.closed").font(.footnote.weight(.medium)).foregroundStyle(Tone.ink2)
                                }.buttonStyle(PressStyle()).padding(.horizontal, 4).padding(.top, 4)
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
            }
        }
    }

    @ViewBuilder private func seite(_ item: TrendTopic) -> some View {
        switch item {
        case .metric(let kind): MetricTrendView(kind: kind, weeks: $weeks)
        case .training: TrainingTrendView()
        case .habits: HabitTrackerView()
        }
    }
}

private struct TopicBar: View {
    @Binding var topic: TrendTopic
    let liste: [TrendTopic]
    let geaendert: ([TrendTopic]) -> Void
    @State private var reihe: [TrendTopic] = []
    @State private var gezogen: TrendTopic?
    @State private var verschoben = 0
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
                            .onDrag {
                                gezogen = item
                                return NSItemProvider(object: item.id as NSString)
                            } preview: {
                                chip(item, gewaehlt: topic == item, mitAnimation: false)
                            }
                            .onDrop(of: [UTType.text], delegate: ChipAblage(ziel: item, reihe: $reihe, gezogen: $gezogen) { neu in
                                verschoben += 1
                                geaendert(neu)
                            })
                    }
                }
            }
            .onChange(of: topic) { _, neu in
                withAnimation(.snappy(duration: 0.25)) { leser.scrollTo(neu, anchor: .center) }
            }
        }
        .onAppear { reihe = liste }
        .onChange(of: liste) { _, neu in if neu != reihe { reihe = neu } }
        .sensoryFeedback(.selection, trigger: topic)
        .sensoryFeedback(.impact(weight: .light), trigger: verschoben)
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

/// Schiebt den gezogenen Chip an die Stelle des Chips unter dem Finger (sofort, nicht erst beim Loslassen).
private struct ChipAblage: DropDelegate {
    let ziel: TrendTopic
    @Binding var reihe: [TrendTopic]
    @Binding var gezogen: TrendTopic?
    let geaendert: ([TrendTopic]) -> Void

    func dropEntered(info: DropInfo) {
        guard let g = gezogen, g != ziel,
              let von = reihe.firstIndex(of: g), let nach = reihe.firstIndex(of: ziel) else { return }
        var neu = reihe
        neu.move(fromOffsets: IndexSet(integer: von), toOffset: nach > von ? nach + 1 : nach)
        withAnimation(.snappy(duration: 0.25)) { reihe = neu }
        geaendert(neu)
    }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool { gezogen = nil; return true }
}

// Ende Version 1 (TrendsKopf)

