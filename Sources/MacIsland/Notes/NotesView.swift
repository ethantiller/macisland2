import SwiftUI

enum NotesMode: String, CaseIterable, Identifiable {
    case notes = "Notes"
    case snippets = "Snippets"
    case prompter = "Prompter"

    var id: Self { self }
}

/// The Notes module: quick notes, text snippets, and a teleprompter for the selected note.
struct NotesView: View {
    let viewModel: IslandViewModel

    private var mode: NotesMode { viewModel.notesMode }

    private var notes: NotesModel { viewModel.notes }

    var body: some View {
        VStack(spacing: Theme.Metrics.rowSpacing) {
            HStack(spacing: 4) {
                SegmentedChoice(options: NotesMode.allCases, selection: mode, title: \.rawValue, onSelect: viewModel.setNotesMode)
                .frame(width: 250)
                Spacer(minLength: 0)
                IconButton(
                    systemName: viewModel.voice.isRecording ? "stop.fill" : "mic",
                    label: viewModel.voice.isRecording ? "Stop Voice Note" : "Record Voice Note",
                    size: 13
                ) { viewModel.toggleVoiceNote() }
                switch mode {
                case .notes: IconButton(systemName: "square.and.pencil", label: "New Note", size: 13) { notes.addNote() }
                case .snippets: IconButton(systemName: "plus", label: "New Snippet", size: 13) { notes.addSnippet() }
                case .prompter: EmptyView()
                }
            }
            .frame(height: Theme.Metrics.hitTarget)

            switch mode {
            case .notes: NotesPane(viewModel: viewModel)
            case .snippets: SnippetsPane(viewModel: viewModel)
            case .prompter: PrompterView(notes: notes)
            }
        }
        .onDisappear { notes.save() }
    }
}

// MARK: Lists and editors

/// A list on the left, its editor on the right.
private struct NotesPane: View {
    let viewModel: IslandViewModel

    @Environment(\.isFloatingWindow) private var isFloating

    private var notes: NotesModel { viewModel.notes }

    var body: some View {
        HStack(spacing: 10) {
            ItemList(
                rows: notes.notes.map { ItemRow(id: $0.id, title: $0.title) },
                selection: notes.selectedNoteID,
                onSelect: { notes.selectedNoteID = $0 },
                onDelete: { notes.deleteNote($0) }
            )
            if let note = notes.selectedNote {
                EditorField(
                    text: Binding(get: { note.body }, set: { notes.setBody($0, ofNote: note.id) }),
                    onFocus: { if !isFloating { viewModel.holdOpen() } }
                )
                .id(note.id)
            } else {
                EmptyLabel(text: "Write a quick note", systemImage: "square.and.pencil")
            }
        }
    }
}

private struct SnippetsPane: View {
    let viewModel: IslandViewModel

    @Environment(\.isFloatingWindow) private var isFloating

    private var notes: NotesModel { viewModel.notes }

    var body: some View {
        HStack(spacing: 10) {
            ItemList(
                rows: notes.snippets.map { ItemRow(id: $0.id, title: $0.title.isEmpty ? "New Snippet" : $0.title) },
                selection: notes.selectedSnippetID,
                onSelect: { notes.selectedSnippetID = $0 },
                onDelete: { notes.deleteSnippet($0) }
            )
            if let snippet = notes.selectedSnippet {
                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        TextField("Name", text: Binding(
                            get: { snippet.title }, set: { notes.setTitle($0, ofSnippet: snippet.id) }
                        ))
                        .textFieldStyle(.plain)
                        .font(Theme.Typography.bodyEmphasized)
                        .foregroundStyle(Theme.Palette.primary)
                        ChipButton(title: "Copy", systemImage: "doc.on.doc") {
                            viewModel.copySnippet(snippet)
                        }
                    }
                    EditorField(
                        text: Binding(get: { snippet.text }, set: { notes.setText($0, ofSnippet: snippet.id) }),
                        onFocus: { if !isFloating { viewModel.holdOpen() } }
                    )
                }
                .id(snippet.id)
            } else {
                EmptyLabel(text: "Save text you type often", systemImage: "text.badge.plus")
            }
        }
    }
}

private struct ItemRow: Identifiable {
    let id: UUID
    let title: String
}

/// Titles, newest first. The selected row is filled white, like other "on" states.
private struct ItemList: View {
    let rows: [ItemRow]
    let selection: UUID?
    let onSelect: (UUID) -> Void
    let onDelete: (UUID) -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 2) {
                ForEach(rows) { row in
                    let isSelected = row.id == selection
                    Button { onSelect(row.id) } label: {
                        Text(row.title)
                            .font(Theme.Typography.body)
                            .foregroundStyle(isSelected ? Theme.Palette.inverse : Theme.Palette.primary)
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
                            .background(isSelected ? Theme.Palette.primary : Theme.Palette.none, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(IslandButtonStyle())
                    .contextMenu { Button("Delete") { onDelete(row.id) } }
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
        .frame(width: 130)
    }
}

/// Multi-line text in a rounded field. Focusing it keeps the island open while typing.
private struct EditorField: View {
    @Binding var text: String
    let onFocus: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        TextEditor(text: $text)
            .font(Theme.Typography.body)
            .foregroundStyle(Theme.Palette.primary)
            .scrollContentBackground(.hidden)
            .focused($isFocused)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Theme.Palette.fill, in: RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous))
            .onChange(of: isFocused) { _, focused in if focused { onFocus() } }
    }
}

private struct EmptyLabel: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(Theme.Typography.bodyEmphasized)
            .foregroundStyle(Theme.Palette.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .foregroundStyle(Theme.Palette.tertiary)
            )
    }
}

// MARK: Prompter

/// The selected note, scrolling under the camera at an adjustable speed.
struct PrompterView: View {
    let notes: NotesModel

    @State private var speed = 0.35
    @State private var isRunning = false
    @State private var offset: CGFloat = 0
    @State private var resumedAt = Date()
    @State private var offsetAtResume: CGFloat = 0
    @State private var textHeight: CGFloat = 0

    private static let window: CGFloat = 76
    /// Points per second across the slider's range.
    private static let speeds: ClosedRange<Double> = 12...80

    var body: some View {
        VStack(spacing: Theme.Metrics.rowSpacing) {
            if let note = notes.selectedNote, !note.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                scroller(note.body)
            } else {
                EmptyLabel(text: "Pick a note in Notes to read", systemImage: "text.alignleft")
                    .frame(height: Self.window)
            }
            controls
        }
    }

    private func scroller(_ text: String) -> some View {
        TimelineView(.animation(paused: !isRunning)) { context in
            let current = isRunning ? min(offsetAtResume + CGFloat(context.date.timeIntervalSince(resumedAt) * pointsPerSecond), max(textHeight, 0)) : offset
            Text(text)
                .font(Theme.Typography.prompter)
                .foregroundStyle(Theme.Palette.primary)
                .multilineTextAlignment(.center)
                .frame(width: 340)
                .fixedSize(horizontal: false, vertical: true)
                .background(GeometryReader { geometry in
                    Color.clear.onAppear { textHeight = geometry.size.height }
                        .onChange(of: geometry.size.height) { _, height in textHeight = height }
                })
                .offset(y: -current)
                .frame(maxWidth: .infinity, minHeight: Self.window, maxHeight: Self.window, alignment: .top)
                .clipped()
                .mask(
                    LinearGradient(
                        stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.12),
                                .init(color: .black, location: 0.88), .init(color: .clear, location: 1)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .onChange(of: current >= textHeight && isRunning) { _, finished in
                    if finished { stop(at: textHeight) }
                }
        }
        .accessibilityLabel("Prompter: \(text)")
    }

    private var controls: some View {
        HStack(spacing: 8) {
            IconButton(
                systemName: isRunning ? "pause.fill" : "play.fill",
                label: isRunning ? "Pause Prompter" : "Start Prompter",
                size: 14
            ) { isRunning ? stop(at: currentOffset()) : start() }
            IconButton(systemName: "backward.end.fill", label: "Back to Top", size: 12) {
                stop(at: 0)
            }
            Image(systemName: "tortoise.fill")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.tertiary)
                .accessibilityHidden(true)
            IslandSlider(value: speed, label: "Scroll Speed", onChange: { setSpeed($0) })
                .frame(maxWidth: 200)
            Image(systemName: "hare.fill")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.tertiary)
                .accessibilityHidden(true)
            Spacer(minLength: 0)
        }
        .frame(height: Theme.Metrics.hitTarget)
    }

    private var pointsPerSecond: Double {
        Self.speeds.lowerBound + speed * (Self.speeds.upperBound - Self.speeds.lowerBound)
    }

    private func currentOffset() -> CGFloat {
        min(offsetAtResume + CGFloat(Date().timeIntervalSince(resumedAt) * pointsPerSecond), max(textHeight, 0))
    }

    private func start() {
        offsetAtResume = offset >= textHeight ? 0 : offset
        resumedAt = Date()
        isRunning = true
    }

    private func stop(at position: CGFloat) {
        offset = position
        offsetAtResume = position
        isRunning = false
    }

    /// Changing speed mid-scroll continues from where the text is now.
    private func setSpeed(_ value: Double) {
        if isRunning {
            offsetAtResume = currentOffset()
            resumedAt = Date()
        }
        speed = value
    }
}
