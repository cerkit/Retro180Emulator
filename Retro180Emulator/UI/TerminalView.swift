import Combine
import SwiftUI

struct TerminalView: View {
    @ObservedObject var viewModel: TerminalViewModel
    var onKey: (UInt8) -> Void
    @FocusState private var isFocused: Bool

    let rows = 25
    let cols = 80

    @AppStorage("monitorColor") private var monitorColor: MonitorColor = .amber

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<rows, id: \.self) { row in
                lineView(row: row)
            }
        }
        .padding(10)
        .background(Color.black)
        .focusable()
        .focused($isFocused)
        .onKeyPress { press in
            guard let first = press.characters.first?.unicodeScalars.first else { return .ignored }
            let val = first.value
            // Only handle standard ASCII/Control characters for now to avoid crashes (val <= 255)
            if val <= 255 {
                onKey(UInt8(val))
                return .handled
            }
            return .ignored
        }
        .onAppear {
            isFocused = true
            viewModel.start()
        }
        .onTapGesture {
            isFocused = true
        }
    }

    private func lineView(row: Int) -> some View {
        let line = viewModel.grid[row]
        let isCursorRow = row == viewModel.cursorRow

        return HStack(spacing: 0) {
            if isCursorRow {
                let col = viewModel.cursorCol
                let safeCol = min(max(0, col), cols - 1)

                let left = String(line[0..<safeCol])
                let cursor = String(line[safeCol])
                let right = String(line[(safeCol + 1)...])

                Text(left)
                Text(cursor)
                    .background(monitorColor.color)
                    .foregroundColor(.black)
                Text(right)
            } else {
                Text(String(line))
            }
        }
        .font(.system(size: 14, weight: .regular, design: .monospaced))
        .foregroundColor(monitorColor.color)
        .frame(height: 16)
    }
}

struct CharacterView: View {
    let char: Character
    @AppStorage("monitorColor") private var monitorColor: MonitorColor = .amber

    var body: some View {
        Text(String(char))
            .font(.system(size: 14, weight: .regular, design: .monospaced))
            .foregroundColor(monitorColor.color)
            .frame(width: 8, height: 16)
            .clipped()
    }
}

@MainActor
class TerminalViewModel: ObservableObject {
    @Published var grid: [[Character]] = Array(
        repeating: Array(repeating: " ", count: 80), count: 25)

    @Published var cursorRow = 0
    @Published var cursorCol = 0

    func putChar(_ char: Character) {
        // Map CP437 box-drawing characters to Unicode
        var displayChar = char
        if let scalar = char.unicodeScalars.first?.value {
            switch scalar {
            case 0xDA: displayChar = "┌"
            case 0xBF: displayChar = "┐"
            case 0xC0: displayChar = "└"
            case 0xD9: displayChar = "┘"
            case 0xC4: displayChar = "─"
            case 0xB3: displayChar = "│"
            default: break
            }
        }

        if char == "\n" {
            newLine()
        } else if char == "\r" {
            cursorCol = 0
        } else {
            if cursorRow < 25 && cursorCol < 80 {
                grid[cursorRow][cursorCol] = displayChar
                cursorCol += 1
                if cursorCol >= 80 {
                    newLine()
                }
            }
        }
        objectWillChange.send()
    }

    private func newLine() {
        cursorCol = 0
        cursorRow += 1
        if cursorRow >= 25 {
            scroll()
            cursorRow = 24
        }
    }

    private func scroll() {
        for r in 0..<24 {
            grid[r] = grid[r + 1]
        }
        grid[24] = Array(repeating: " ", count: 80)
    }

    func start() {}
}
