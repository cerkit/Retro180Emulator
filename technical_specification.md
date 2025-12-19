# Retro180Emulator Technical Specification

## 1. System Overview

**Retro180Emulator** is a macOS-based emulator for the Zilog Z180 microprocessor, specifically tailored to emulate the SC131 pocket-sized computer architecture. It provides a comprehensive emulation environment including a Z180 CPU core, Memory Management Unit (MMU), Serial I/O (ASCI), and specialized hardware extensions like a text-to-speech engine.

The system is designed with a layered architecture, separating the core hardware simulation (`Core` & `Hardware` modules) from the user presentation layer (`UI` module). This ensures a clean separation of concerns, where the `Motherboard` acts as the central integration point, simulating the physical motherboard's bus and clock.

Key Design Philosophies:
-   **Accuracy driven by "Good Enough" Utility**: The emulation targets instruction-set compatibility sufficient to run the RomWBW operating system (CP/M-80 compatible) rather than cycle-perfect hardware accuracy.
-   **Native macOS Integration**: Utilizes Swift and SwiftUI for a performant, modern user interface, leveraging AVFoundation for high-quality speech synthesis rather than emulating legacy synthesizer chips.
-   **Component Modularity**: Each hardware subsystem (CPU, MMU, I/O) is isolated, allowing for easier debugging and potential future expansion (e.g., adding an SD card emulation).

---

## 2. Core Functional Sections

### 2.1 Central Processing Unit (CPU)
The heart of the emulator is the `Z180CPU` class. It emulates the Zilog Z180 instruction set, which is a superset of the Z80 with added instructions (e.g., `MLT` multiply) and integrated peripherals.

**Implementation Details:**
-   **Register State**: Implements full Z80/Z180 register sets, including main (`AF`, `BC`, `DE`, `HL`) and alternate (`AF'`, `BC'`, etc.) registers, plus index registers (`IX`, `IY`) and system registers (`SP`, `PC`, `I`, `R`).
-   **Execution Loop**: The `step()` function performs a fetch-decode-execute cycle. Complex instruction groups (`ED`, `CB`, `DD`, `FD` prefixes) are delegated to specific handler subroutines (`executeED`, `executeCB`, `executeIndex`).
-   **Interrupt Handling**: Supports Z80 interrupt modes 0, 1, and 2. It checks for maskable interrupts (`INT0`) via `checkInterrupts()` before each instruction cycle if `IFF1` is enabled. It correctly interacts with the I/O dispatcher to retrieve interrupt vectors.
-   **Z180 Specifics**: Includes the 8-bit multiply (`MLT`) instruction and handles Z180-specific I/O instructions (`IN0`, `OUT0`, `OTIM`, `OTDM` families).

**Justification:**
A naive switch-case interpreter was chosen over a JIT compiler for simplicity and ease of debugging. Given modern host CPU speeds (3GHz+), emulating a <20MHz Z180 purely in Swift software is performant enough for real-time usage without the complexity of dynamic recompilation.

### 2.2 Memory Management Unit (MMU)
The `Z180MMU` class emulates the built-in MMU of the Z180, which extends the 16-bit (64KB) logical address space to a 20-bit (1MB) physical address space.

**Implementation Details:**
-   **Address Translation**: Logic translates 16-bit logical addresses to 20-bit physical addresses using the Z180's `CBAR` (Common/Bank Area Register), `BBR` (Bank Base Register), and `CBR` (Common Base Register).
-   **Memory Map (SC131 Compatible)**:
    -   **ROM**: 0x00000 - 0x7FFFF (Lower 512KB)
    -   **RAM**: 0x80000 - 0xFFFFF (Upper 512KB)
-   **Banking Logic**:
    -   **Area 0**: Fixed base 0x00 (typically for vector table/boot code).
    -   **Bank Area**: Relocatable window controlled by `BBR`.
    -   **Common Area 1**: Relocatable window controlled by `CBR` (typically for OS high memory).

**Justification:**
Implementing the authentic Z180 MMU banking logic is critical for running operating systems like CP/M Plus and RomWBW, which rely on bank switching to manage processes larger than 64KB.

### 2.3 I/O Subsystem
The `Z180IODispatcher` class manages the Z180's I/O address space (0x0000 - 0xFFFF).

**Implementation Details:**
-   **Internal Registers**: Z180 internal registers (ASCI control, MMU registers, DMAC, etc.) are mapped to a relocatable 64-byte window (default base 0x00). The dispatcher intercepts reads/writes to this range and routes them to `Z180ASCI`, `Z180MMU`, `Z180PRT` instances.
-   **External Device Registration**: Allows attaching devices to arbitrary ports.
    -   **Speech Device**: Mapped to port `0x50` (Simulation of SP0256 interface).
    -   **SD Card (Planned)**: Hooks for ports `0xCA`/`0xCB`.

**Justification:**
The dynamic dispatch allows for flexible system configuration. By "relocating" internal registers in software (matching the hardware behavior of the Z180 I/O Control Register), the emulator can support BIOS versions that move the internal register block to high memory (e.g., 0xC0) to free up zero-page I/O for other peripherals.

### 2.4 Peripherals

#### Async Serial Communication Interface (ASCI)
The `Z180ASCI` class emulates the Z180's on-chip UARTs (Channels 0 and 1).

**Implementation Details:**
-   **Buffering**: Uses `Data` queues for input and output buffering.
-   **Interrupts**: Implements `RIE` (Receive Interrupt Enable) logic. When data arrives in the input buffer and `RIE` is set, it signals an interrupt to the CPU.
-   **Register Mapping**: Supports both standard Z180 register offsets (0-4) and "Stride-2" mapping often used in SC126/SC131 hardware (offsets 0, 2, 4, 6) to align with board layouts.

#### Speech Device (HLE)
The `SpeechDevice` class is a High-Level Emulation (HLE) replacement for the vintage SP0256-AL2 chip.

**Implementation Details:**
-   **Interface**: Listens on Port 0x50. Writes to this port are buffered.
-   **Trigger**: Upon receiving a Carriage Return (`0x0D`), the buffered text is synthesized using macOS's `AVSpeechSynthesizer`.
-   **Feedback**: Reads from Port 0x50 return a status bit indicating if the synthesizer is currently speaking (emulator busy flag).

**Justification:**
Instead of emulating the low-level phoneme generation of an SP0256 (which sounds robotic and low-fidelity), the emulator leverages the host OS's advanced text-to-speech engine. This provides clearer audio output while maintaining software compatibility with programs that just send ASCII text to the speech port.

### 2.5 User Interface (UI)
The UI is built with **SwiftUI**, following the MVVM (Model-View-ViewModel) pattern.

**Implementation Details:**
-   **TerminalView**: Renders a 80x25 character grid. It does not use a raw bitmap buffer but rather a grid of `Character` objects/strings, allowing for responsive text resizing and coloration.
-   **Motherboard Integration**: The `Motherboard` class publishes `@Published` properties for `terminalOutput`? No, it pushes data to `Z180ASCI`'s output buffer, which the `TerminalViewModel` polls or observes to update the grid.
-   **Input Handling**: Captures SwiftUI keyboard events and injects them into the `Motherboard`'s input queue, simulating serial data arriving at the ASCI.

---

## 3. Data Flow Architecture

1.  **Clock Tick**: A `Timer` in `Motherboard` fires ~100Hz.
2.  **CPU Burst**: The CPU executes a burst of cycles (e.g., 5,000 instructions) to simulate real-time speed.
3.  **Peripheral Update**: PRT (Timers) are stepped based on the cycles consumed.
4.  **I/O Check**:
    -   **Output**: The UI checks `ASCI` output buffers and renders new characters to the screen.
    -   **Input**: Keystrokes from the UI are pushed to the `ASCI` input buffer. If interrupts are enabled, the ASCI asserts an interrupt line.
5.  **Interrupt Service**: On the next CPU step, the pending interrupt is detected, the CPU saves context, and jumps to the ISR (Interrupt Service Routine) defined by the OS/BIOS (typically jumping to the vector table at 0x0000 or the address specified by `IM 2`).

## 4. Design Decisions & Justification

| Decision | Alternative Considered | Justification |
| :--- | :--- | :--- |
| **Swift / SwiftUI** | C++ / Qt / SDL | Leveraging native macOS technologies allows for a smaller codebase, better accessibility integration, and easier maintenance for a Mac-first tool. |
| **High-Level Speech** | SP0256 Chip Emulation | Emulating the exact verified behavioral model of an SP0256 is complex and results in lower audio quality. HLE provides immediate utility and readability. |
| **Timer-Based Loop** | Dedicated Thread | A simple `Timer` on the main runloop (or background dispatch) simplifies thread safety with the UI. Since strict real-time accuracy isn't required for a text-based OS, this avoids complex locking synchronization. |
| **Z180 over Z80** | Pure Z80 | The Z180's built-in MMU and UARTs significantly reduce the external glue logic required to emulate a complete computer, making the emulator's "Hardware" code much simpler than emulating discrete Z80 + SIO + MMU chips. |

