import SwiftUI

/// Editor for a Board. `board == nil` means "create new". The closures handle
/// persistence — the view doesn't touch the model context directly so the same
/// form drives both the sheet-presented new-board flow and edit flow.
struct BoardEditorView: View {
    let initialBoard: Board?
    let onSave: (Board) -> Void
    let onCancel: () -> Void

    @State private var nickname: String
    @State private var type: BoardType
    @State private var lengthFeet: Int
    @State private var lengthInchesRemainder: Double   // 0.0..11.5 in half-inch steps
    @State private var widthIn: Double
    @State private var thicknessIn: Double
    @State private var volumeText: String              // empty → use estimate
    @State private var tailShape: TailShape?
    @State private var notes: String

    private let isEditing: Bool

    init(board: Board?, onSave: @escaping (Board) -> Void, onCancel: @escaping () -> Void) {
        self.initialBoard = board
        self.onSave = onSave
        self.onCancel = onCancel
        self.isEditing = board != nil

        if let b = board {
            _nickname = State(initialValue: b.nickname ?? "")
            _type = State(initialValue: b.type)
            _lengthFeet = State(initialValue: Int(b.lengthIn) / 12)
            _lengthInchesRemainder = State(initialValue: b.lengthIn.truncatingRemainder(dividingBy: 12))
            _widthIn = State(initialValue: b.widthIn)
            _thicknessIn = State(initialValue: b.thicknessIn)
            _volumeText = State(initialValue: b.volumeL.map { String(format: "%.1f", $0) } ?? "")
            _tailShape = State(initialValue: b.tailShape)
            _notes = State(initialValue: b.notes ?? "")
        } else {
            _nickname = State(initialValue: "")
            _type = State(initialValue: .hpsb)
            _lengthFeet = State(initialValue: 5)
            _lengthInchesRemainder = State(initialValue: 10)
            _widthIn = State(initialValue: 19.0)
            _thicknessIn = State(initialValue: 2.4)
            _volumeText = State(initialValue: "")
            _tailShape = State(initialValue: nil)
            _notes = State(initialValue: "")
        }
    }

    private var totalLengthIn: Double { Double(lengthFeet * 12) + lengthInchesRemainder }

    private var estimatedVolumeL: Double {
        totalLengthIn * widthIn * thicknessIn * type.shapeCoefficient * 0.01639
    }

    private var parsedVolume: Double? {
        let trimmed = volumeText.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "L", with: "")
            .replacingOccurrences(of: "l", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed)
    }

    var body: some View {
        Form {
            Section("Board") {
                TextField("Nickname (optional, e.g. Ghost)", text: $nickname)
                Picker("Type", selection: $type) {
                    ForEach(BoardType.allCases) { t in
                        Text(t.displayName).tag(t)
                    }
                }
            }

            Section("Dimensions") {
                Stepper("Length: \(lengthFeet)' \(lengthInchesString)\"", value: $lengthFeet, in: 4...12)
                Stepper(value: $lengthInchesRemainder, in: 0...11.5, step: 0.5) {
                    HStack {
                        Text("Inches")
                        Spacer()
                        Text(lengthInchesString).foregroundStyle(.secondary)
                    }
                }
                Stepper(value: $widthIn, in: 16.0...26.0, step: 0.125) {
                    HStack {
                        Text("Width")
                        Spacer()
                        Text(String(format: "%.3f\"", widthIn)).foregroundStyle(.secondary)
                    }
                }
                Stepper(value: $thicknessIn, in: 2.0...4.0, step: 0.05) {
                    HStack {
                        Text("Thickness")
                        Spacer()
                        Text(String(format: "%.2f\"", thicknessIn)).foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                HStack {
                    Text("Volume (L)")
                    Spacer()
                    TextField("optional", text: $volumeText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 100)
                }
                HStack {
                    Text("Estimate")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.1f L", estimatedVolumeL))
                        .font(.body.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
            } header: {
                Text("Volume")
            } footer: {
                Text("Leave blank to use the geometric estimate from dimensions. Shape coefficient for \(type.displayName) is \(String(format: "%.3f", type.shapeCoefficient)).")
            }

            Section("Details") {
                Picker("Tail", selection: $tailShape) {
                    Text("Not set").tag(TailShape?.none)
                    ForEach(TailShape.allCases) { t in
                        Text(t.displayName).tag(TailShape?.some(t))
                    }
                }
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(2...4)
            }
        }
        .navigationTitle(isEditing ? "Edit board" : "New board")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { onCancel() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { save() }
                    .bold()
                    .disabled(totalLengthIn < 48)
            }
        }
    }

    private var lengthInchesString: String {
        if lengthInchesRemainder == floor(lengthInchesRemainder) {
            return "\(Int(lengthInchesRemainder))"
        }
        return String(format: "%.1f", lengthInchesRemainder)
    }

    private func save() {
        let trimmedNickname = nickname.trimmingCharacters(in: .whitespaces)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespaces)

        if let existing = initialBoard {
            existing.nickname = trimmedNickname.isEmpty ? nil : trimmedNickname
            existing.type = type
            existing.lengthIn = totalLengthIn
            existing.widthIn = widthIn
            existing.thicknessIn = thicknessIn
            existing.volumeL = parsedVolume
            existing.tailShape = tailShape
            existing.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
            onSave(existing)
        } else {
            let board = Board(
                nickname: trimmedNickname.isEmpty ? nil : trimmedNickname,
                type: type,
                lengthIn: totalLengthIn,
                widthIn: widthIn,
                thicknessIn: thicknessIn,
                volumeL: parsedVolume,
                tailShape: tailShape,
                notes: trimmedNotes.isEmpty ? nil : trimmedNotes
            )
            onSave(board)
        }
    }
}
