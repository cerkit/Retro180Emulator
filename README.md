# Retro180Emulator Technical Specification

## 1. System Overview

**Retro180Emulator** is a macOS-based emulator for the Zilog Z180 microprocessor, specifically tailored to emulate the [SC126 Z180 Motherboard](https://smallcomputercentral.com/projects/sc126-z180-motherboard/) architecture (with fallback/compatibility for SC131). It provides a comprehensive emulation environment including a Z180 CPU core, Memory Management Unit (MMU), and Serial I/O (ASCI).

The system is designed with a layered architecture, separating the core hardware simulation (`Core` & `Hardware` modules) from the user presentation layer (`UI` module). This ensures a clean separation of concerns, where the `Motherboard` acts as the central integration point, simulating the physical motherboard's bus and clock.

Key Design Philosophies:
-   **Accuracy driven by "Good Enough" Utility**: The emulation targets instruction-set compatibility sufficient to run the [RomWBW](https://smallcomputercentral.com/firmware/firmware-romwbw/) operating system (CP/M-80 compatible) rather than cycle-perfect hardware accuracy.
-   **Native macOS Integration**: Utilizes Swift and SwiftUI for a performant, modern user interface.
-   **Component Modularity**: Each hardware subsystem (CPU, MMU, I/O) is isolated, allowing for easier debugging.

---

## 2. Core Functional Sections

### 2.1 Central Processing Unit (CPU)
The heart of the emulator is the `Z180CPU` class. It emulates the Zilog Z180 instruction set, which is a superset of the Z80 with added instructions (e.g., `MLT` multiply) and integrated peripherals.

**Implementation Details:**
-   **Register State**: Implements full Z80/Z180 register sets, including main (`AF`, `BC`, `DE`, `HL`) and alternate (`AF'`, `BC'`, etc.) registers, plus index registers (`IX`, `IY`) and system registers (`SP`, `PC`, `I`, `R`).
-   **Execution Loop**: The `step()` function performs a fetch-decode-execute cycle. Complex instruction groups (`ED`, `CB`, `DD`, `FD` prefixes) are delegated to specific handler subroutines (`executeED`, `executeCB`, `executeIndex`).
-   **Interrupt Handling**: Supports Z80 interrupt modes 0, 1, and 2. It correctly interacts with the I/O dispatcher to retrieve interrupt vectors.
-   **Z180 Specifics**: Includes the 8-bit multiply (`MLT`) instruction and handles Z180-specific I/O instructions (`IN0`, `OUT0`, `OTIM`, `OTDM` families).

**Justification:**
A naive switch-case interpreter was chosen over a JIT compiler for simplicity and ease of debugging. Given modern host CPU speeds (3GHz+), emulating a <20MHz Z180 purely in Swift software is performant enough for real-time usage without the complexity of dynamic recompilation.

### 2.2 Memory Management Unit (MMU) & Persistence
The `Z180MMU` class emulates the built-in MMU of the Z180, extending the 16-bit (64KB) logical address space to a 20-bit (1MB) physical address space.

**Implementation Details:**
-   **Persistent RAM**: The emulator implements **Persistent RAM**. The 512KB RAM state is automatically saved to `ram.bin` in the user's Documents directory every 30 seconds and on application exit. This allows the guest OS (CP/M) state to survive application restarts.
-   **Address Translation**: Logic translates 16-bit logical addresses to 20-bit physical addresses using the Z180's `CBAR` (Common/Bank Area Register), `BBR` (Bank Base Register), and `CBR` (Common Base Register).
-   **Memory Map (SC126 Compatible)**:
    -   **ROM**: 0x00000 - 0x7FFFF (Lower 512KB)
    -   **RAM**: 0x80000 - 0xFFFFF (Upper 512KB)
    -   **Banking**: Supports Z180 standard Area 0, Bank Area, and Common Area 1.

### 2.3 I/O Subsystem
The `Z180IODispatcher` class manages the Z180's I/O address space (0x0000 - 0xFFFF).

**Implementation Details:**
-   **Internal Registers**: Z180 internal registers (ASCI control, MMU registers, DMAC, etc.) are mapped to a relocatable 64-byte window (default base 0x00, typically relocated to 0x40 or 0xC0 by BIOS). The dispatcher intercepts reads/writes to this range and routes them to `Z180ASCI`, `Z180MMU`, `Z180PRT` instances.

**Justification:**
The dynamic dispatch allows for flexible system configuration. By "relocating" internal registers in software (matching the hardware behavior of the Z180 I/O Control Register), the emulator can support BIOS versions that move the internal register block.

### 2.4 Peripherals

#### Async Serial Communication Interface (ASCI)
The `Z180ASCI` class emulates the Z180's on-chip UARTs (Channels 0 and 1).

**Implementation Details:**
-   **Buffering**: Uses `Data` queues for input and output buffering.
-   **Interrupts**: Implements `RIE` (Receive Interrupt Enable) logic.
-   **Register Mapping**: Supports both standard Z180 register offsets (0-4) and "Stride-2" mapping often used in SC126/SC131 hardware.

### 2.5 User Interface (UI)
The UI is built with **SwiftUI**, following the MVVM (Model-View-ViewModel) pattern.

**Implementation Details:**
-   **TerminalView**: Renders a 80x25 character grid.
-   **Smart File Injection**: A user-friendly feature to inject files into the running CP/M instance.
    -   **Restore Snapshot**: Loads a full 512KB binary image into RAM (replacing current state).
    -   **Inject File**: Uses an automated XMODEM transfer (via `B:XM R <filename>`) to safely transfer a file from the host macOS file system to the emulated CP/M filesystem without restarting.
-   **Input Handling**: Captures SwiftUI keyboard events.
-   **Auto-Save**: The UI observes the application `scenePhase` and triggers a RAM save when the app enters the background or terminates.

---

## 3. Data Flow Architecture

1.  **Clock Tick**: A `Timer` in `Motherboard` fires ~100Hz.
2.  **CPU Burst**: The CPU executes a burst of cycles (e.g., 5,000 instructions) to simulate real-time speed.
3.  **Peripheral Update**: PRT (Timers) are stepped based on the cycles consumed.
4.  **I/O Check**:
    -   **Output**: The UI checks `ASCI` output buffers and renders new characters to the screen.
    -   **Input**: Keystrokes from the UI are pushed to the `ASCI` input buffer.
5.  **Interrupt Service**: On the next CPU step, pending interrupts are detected and serviced.

## 4. Design Decisions & Justification

| Decision | Alternative Considered | Justification |
| :--- | :--- | :--- |
| **Swift / SwiftUI** | C++ / Qt / SDL | Leveraging native macOS technologies allows for a smaller codebase, better accessibility integration, and easier maintenance for a Mac-first tool. |
| **Persistent RAM** | File-based Disk Image | Instead of simulating sector-level disk I/O for a RAM disk, we simply persist the entire RAM content. This provides instant "resume" capability and simplifies the architecture. |
| **XMODEM Injection** | Host File System Mapping | Mapping a host folder to CP/M via a custom driver is complex. Automating the existing XMODEM tool (`XM.COM`) provides a robust way to import files using standard CP/M tooling. |
| **Timer-Based Loop** | Dedicated Thread | A simple `Timer` on the main runloop (or background dispatch) simplifies thread safety with the UI. |
| **Z180 over Z80** | Pure Z80 | The Z180's built-in MMU and UARTs significantly reduce the external glue logic required to emulate a complete computer. |
