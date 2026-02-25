#Requires AutoHotkey v2.0
#SingleInstance Force

; ─── Global state ──────────────────────────────────────────────────────────────
; g_kensingtonHandle = 0 means "not connected / disarmed" — hook is a no-op
global g_kensingtonHandle := 0
global g_hookID           := 0
global g_hookCB           := 0
; g_msgWin must be a persistent object (not GC'd) so the HWND stays valid
global g_msgWin           := Gui(, "KensingtonMacropad_Internal")

; ─── Entry point ───────────────────────────────────────────────────────────────
SetupRawInput()
FindKensington()
InstallHook()
UpdateTrayTip()
DebugDumpDevices()  ; one-time startup dump — shows all keyboard paths in a MsgBox

; ─── Raw Input registration ────────────────────────────────────────────────────
; Registers for keyboard WM_INPUT messages delivered to g_msgWin even when
; that window is not focused (RIDEV_INPUTSINK = 0x100).
SetupRawInput() {
    global g_msgWin

    ; sizeof(RAWINPUTDEVICE): usUsagePage(2) + usUsage(2) + dwFlags(4) + hwndTarget(ptr)
    entrySize := 8 + A_PtrSize
    rid := Buffer(entrySize, 0)
    NumPut("UShort", 1,             rid, 0)  ; usUsagePage = Generic Desktop Controls
    NumPut("UShort", 6,             rid, 2)  ; usUsage = Keyboard
    NumPut("UInt",   0x100,         rid, 4)  ; dwFlags = RIDEV_INPUTSINK
    NumPut("Ptr",    g_msgWin.Hwnd, rid, 8)  ; hwndTarget

    if !DllCall("RegisterRawInputDevices", "Ptr", rid, "UInt", 1, "UInt", entrySize)
        MsgBox "RegisterRawInputDevices failed (LastError=" A_LastError ")"

    OnMessage(0x00FF, HandleRawInput)    ; WM_INPUT
    OnMessage(0x0219, HandleDeviceChange) ; WM_DEVICECHANGE
}

; ─── Device discovery ──────────────────────────────────────────────────────────
; Scans all Raw Input keyboards for the Kensington VID/PID.
; Sets g_kensingtonHandle on success, 0 on failure.
FindKensington() {
    global g_kensingtonHandle
    g_kensingtonHandle := 0

    ; sizeof(RAWINPUTDEVICELIST): hDevice(ptr) + dwType(4) + alignment padding
    ; = A_PtrSize + 4 padded to 8 = A_PtrSize + 8 on 64-bit (= 16)
    entrySize := 8 + A_PtrSize
    DllCall("GetRawInputDeviceList", "Ptr", 0, "UInt*", &count := 0, "UInt", entrySize)
    if !count
        return

    listBuf := Buffer(entrySize * count)
    DllCall("GetRawInputDeviceList", "Ptr", listBuf, "UInt*", &count, "UInt", entrySize)

    loop count {
        offset  := (A_Index - 1) * entrySize
        handle  := NumGet(listBuf, offset,             "Ptr" )
        devType := NumGet(listBuf, offset + A_PtrSize, "UInt")

        if devType != 1  ; 1 = RIM_TYPEKEYBOARD
            continue

        ; Device name is a HID path that includes VID/PID — use that for stable ID.
        ; (Numeric device index changes between sessions; VID/PID does not.)
        DllCall("GetRawInputDeviceInfo", "Ptr", handle, "UInt", 0x20000007,
            "Ptr", 0, "UInt*", &nameLen := 0)
        nameBuf := Buffer(nameLen * 2)
        DllCall("GetRawInputDeviceInfo", "Ptr", handle, "UInt", 0x20000007,
            "Ptr", nameBuf, "UInt*", &nameLen)
        devName := StrGet(nameBuf, "UTF-16")

        if InStr(devName, "VID_05A4&PID_9865") {
            g_kensingtonHandle := handle
            return
        }
    }
}

; ─── LL Keyboard Hook ──────────────────────────────────────────────────────────
InstallHook() {
    global g_hookID, g_hookCB
    if g_hookID
        return
    g_hookCB := CallbackCreate(HookProc, "Fast", 3)
    g_hookID  := DllCall("SetWindowsHookEx", "Int", 13, "Ptr", g_hookCB,
        "Ptr", 0, "UInt", 0, "Ptr")
}

RemoveHook() {
    global g_hookID, g_hookCB
    if g_hookID {
        DllCall("UnhookWindowsHookEx", "Ptr", g_hookID)
        g_hookID := 0
    }
    if g_hookCB {
        CallbackFree(g_hookCB)
        g_hookCB := 0
    }
}

; Called by Windows on every system-wide keystroke.
; Strategy: block numpad VKs so they never reach applications.
;   - Injected keys (LLKHF_INJECTED 0x10) are from our own Send calls → let them through.
;   - Real numpad keys → block; WM_INPUT will fire and HandleRawInput decides what to do.
; When g_kensingtonHandle = 0 (Kensington not connected), the hook is a no-op.
HookProc(nCode, wParam, lParam) {
    global g_kensingtonHandle

    if nCode >= 0 && g_kensingtonHandle {
        vk    := NumGet(lParam + 0, "UInt")  ; KBDLLHOOKSTRUCT.vkCode  (offset 0)
        flags := NumGet(lParam + 8, "UInt")  ; KBDLLHOOKSTRUCT.flags   (offset 8)

        ; Pass injected keys through — these are our own re-injected main-keyboard keys.
        if flags & 0x10  ; LLKHF_INJECTED
            return DllCall("CallNextHookEx", "Ptr", 0, "Int", nCode,
                "Ptr", wParam, "Ptr", lParam, "Ptr")

        ; Block both key-down and key-up for numpad keys.
        ; (App never saw the key-down, so doesn't need an orphaned key-up.)
        if IsNumpadVK(vk)
            return 1  ; non-zero without CallNextHookEx = block
    }

    return DllCall("CallNextHookEx", "Ptr", 0, "Int", nCode, "Ptr", wParam, "Ptr", lParam, "Ptr")
}

IsNumpadVK(vk) {
    ; VK 96–111:  Numpad0–9, NumpadMult, NumpadAdd, NumpadSep, NumpadSub, NumpadDot, NumpadDiv
    ; VK 13:      Enter
    ; VK 8:       Backspace
    ; VK 144:     NumLock
    return (vk >= 96 && vk <= 111) || vk = 13 || vk = 8 || vk = 144
}

; ─── WM_INPUT handler ──────────────────────────────────────────────────────────
; IMPORTANT: No Critical directive here. The earlier combined-script failure was
; suspected to be caused by Critical blocking the AHK message pump, preventing
; WM_INPUT from being processed while the hook was active.
HandleRawInput(wParam, lParam, *) {
    global g_kensingtonHandle
    if !g_kensingtonHandle
        return

    ; sizeof(RAWINPUTHEADER): dwType(4) + dwSize(4) + hDevice(ptr) + wParam(ptr)
    headerSize := 8 + 2 * A_PtrSize

    ; First call: retrieve required buffer size
    DllCall("GetRawInputData",
        "Ptr",   lParam,
        "UInt",  0x10000003,   ; RID_INPUT
        "Ptr",   0,
        "UInt*", &size := 0,
        "UInt",  headerSize)
    if !size
        return

    ; Second call: retrieve the data
    rawBuf := Buffer(size)
    DllCall("GetRawInputData",
        "Ptr",   lParam,
        "UInt",  0x10000003,
        "Ptr",   rawBuf,
        "UInt*", &size,
        "UInt",  headerSize)

    ; RAWINPUTHEADER.dwType at offset 0 — must be 1 (RIM_TYPEKEYBOARD)
    if NumGet(rawBuf, 0, "UInt") != 1
        return

    ; RAWINPUTHEADER.hDevice at offset 8 (after two DWORDs)
    devHandle := NumGet(rawBuf, 8, "Ptr")

    ; RAWKEYBOARD fields (start at headerSize):
    ;   +0  MakeCode  (UShort)
    ;   +2  Flags     (UShort)  — RI_KEY_BREAK=0x1 (key-up), RI_KEY_E0=0x2 (extended)
    ;   +4  Reserved  (UShort)
    ;   +6  VKey      (UShort)
    flags := NumGet(rawBuf, headerSize + 2, "UShort")
    vKey  := NumGet(rawBuf, headerSize + 6, "UShort")

    ; Only act on key-down events (RI_KEY_BREAK is SET on key-up)
    if (flags & 1) || !IsNumpadVK(vKey)
        return

    ; Debug: show which device sent the key and whether it matched
    match := (devHandle = g_kensingtonHandle) ? "KENSINGTON" : "other kbd"
    ToolTip "WM_INPUT VK=" vKey " | dev=" devHandle " | " match
    SetTimer(() => ToolTip(), -2000)

    if devHandle = g_kensingtonHandle {
        ; Key came from the Kensington → run test macro
        RunMacro(vKey)
    } else {
        ; Key came from another keyboard (e.g. main keyboard numpad) → passthrough.
        ; Re-inject via Send so the hook sees LLKHF_INJECTED and lets it reach the app.
        ReInjectKey(vKey, !!(flags & 2))  ; RI_KEY_E0 = 0x2 = extended key
    }
}

; ─── Device plug / unplug ──────────────────────────────────────────────────────
HandleDeviceChange(wParam, lParam, *) {
    ; DBT_DEVICEARRIVAL = 0x8000, DBT_DEVICEREMOVECOMPLETE = 0x8004
    if wParam = 0x8000 || wParam = 0x8004 {
        Sleep(500)  ; let Windows finish registering/unregistering the device
        FindKensington()
        UpdateTrayTip()
    }
}

; ─── Main keyboard numpad passthrough ──────────────────────────────────────────
; Sends a synthesized keypress so the active application receives the numpad key
; as if the hook had never blocked it. AHK's Send sets LLKHF_INJECTED, which
; HookProc checks for and lets through.
ReInjectKey(vk, isExtended) {
    switch vk {
        case 96:  Send "{Numpad0}"
        case 97:  Send "{Numpad1}"
        case 98:  Send "{Numpad2}"
        case 99:  Send "{Numpad3}"
        case 100: Send "{Numpad4}"
        case 101: Send "{Numpad5}"
        case 102: Send "{Numpad6}"
        case 103: Send "{Numpad7}"
        case 104: Send "{Numpad8}"
        case 105: Send "{Numpad9}"
        case 106: Send "{NumpadMult}"
        case 107: Send "{NumpadAdd}"
        case 109: Send "{NumpadSub}"
        case 110: Send "{NumpadDot}"
        case 111: Send "{NumpadDiv}"
        case 13:
            if isExtended
                Send "{NumpadEnter}"  ; main keyboard numpad Enter (SC 11C, E0 flag)
            else
                Send "{Enter}"        ; regular Enter (SC 01C) — same as Kensington Enter
        case 8:   Send "{Backspace}"
        case 144: Send "{NumLock}"
    }
}

; ─── Test macros ───────────────────────────────────────────────────────────────
; Placeholder mappings — each Kensington key sends a letter for easy confirmation.
; Replace with real macros once the hook + WM_INPUT interaction is confirmed working.
;
; Numpad layout reference (standard grid, top→bottom left→right):
;   [NumLock=q] [/=r]  [*=s]  [-=t]
;   [7=u]       [8=v]  [9=w]  [+=x]
;   [4=y]       [5=z]  [6=A]
;   [1=B]       [2=C]  [3=D]  [Enter=E]
;   [0=F]              [.=G]
;   [Backspace=H]  (if key exists on device)
RunMacro(vk) {
    switch vk {
        case 144: Send "q"   ; Num Lock
        case 111: Send "r"   ; /
        case 106: Send "s"   ; *
        case 109: Send "t"   ; -
        case 103: Send "u"   ; 7
        case 104: Send "v"   ; 8
        case 105: Send "w"   ; 9
        case 107: Send "x"   ; +
        case 100: Send "y"   ; 4
        case 101: Send "z"   ; 5
        case 102: Send "A"   ; 6
        case 97:  Send "B"   ; 1
        case 98:  Send "C"   ; 2
        case 99:  Send "D"   ; 3
        case 13:  Send "E"   ; Enter (Kensington, SC 01C, non-extended)
        case 96:  Send "F"   ; 0
        case 110: Send "G"   ; .
        case 8:   Send "H"   ; Backspace
    }
}

; ─── Debug helpers (remove once working) ──────────────────────────────────────

; Shows ARMED / DISARMED in the tray icon tooltip.
UpdateTrayTip() {
    global g_kensingtonHandle
    if g_kensingtonHandle
        A_IconTip := "Kensington Macropad — ARMED (handle=" g_kensingtonHandle ")"
    else
        A_IconTip := "Kensington Macropad — disarmed (device not found)"
}

; Dumps every keyboard's HID path at startup so we can verify the VID/PID string.
; Shows a scrollable MsgBox — close it to continue; the script keeps running.
DebugDumpDevices() {
    entrySize := 8 + A_PtrSize
    DllCall("GetRawInputDeviceList", "Ptr", 0, "UInt*", &count := 0, "UInt", entrySize)
    if !count {
        MsgBox "GetRawInputDeviceList returned 0 devices."
        return
    }

    listBuf := Buffer(entrySize * count)
    DllCall("GetRawInputDeviceList", "Ptr", listBuf, "UInt*", &count, "UInt", entrySize)

    out := ""
    loop count {
        offset  := (A_Index - 1) * entrySize
        handle  := NumGet(listBuf, offset,             "Ptr" )
        devType := NumGet(listBuf, offset + A_PtrSize, "UInt")
        if devType != 1  ; skip non-keyboards
            continue

        DllCall("GetRawInputDeviceInfo", "Ptr", handle, "UInt", 0x20000007,
            "Ptr", 0, "UInt*", &nameLen := 0)
        nameBuf := Buffer(nameLen * 2)
        DllCall("GetRawInputDeviceInfo", "Ptr", handle, "UInt", 0x20000007,
            "Ptr", nameBuf, "UInt*", &nameLen)
        devName := StrGet(nameBuf, "UTF-16")

        matched := InStr(devName, "VID_05A4&PID_9865") ? "  ← KENSINGTON" : ""
        out .= "Handle: " handle "`nPath:   " devName matched "`n`n"
    }

    if !out
        out := "(no keyboard entries found)"

    dGui := Gui(, "Keyboard devices at startup")
    dGui.Add("Edit", "r20 w700 ReadOnly", out)
    dGui.Add("Button", "Default w100", "OK").OnEvent("Click", (*) => dGui.Destroy())
    dGui.Show()
}

; ─── Cleanup on exit ───────────────────────────────────────────────────────────
OnExit((*) => RemoveHook())
