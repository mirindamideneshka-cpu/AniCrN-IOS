import SwiftUI

enum AniStyle {
    static let background = Color(red: 16/255, green: 10/255, blue: 24/255)
    static let surface = Color(red: 27/255, green: 16/255, blue: 40/255)
    static let accent = Color(red: 244/255, green: 114/255, blue: 182/255)
}

struct LibraryHome: View {
    @State private var source: AnimeSource = .aniliberty
    @State private var query = ""
    @State private var titles: [Anime] = []
    @State private var loading = false
    @State private var error: String?
    @State private var page = 1
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(query.isEmpty ? "Найди свою историю" : "Результаты поиска").font(.title2.bold())
                            Text("Аниме · серии · любимые озвучки").font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    HStack {
                        Text(query.isEmpty ? "Каталог" : "Найдено: \(titles.count)").font(.headline)
                        Spacer()
                        Picker("Источник", selection: $source) {
                            ForEach(AnimeSource.allCases) { Text($0.title).tag($0) }
                        }.tint(AniStyle.accent)
                    }
                    if loading && titles.isEmpty { ProgressView().frame(maxWidth: .infinity).padding(40) }
                    if let error { Label(error, systemImage: "wifi.exclamationmark").font(.subheadline).foregroundStyle(.secondary).padding().frame(maxWidth: .infinity).background(AniStyle.surface, in: RoundedRectangle(cornerRadius: 16)) }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 16)], alignment: .leading, spacing: 24) {
                        ForEach(titles) { anime in
                            NavigationLink { TitlePage(anime: anime, source: source) } label: { PosterCard(anime: anime) }.buttonStyle(.plain)
                        }
                    }
                    if !loading && titles.isEmpty && error == nil { Text("Пока ничего не найдено. Попробуй другое название или источник.").foregroundStyle(.secondary).padding(.vertical, 32) }
                    if query.isEmpty && !titles.isEmpty {
                        HStack {
                            Button("Назад") { page = max(1, page - 1) }.disabled(page == 1 || loading)
                            Spacer(); Text("\(page)").foregroundStyle(.secondary); Spacer()
                            Button("Далее") { page += 1 }.disabled(loading)
                        }.buttonStyle(.bordered).tint(AniStyle.accent)
                    }
                    if loading && !titles.isEmpty { ProgressView().frame(maxWidth: .infinity) }
                }.padding(20)
            }
            .background(AniStyle.background)
            .navigationTitle("AniCrN")
            .searchable(text: $query, prompt: "Название аниме")
            .toolbar { NavigationLink { SourcesView() } label: { Image(systemName: "slider.horizontal.3") }.accessibilityLabel("Источники") }
            .onChange(of: source) { _ in page = 1; titles = [] }
            .onChange(of: query) { _ in page = 1 }
            .task(id: "\(source.rawValue):\(query):\(page)") { await load() }
        }.tint(AniStyle.accent)
    }
    @MainActor private func load() async {
        loading = true; error = nil
        do {
            try await Task.sleep(nanoseconds: 350_000_000)
            let result = try await HomeCatalog.load(source: source, query: query, page: page)
            try Task.checkCancellation(); titles = result; loading = false
        } catch { if !Task.isCancelled { self.error = error.localizedDescription; loading = false } }
    }
}

struct PosterCard: View {
    let anime: Anime
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            AsyncImage(url: URL(string: anime.poster)) { image in image.resizable().scaledToFill() } placeholder: {
                ZStack { AniStyle.surface; Image(systemName: "play.rectangle").font(.largeTitle).foregroundStyle(AniStyle.accent.opacity(0.5)) }
            }.frame(height: 218).frame(maxWidth: .infinity).clipped().clipShape(RoundedRectangle(cornerRadius: 16))
            Text(anime.title).font(.subheadline.weight(.semibold)).lineLimit(2).frame(height: 40, alignment: .topLeading)
        }.contentShape(Rectangle())
    }
}

struct TitlePage: View {
    let anime: Anime
    let source: AnimeSource
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top, spacing: 20) {
                    AsyncImage(url: URL(string: anime.poster)) { $0.resizable().scaledToFill() } placeholder: { AniStyle.surface }
                        .frame(width: 130, height: 190).clipped().clipShape(RoundedRectangle(cornerRadius: 16))
                    VStack(alignment: .leading, spacing: 12) {
                        Text(source.title).font(.caption.weight(.semibold)).foregroundStyle(AniStyle.accent)
                        Text(anime.title).font(.title2.bold())
                        Text("Аниме").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                NavigationLink { episodes } label: {
                    Label(source == .shikimori ? "Найти озвучку" : "Смотреть", systemImage: "play.fill").font(.headline).frame(maxWidth: .infinity).padding(16)
                }.buttonStyle(.plain).background(AniStyle.accent, in: RoundedRectangle(cornerRadius: 14)).foregroundStyle(.black)
                if !anime.description.isEmpty { Text("О тайтле").font(.title3.bold()); Text(anime.description).font(.body).foregroundStyle(.secondary) }
            }.padding(20)
        }.background(AniStyle.background).navigationBarTitleDisplayMode(.inline)
    }
    @ViewBuilder private var episodes: some View {
        switch source {
        case .aniliberty: DetailView(anime: anime)
        case .animelib: AnimeLibEpisodesView(anime: anime)
        case .yummyanime: YummyEpisodesView(anime: anime)
        case .animego: if let url = URL(string: anime.id) { AnimeGoEpisodesView(url: url) }
        case .animefox, .animevost: if let url = URL(string: anime.id) { EmbeddedReleaseView(source: source, page: url) }
        case .shikimori: HTMLCatalogView(source: .animego, initialQuery: anime.title)
        }
    }
}
