import Combine
import SwiftUI

struct TerminalView: View {
    @ObservedObject var viewModel: TerminalViewModel

    let rows = 25
    let cols = 80

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<rows, id: \.self) { row in
                Text(String(viewModel.grid[row]))
                    .font(.system(size: 14, weight: .regular, design: .monospaced))
                    .foregroundColor(Color(red: 1.0, green: 0.7, blue: 0.0))
                    .frame(height: 16)
            }
        }
        .padding(10)
        .background(Color.black)
        .onAppear {
            viewModel.start()
        }
    }
}

struct CharacterView: View {
    let char: Character

    var body: some View {
        Text(String(char))
            .font(.system(size: 14, weight: .regular, design: .monospaced))
            .foregroundColor(Color(red: 1.0, green: 0.7, blue: 0.0))
            .frame(width: 8, height: 16)
            .clipped()
    }
}

@MainActor
class TerminalViewModel: ObservableObject {
    @Published var grid: [[Character]] = Array(
        repeating: Array(repeating: " ", count: 80), count: 25)

    private var cursorRow = 0
    private var cursorCol = 0

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
