import SwiftUI

struct CharacterConversationView: View {
    let character: BaduyCharacter
    @State private var page = 0
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Label(character.title, systemImage: "bubble.left.and.bubble.right.fill")
                        .font(.title2.bold())
                    Text(character.lines[page]).font(.title3)
                    HStack {
                        Button("Sebelumnya") { page -= 1 }.disabled(page == 0)
                        Spacer()
                        Text("\(page + 1)/\(character.lines.count)").font(.caption)
                        Spacer()
                        Button("Berikutnya") { page += 1 }
                            .disabled(page == character.lines.count - 1)
                    }
                    Link("Sumber materi", destination: character.source)
                }.padding()
            }
            .navigationTitle("Kenali Baduy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Tutup") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
