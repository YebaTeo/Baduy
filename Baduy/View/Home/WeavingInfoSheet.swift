import SwiftUI
import AVFoundation

/// The weaving story shown alongside the tenun AR object.
private struct WeavingInfoPage {
    let object: BaduyARObject
    let title: String
    let introduction: String
    let heading: String
    let body: String

    var narration: String { [title, introduction, heading, body].joined(separator: ". ") }

    static let pages: [Self] = [
        .init(
            object: .tenun,
            title: "Kain Tenun",
            introduction: "Tahu nggak? Di Baduy teh tenun bukan cuma kain biasa.",
            heading: "Nggak buat sendiri lagi",
            body: "Nah, keterampilan menenun ini diturunkan dari ibu ke anak perempuannya. Jadi, mereka mah dari kecil udah terbiasa merhatiin dan belajar menenun langsung dari orang-orang terdekatnya. Keren euy!"
        ),
        .init(
            object: .pintal,
            title: "Memintal Benang",
            introduction: "Sebelum mulai menenun, kira-kira yg perlu disiapin dulu apa, ya?",
            heading: "Persiapkan Benang",
            body: "Serat kapas diputar lalu digulung menjadi benang yang panjang dan kuat. Setelah itu dimasukin ke alat tenun tradisional yang disebut gedongan. Cuman sekarang mah, kebanyakan penenun udah ga bikin benang sendiri lagi, kenapa ya mereka udah jarang bikin benang sendiri lagi?"
        ),
        .init(
            object: .tenun,
            title: "Proses Menenun",
            introduction: "Kalau benangnya udah siap, proses menenun baru bisa dimulai.",
            heading: "Heading",
            body: "Buka celah benang, selipkan benang melintang, lalu rapatkan. Ulangi sampai pola dan panjang kain sesuai keinginan, kemudian lepaskan dan rapikan ujungnya. Hmm, kira-kira dari proses ini yang paling susah menurut para penenun di bagian mananya, ya?"
        )
    ]
}

struct WeavingInfoSheet: View {
    let onFinish: () -> Void
    var onObjectChange: (BaduyARObject) -> Void = { _ in }
    @ViewState private var pageIndex = 0
    @ViewState private var narrator = AVSpeechSynthesizer()

    private var page: WeavingInfoPage { WeavingInfoPage.pages[pageIndex] }
    private var isLastPage: Bool { pageIndex == WeavingInfoPage.pages.count - 1 }

    var body: some View {
        BaduySheet(
            title: page.title,
            style: .white,
            audioAction: narrate,
            compactSummary: page.introduction,
            actionTitle: isLastPage ? "Selesai" : "Berikutnya",
            action: advance,
            pageLabel: "\(pageIndex + 1)/\(WeavingInfoPage.pages.count)"
        ) {
            Text(page.introduction).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                Text(page.heading).font(.headline)
                Text(page.body).fixedSize(horizontal: false, vertical: true)
            }
        }
        // Each new page starts at the top instead of retaining the old scroll offset.
        .id(pageIndex)
        .onChange(of: pageIndex, initial: true) { _, _ in
            onObjectChange(page.object)
        }
        .onDisappear { narrator.stopSpeaking(at: .immediate) }
    }

    private func advance() {
        narrator.stopSpeaking(at: .immediate)
        if isLastPage { onFinish() } else { pageIndex += 1 }
    }

    private func narrate() {
        narrator.stopSpeaking(at: .immediate)
        let speech = AVSpeechUtterance(string: page.narration)
        speech.voice = AVSpeechSynthesisVoice(language: "id-ID")
        narrator.speak(speech)
    }
}
