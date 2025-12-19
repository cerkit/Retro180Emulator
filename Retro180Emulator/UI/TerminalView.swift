import SwiftUI
import Combine

struct TerminalView: View {
    @ObservedObject var viewModel: TerminalViewModel

    let rows = 25
    let cols = 80

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<cols, id: \.self) { col in
                        CharacterView(char: viewModel.grid[row][col])
                    }
                }
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
            .foregroundColor(Color(red: 1.0, green: 0.7, blue: 0.0))  // Amber
            .frame(width: 8, height: 16)
            .clipped() // Ensure it doesn't bleed into other cells
    }
}

@MainActor
class TerminalViewModel: ObservableObject {
    @Published var grid: [[Character]] = Array(
        repeating: Array(repeating: " ", count: 80), count: 25)

    private var cursorRow = 0
    private var cursorCol = 0

    func putChar(_ char: Character) {
        // Simple terminal logic
        if char == "\n" {
            newLine()
        } else if char == "\r" {
            cursorCol = 0
        } else {
            // Prevent out of bounds
            if cursorRow < 25 && cursorCol < 80 {
                grid[cursorRow][cursorCol] = char
                cursorCol += 1
                if cursorCol >= 80 {
                    newLine()
                }
            }
        }
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

    func start() {
        // Initialization if needed
    }
}
