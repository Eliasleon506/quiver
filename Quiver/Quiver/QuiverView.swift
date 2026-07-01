import SwiftUI
import SwiftData

struct QuiverView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Board.addedAt, order: .reverse) private var boards: [Board]

    @State private var showingNewBoard = false
    @State private var editingBoard: Board?
    @State private var showingDimensionRecommender = false

    var body: some View {
        Group {
            if boards.isEmpty {
                emptyState
            } else {
                boardList
            }
        }
        .navigationTitle("Quiver")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showingDimensionRecommender = true
                } label: {
                    Label("Sizing", systemImage: "ruler")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingNewBoard = true
                } label: {
                    Label("Add board", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingNewBoard) {
            NavigationStack {
                BoardEditorView(board: nil) { saved in
                    modelContext.insert(saved)
                    try? modelContext.save()
                    showingNewBoard = false
                } onCancel: {
                    showingNewBoard = false
                }
            }
        }
        .sheet(item: $editingBoard) { board in
            NavigationStack {
                BoardEditorView(board: board) { _ in
                    try? modelContext.save()
                    editingBoard = nil
                } onCancel: {
                    modelContext.rollback()
                    editingBoard = nil
                }
            }
        }
        .sheet(isPresented: $showingDimensionRecommender) {
            NavigationStack {
                DimensionRecommenderView()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 54))
                .foregroundStyle(.tertiary)
            Text("No boards yet").font(.title2.weight(.semibold))
            Text("Add the boards you own and we'll pick from your quiver instead of just telling you what to look for.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            Button {
                showingNewBoard = true
            } label: {
                Label("Add a board", systemImage: "plus")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 32)
            Spacer()
        }
    }

    private var boardList: some View {
        List {
            ForEach(boards) { board in
                Button { editingBoard = board } label: { BoardRow(board: board) }
                    .buttonStyle(.plain)
            }
            .onDelete { offsets in
                for i in offsets { modelContext.delete(boards[i]) }
                try? modelContext.save()
            }
        }
        .listStyle(.insetGrouped)
    }
}

private struct BoardRow: View {
    let board: Board

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: "figure.surfing")
                    .imageScale(.large)
                    .foregroundStyle(.tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(board.nickname ?? board.type.displayName).font(.body.weight(.semibold))
                Text(board.type.displayName).font(.caption).foregroundStyle(.secondary)
                DimensionLabel(lengthIn: board.lengthIn, widthIn: board.widthIn,
                               thicknessIn: board.thicknessIn, volumeL: board.effectiveVolumeL)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}
