import Foundation
import Observation

struct Note: Codable, Identifiable, Equatable {
    var id = UUID()
    var body: String
    var updated = Date()

    /// The first line, which is how a note is named in the list.
    var title: String {
        let first = body.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let trimmed = first.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "New Note" : String(trimmed.prefix(60))
    }
}

struct Snippet: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var text: String
}

/// Quick notes and text snippets, kept as one JSON file in Application Support.
@MainActor
@Observable
final class NotesModel {
    private struct Stored: Codable {
        var notes: [Note] = []
        var snippets: [Snippet] = []
    }

    private(set) var notes: [Note] = []
    private(set) var snippets: [Snippet] = []
    var selectedNoteID: UUID?
    var selectedSnippetID: UUID?

    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    init(directory: URL? = nil) {
        let folder = directory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("MacIsland", isDirectory: true)
        fileURL = folder.appendingPathComponent("notes.json")
        if let data = try? Data(contentsOf: fileURL), let stored = try? JSONDecoder().decode(Stored.self, from: data) {
            notes = stored.notes
            snippets = stored.snippets
        }
        selectedNoteID = notes.first?.id
        selectedSnippetID = snippets.first?.id
    }

    var selectedNote: Note? { notes.first { $0.id == selectedNoteID } }
    var selectedSnippet: Snippet? { snippets.first { $0.id == selectedSnippetID } }

    // MARK: Notes

    @discardableResult
    func addNote() -> Note {
        let note = Note(body: "")
        notes.insert(note, at: 0)
        selectedNoteID = note.id
        scheduleSave()
        return note
    }

    func setBody(_ body: String, ofNote id: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == id }), notes[index].body != body else { return }
        notes[index].body = body
        notes[index].updated = Date()
        scheduleSave()
    }

    func deleteNote(_ id: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes.remove(at: index)
        if selectedNoteID == id { selectedNoteID = notes.indices.contains(index) ? notes[index].id : notes.last?.id }
        scheduleSave()
    }

    // MARK: Snippets

    @discardableResult
    func addSnippet() -> Snippet {
        let snippet = Snippet(title: "", text: "")
        snippets.insert(snippet, at: 0)
        selectedSnippetID = snippet.id
        scheduleSave()
        return snippet
    }

    func setTitle(_ title: String, ofSnippet id: UUID) {
        update(snippet: id) { $0.title = title }
    }

    func setText(_ text: String, ofSnippet id: UUID) {
        update(snippet: id) { $0.text = text }
    }

    func deleteSnippet(_ id: UUID) {
        guard let index = snippets.firstIndex(where: { $0.id == id }) else { return }
        snippets.remove(at: index)
        if selectedSnippetID == id {
            selectedSnippetID = snippets.indices.contains(index) ? snippets[index].id : snippets.last?.id
        }
        scheduleSave()
    }

    private func update(snippet id: UUID, _ change: (inout Snippet) -> Void) {
        guard let index = snippets.firstIndex(where: { $0.id == id }) else { return }
        var copy = snippets[index]
        change(&copy)
        guard copy != snippets[index] else { return }
        snippets[index] = copy
        scheduleSave()
    }

    // MARK: Saving

    /// Waits for a pause in typing, then writes everything.
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    /// Writes now. Called on a pause in typing, and when the app quits.
    func save() {
        saveTask?.cancel()
        let stored = Stored(notes: notes, snippets: snippets)
        guard let data = try? JSONEncoder().encode(stored) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
