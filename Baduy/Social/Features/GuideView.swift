import Combine
import SwiftUI

@MainActor final class GuideState: ObservableObject {
    @Published var guides: [Guide] = []
    @Published var loading = false
    @Published var error: String?
    let repository: any ContentRepository
    init(repository: any ContentRepository) { self.repository = repository }
    func load() async {
        loading = true; error = nil; defer { loading = false }
        do {
            guides = try await repository.guides()
            // This project uses -Onone for development and -O for release.
            if _isDebugAssertConfiguration() && guides.isEmpty { guides = Guide.samples }
        }
        catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
}
struct GuideListView: View {
    let repository: SupabaseRepository
    @StateObject private var state: GuideState
    @ViewState private var search = ""
    init(repository: SupabaseRepository) {
        self.repository = repository; _state = StateObject(wrappedValue: GuideState(repository: repository))
    }
    private var filtered: [Guide] {
        state.guides.filter { search.isEmpty || ([$0.name, $0.description] + $0.languages + $0.covered_areas).joined(separator: " ").localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        NavigationStack {
            Group {
                if state.loading && state.guides.isEmpty { ProgressView("Finding guides…") }
                else if let error = state.error {
                    ContentUnavailableView { Label("Couldn’t load guides", systemImage: "wifi.exclamationmark") }
                    description: { Text(error) } actions: { Button("Retry") { Task { await state.load() } } }
                } else if filtered.isEmpty {
                    ContentUnavailableView(search.isEmpty ? "No guides listed yet" : "No matching guides", systemImage: "person.text.rectangle", description: Text("Locally reviewed guide profiles will appear here when available."))
                } else {
                    List {
                        if state.guides.contains(where: { $0.isSample }) {
                            Label("Sample guides for preview — profiles and prices are fictional.", systemImage: "info.circle")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(filtered) { guide in
                        NavigationLink {
                            GuideDetailView(guide: guide, api: repository.api)
                        } label: {
                            HStack(spacing: 12) {
                                GuideImage(path: guide.profile_image_path, api: repository.api).frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 12))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(guide.name).font(.headline)
                                    Text(guide.description).lineLimit(2).foregroundStyle(.secondary)
                                    Text(guide.languages.joined(separator: ", ")).font(.caption)
                                }
                            }.padding(.vertical, 4)
                        }
                    }
                    }.refreshable { await state.load() }
                }
            }.navigationTitle("Local guides").searchable(text: $search, prompt: "Name, language, or area")
            .task { if state.guides.isEmpty { await state.load() } }
        }
    }
}
struct GuideImage: View {
    let path: String?
    let api: API
    @ViewState private var url: URL?
    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    case .failure: Image(systemName: "person.crop.square").resizable().scaledToFit().foregroundStyle(.secondary).padding()
                    default: ProgressView()
                    }
                }
            }
            else { Image(systemName: "person.crop.square").resizable().scaledToFit().foregroundStyle(.secondary).padding() }
        }.clipped().accessibilityHidden(true)
        .task(id: path) { if let path { url = try? await api.signedURL(path, bucket: "guide-images") } }
    }
}
struct GuideDetailView: View {
    let guide: Guide
    let api: API
    @Environment(\.openURL) private var openURL
    @ViewState private var bookingError = false
    var body: some View {
        List {
            if guide.isSample {
                Section { Label("Sample profile · WhatsApp booking demo", systemImage: "info.circle").font(.callout) }
            }
            GuideImage(path: guide.profile_image_path, api: api).frame(height: 220).frame(maxWidth: .infinity)
            Section("About") { Text(guide.description) }
            Section("Languages") { Text(guide.languages.joined(separator: ", ")) }
            Section("Areas covered") { Text(guide.covered_areas.joined(separator: ", ")) }
            if let tour = guide.tour_information { Section("Tour information") { Text(tour) } }
            if let price = guide.price { Section("Price") { Text(price) } }
            if guide.whatsAppBookingURL == nil, let contact = guide.contact_information {
                Section("Public contact") {
                    if let url = URL(string: contact), ["https", "tel", "mailto"].contains(url.scheme?.lowercased() ?? "") {
                        Link("Contact \(guide.name)", destination: url)
                    } else { Text(contact).textSelection(.enabled) }
                }
            }
        }.navigationTitle(guide.name).navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if let url = guide.whatsAppBookingURL {
                VStack(spacing: 8) {
                    Button {
                        openURL(url) { accepted in bookingError = !accepted }
                    } label: {
                        Label("Book on WhatsApp", systemImage: "message.fill")
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent).tint(Color(red: 0.05, green: 0.43, blue: 0.25))
                    Text(guide.isSample ? "Opens the test contact. This is a demo booking." : "Ask about dates and availability. Your booking is confirmed by the guide.")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.padding().background(.regularMaterial)
            }
        }
        .alert("Couldn’t open WhatsApp", isPresented: $bookingError) {
            Button("OK", role: .cancel) {}
        } message: { Text("Please try again and check that your device can open WhatsApp links.") }
    }
}

// Stable IDs keep sample rows identifiable across refreshes.
extension Guide {
    // One owner-provided test contact is shared by the fictional guide profiles.
    private static var sampleWhatsAppNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "GUIDE_DEMO_WHATSAPP_NUMBER") as? String ?? ""
    }
    var whatsAppBookingURL: URL? {
        let number: String
        if isSample {
            number = Self.sampleWhatsAppNumber
        } else if let contact = contact_information,
                  let url = URL(string: contact), url.scheme?.lowercased() == "https",
                  url.host?.lowercased() == "wa.me" {
            number = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        } else { return nil }
        guard (7...15).contains(number.count), number.first != "0",
              number.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
        let message = (isSample ? "[Demo booking] " : "") + "Hi, I’m interested in booking \(name). Could you share your availability and tour details?\nDate: \nNumber of guests: "
        var components = URLComponents()
        components.scheme = "https"
        components.host = "wa.me"
        components.path = "/" + number
        components.queryItems = [URLQueryItem(name: "text", value: message)]
        return components.url
    }

    var isSample: Bool { Self.samples.contains { $0.id == id } }
    static let samples: [Guide] = [
        Guide(id: UUID(uuidString: "D3000000-0000-4000-8000-000000000001")!,
              name: "Ardi — Village Walk", profile_image_path: nil,
              description: "A relaxed introduction to village paths, local crafts, and respectful visiting etiquette.",
              languages: ["Indonesian", "Sundanese"], covered_areas: ["Ciboleger", "Kanekes"],
              tour_information: "Sample itinerary: a 3-hour easy walk with rest stops. Route and village access would be confirmed before a real visit.",
              price: "Sample: Rp250,000 per group", contact_information: nil),
        Guide(id: UUID(uuidString: "D3000000-0000-4000-8000-000000000002")!,
              name: "Maya — Culture & Crafts", profile_image_path: nil,
              description: "Discover weaving traditions and everyday stories on a gentle, conversation-focused outing.",
              languages: ["Indonesian", "English"], covered_areas: ["Kanekes", "Ciboleger"],
              tour_information: "Sample itinerary: a half-day walk and craft introduction. Activities depend on local permission and availability.",
              price: "Sample: Rp350,000 per group", contact_information: nil),
        Guide(id: UUID(uuidString: "D3000000-0000-4000-8000-000000000003")!,
              name: "Deni — Nature Trails", profile_image_path: nil,
              description: "A slower day outdoors following scenic footpaths, with time to enjoy the landscape.",
              languages: ["Indonesian", "Sundanese", "English"], covered_areas: ["Ciboleger", "Surrounding Kanekes trails"],
              tour_information: "Sample itinerary: a 5-hour moderate walk. Bring drinking water, suitable footwear, and rain protection.",
              price: "Sample: Rp450,000 per group", contact_information: nil),
        Guide(id: UUID(uuidString: "D3000000-0000-4000-8000-000000000004")!,
              name: "Rina — Family Explorer", profile_image_path: nil,
              description: "Short walks and flexible breaks for families discovering the area together for the first time.",
              languages: ["Indonesian", "English"], covered_areas: ["Ciboleger"],
              tour_information: "Sample itinerary: a 2-hour gentle outing with frequent breaks and an introduction to visitor etiquette.",
              price: "Sample: Rp200,000 per group", contact_information: nil)
    ]
}
