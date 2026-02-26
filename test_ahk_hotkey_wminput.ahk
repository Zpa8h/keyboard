#Requires AutoHotkey v2.0
#SingleInstance Force

; Test: do AHK native hotkeys suppress WM_INPUT, or does WM_INPUT still fire?
;
; Instructions:
;   1. Run this script
;   2. Press Numpad1 on ANY keyboard
;   3. Read the result:
;
;   BOTH tooltips appear  → AHK hotkeys don't suppress WM_INPUT
;                           The new architecture will work.
;
;   ONLY the hotkey tooltip → AHK hotkeys suppress WM_INPUT too.
;                              Need a completely different approach.

Persistent()

global g_msgWin := Gui(, "HotkeyWMInputTest")

entrySize := 8 + A_PtrSize
rid := Buffer(entrySize, 0)
NumPut("UShort", 1,             rid, 0)
NumPut("UShort", 6,             rid, 2)
NumPut("UInt",   0x100,         rid, 4)  ; RIDEV_INPUTSINK
NumPut("Ptr",    g_msgWin.Hwnd, rid, 8)
DllCall("RegisterRawInputDevices", "Ptr", rid, "UInt", 1, "UInt", entrySize)

OnMessage(0x00FF, HandleRawInput)

; AHK native hotkey — blocks Numpad1 the AHK way (not via DllCall hook)
Numpad1:: {
    ToolTip "Hotkey fired (key blocked by AHK)", , , 1
    SetTimer(() => ToolTip(,,,1), -3000)
}

HandleRawInput(wParam, lParam, *) {
    headerSize := 8 + 2 * A_PtrSize
    DllCall("GetRawInputData", "Ptr", lParam, "UInt", 0x10000003,
        "Ptr", 0, "UInt*", &size := 0, "UInt", headerSize)
    if !size
        return
    rawBuf := Buffer(size)
    DllCall("GetRawInputData", "Ptr", lParam, "UInt", 0x10000003,
        "Ptr", rawBuf, "UInt*", &size, "UInt", headerSize)
    if NumGet(rawBuf, 0, "UInt") != 1  ; keyboard only
        return
    flags := NumGet(rawBuf, headerSize + 2, "UShort")
    vKey  := NumGet(rawBuf, headerSize + 6, "UShort")
    if (flags & 1) || vKey != 97  ; Numpad1 key-down only (VK 97)
        return
    ToolTip "WM_INPUT fired for Numpad1 — architecture viable!", , , 2
    SetTimer(() => ToolTip(,,,2), -3000)
}
