#Requires AutoHotkey v2.0
#SingleInstance Force

<<<<<<< claude/review-project-y3r5p
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
=======
KENSINGTON_ID := "VID_05A4&PID_9865"
global kensingtonHandle := 0
global kensingtonConnected := false
global hookID := 0
global hookCallback := 0

; --- Create GUI first ---
global MyGui := Gui(, "Kensington Macro Pad")
MyGui.Add("Text", "w300 vStatusText", "")
MyGui.Add("Text", "w300 vEventLog", "Waiting for input...")
MyGui.Show()

; --- Startup ---
kensingtonHandle := FindDevice(KENSINGTON_ID)
kensingtonConnected := (kensingtonHandle != 0)
RegisterForRawInput()
OnMessage(0x00FF, HandleRawInput)
OnMessage(0x0219, HandleDeviceChange)

if kensingtonConnected
    InstallHook()

UpdateStatus()


; =====================================================
; MACROS - edit these functions to do what you want
; Each corresponds to a key on the Kensington pad
; =====================================================

RunMacro(vKey, isExtended) {
    switch vKey {
        case 97:  MacroNumpad1()
        case 98:  MacroNumpad2()
        case 99:  MacroNumpad3()
        case 100: MacroNumpad4()
        case 101: MacroNumpad5()
        case 102: MacroNumpad6()
        case 103: MacroNumpad7()
        case 104: MacroNumpad8()
        case 105: MacroNumpad9()
        case 96:  MacroNumpad0()
        case 13:  MacroEnter()
    }
}

MacroNumpad1() {
    ToolTip "Macro: Numpad1"
    SetTimer(() => ToolTip(), -2000)
}
MacroNumpad2() {
    ToolTip "Macro: Numpad2"
    SetTimer(() => ToolTip(), -2000)
}
MacroNumpad3() {
    ToolTip "Macro: Numpad3"
    SetTimer(() => ToolTip(), -2000)
}
MacroNumpad4() {
    ToolTip "Macro: Numpad4"
    SetTimer(() => ToolTip(), -2000)
}
MacroNumpad5() {
    ToolTip "Macro: Numpad5"
    SetTimer(() => ToolTip(), -2000)
}
MacroNumpad6() {
    ToolTip "Macro: Numpad6"
    SetTimer(() => ToolTip(), -2000)
}
MacroNumpad7() {
    ToolTip "Macro: Numpad7"
    SetTimer(() => ToolTip(), -2000)
}
MacroNumpad8() {
    ToolTip "Macro: Numpad8"
    SetTimer(() => ToolTip(), -2000)
}
MacroNumpad9() {
    ToolTip "Macro: Numpad9"
    SetTimer(() => ToolTip(), -2000)
}
MacroNumpad0() {
    ToolTip "Macro: Numpad0"
    SetTimer(() => ToolTip(), -2000)
}
MacroEnter() {
    ToolTip "Macro: Enter"
    SetTimer(() => ToolTip(), -2000)
}

; =====================================================


; -------------------------------------------------------
; Install low-level keyboard hook
; -------------------------------------------------------
InstallHook() {
    global hookID, hookCallback
    if hookID  ; already installed
        return
    hookCallback := CallbackCreate(LLKeyboardProc, "Fast", 3)
    hookID := DllCall("SetWindowsHookEx", "Int", 13, "Ptr", hookCallback, "Ptr", 0, "UInt", 0, "Ptr")
}

RemoveHook() {
    global hookID, hookCallback
    if hookID {
        DllCall("UnhookWindowsHookEx", "Ptr", hookID)
        hookID := 0
    }
    if hookCallback {
        CallbackFree(hookCallback)
        hookCallback := 0
    }
}


; -------------------------------------------------------
; Low-level keyboard hook procedure
; Blocks numpad keys when Kensington is connected
; Lets injected keys pass through (our re-injected main kb keys)
; -------------------------------------------------------
LLKeyboardProc(nCode, wParam, lParam) {
    static LLKHF_INJECTED := 0x10

    if (nCode >= 0 && kensingtonConnected) {
        vk    := NumGet(lParam + 0, "UInt")
        flags := NumGet(lParam + 8, "UInt")

        ; Injected keys are ones we re-sent ourselves - let them pass
        if (flags & LLKHF_INJECTED)
            return DllCall("CallNextHookEx", "Ptr", 0, "Int", nCode, "Ptr", wParam, "Ptr", lParam, "Ptr")

        ; Block all numpad keys and Enter - Raw Input will dispatch them
        isNumpad := (vk >= 96 && vk <= 105) || vk = 13
        if isNumpad
            return 1
>>>>>>> main
    }

    return DllCall("CallNextHookEx", "Ptr", 0, "Int", nCode, "Ptr", wParam, "Ptr", lParam, "Ptr")
}

<<<<<<< claude/review-project-y3r5p
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
    }
}

; ─── Main keyboard numpad passthrough ──────────────────────────────────────────
; Sends a synthesized keypress so the active application receives the numpad key
; as if the hook had never blocked it. AHK's Send sets LLKHF_INJECTED, which
; HookProc checks for and lets through.
ReInjectKey(vk, isExtended) {
    switch vk {
=======

; -------------------------------------------------------
; Raw Input handler
; Identifies which device sent the key and dispatches accordingly
; -------------------------------------------------------
HandleRawInput(wParam, lParam, *) {
    global kensingtonHandle
    Critical

    DllCall("GetRawInputData", "Ptr", lParam, "UInt", 0x10000003, "Ptr", 0, "UInt*", &size := 0, "UInt", 8 + 2*A_PtrSize)
    rawBuf := Buffer(size)
    DllCall("GetRawInputData", "Ptr", lParam, "UInt", 0x10000003, "Ptr", rawBuf, "UInt*", &size, "UInt", 8 + 2*A_PtrSize)

    ; Only handle keyboards (type 1)
    devType := NumGet(rawBuf, 4, "UInt")
    if (devType != 1)
        return

    devHandle  := NumGet(rawBuf, 8, "Ptr")
    headerSize := 8 + 2*A_PtrSize
    flags      := NumGet(rawBuf, headerSize + 2, "UShort")
    vKey       := NumGet(rawBuf, headerSize + 6, "UShort")

    isNumpad   := (vKey >= 96 && vKey <= 105) || vKey = 13
    isKeyDown  := !(flags & 1)   ; RI_KEY_BREAK = key up event
    isExtended := !!(flags & 2)  ; RI_KEY_E0 = extended key (main kb numpad Enter)

    ; Only process numpad key-down events
    if (!isNumpad || !isKeyDown)
        return

    if (devHandle = kensingtonHandle) {
        ; From Kensington - run the assigned macro
        MyGui["EventLog"].Value := "Kensington → VK" vKey
        RunMacro(vKey, isExtended)
    } else {
        ; From main keyboard - re-inject so it behaves normally
        MyGui["EventLog"].Value := "Main KB passthrough → VK" vKey
        ReInjectKey(vKey, isExtended)
    }
}


; -------------------------------------------------------
; Re-inject a key as a synthesized keypress
; The hook sees the LLKHF_INJECTED flag and lets it pass
; -------------------------------------------------------
ReInjectKey(vKey, isExtended) {
    switch vKey {
>>>>>>> main
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
<<<<<<< claude/review-project-y3r5p
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

; ─── Cleanup on exit ───────────────────────────────────────────────────────────
OnExit((*) => RemoveHook())
=======
        case 13:
            ; Main numpad Enter has the extended flag set (RI_KEY_E0)
            ; Regular Enter does not
            if isExtended
                Send "{NumpadEnter}"
            else
                Send "{Enter}"
    }
}


; -------------------------------------------------------
; Handle USB plug/unplug events (WM_DEVICECHANGE)
; -------------------------------------------------------
HandleDeviceChange(wParam, lParam, *) {
    global kensingtonConnected, kensingtonHandle
    Sleep 500  ; let Windows finish registering/unregistering
    newHandle := FindDevice(KENSINGTON_ID)
    kensingtonHandle    := newHandle
    kensingtonConnected := (newHandle != 0)

    if kensingtonConnected
        InstallHook()
    else
        RemoveHook()

    UpdateStatus()
}


; -------------------------------------------------------
; Find a device by VID/PID string, return its handle or 0
; -------------------------------------------------------
FindDevice(targetID) {
    DllCall("GetRawInputDeviceList", "Ptr", 0, "UInt*", &count := 0, "UInt", 8 + A_PtrSize)
    buf := Buffer((8 + A_PtrSize) * count)
    DllCall("GetRawInputDeviceList", "Ptr", buf, "UInt*", &count, "UInt", 8 + A_PtrSize)

    loop count {
        offset := (A_Index - 1) * (8 + A_PtrSize)
        handle := NumGet(buf, offset, "Ptr")

        DllCall("GetRawInputDeviceInfo", "Ptr", handle, "UInt", 0x20000007, "Ptr", 0, "UInt*", &nameLen := 0)
        nameBuf := Buffer(nameLen * 2)
        DllCall("GetRawInputDeviceInfo", "Ptr", handle, "UInt", 0x20000007, "Ptr", nameBuf, "UInt*", &nameLen)
        devName := StrGet(nameBuf, "UTF-16")

        if InStr(devName, targetID)
            return handle
    }
    return 0
}


; -------------------------------------------------------
; Register to receive raw keyboard input messages
; -------------------------------------------------------
RegisterForRawInput() {
    global MyGui
    ridSize := 8 + A_PtrSize
    rid := Buffer(ridSize, 0)
    NumPut("UShort", 1,          rid, 0)  ; Usage Page (1 = generic desktop)
    NumPut("UShort", 6,          rid, 2)  ; Usage (6 = keyboard)
    NumPut("UInt",   0x100,      rid, 4)  ; RIDEV_INPUTSINK: receive even when unfocused
    NumPut("Ptr",    MyGui.Hwnd, rid, 8)  ; Target window
    DllCall("RegisterRawInputDevices", "Ptr", rid, "UInt", 1, "UInt", ridSize)
}


; -------------------------------------------------------
; Update the status line in the GUI
; -------------------------------------------------------
UpdateStatus() {
    global MyGui
    if !IsSet(MyGui)
        return
    status := kensingtonConnected ? "✓ Kensington CONNECTED" : "✗ Kensington NOT connected"
    MyGui["StatusText"].Value := status
}
>>>>>>> main
