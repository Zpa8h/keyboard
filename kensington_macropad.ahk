#Requires AutoHotkey v2.0
#SingleInstance Force

; ─── Architecture note ─────────────────────────────────────────────────────────
; Blocking a key in WH_KEYBOARD_LL (any form — DllCall hook or AHK native hotkey)
; also cancels WM_INPUT delivery for that key. Per-device routing while blocking
; is therefore impossible in pure user-space Windows.
;
; This script uses AHK's #HotIf to activate numpad hotkeys only while the
; Kensington is connected. Device detection uses GetRawInputDeviceList at
; startup and WM_DEVICECHANGE for plug/unplug.
;
; Known limitation: when armed, ALL keyboards' numpad keys trigger macros —
; not just the Kensington. The main keyboard's numpad is also captured.
; Regular Enter and Backspace are intentionally NOT hotkeyable (doing so would
; break them on all keyboards, since their scan codes are identical).

; ─── State ─────────────────────────────────────────────────────────────────────
global g_armed  := false
global g_msgWin := Gui(, "KensingtonMacropad_Internal")

; ─── Entry point ───────────────────────────────────────────────────────────────
; Script has hotkeys defined below, so Persistent() is not needed.
OnMessage(0x0219, HandleDeviceChange)  ; WM_DEVICECHANGE

if KensingtonPresent()
    Arm()
else
    Disarm()

; ─── Arm / disarm ──────────────────────────────────────────────────────────────
Arm() {
    global g_armed
    g_armed := true
    A_IconTip := "Kensington Macropad — ARMED"
}

Disarm() {
    global g_armed
    g_armed := false
    A_IconTip := "Kensington Macropad — disarmed (Kensington not found)"
}

; ─── Device detection ──────────────────────────────────────────────────────────
; Returns true if the Kensington (VID 05A4, PID 9865) is currently connected.
KensingtonPresent() {
    entrySize := 8 + A_PtrSize
    DllCall("GetRawInputDeviceList", "Ptr", 0, "UInt*", &count := 0, "UInt", entrySize)
    if !count
        return false

    listBuf := Buffer(entrySize * count)
    DllCall("GetRawInputDeviceList", "Ptr", listBuf, "UInt*", &count, "UInt", entrySize)

    loop count {
        offset  := (A_Index - 1) * entrySize
        handle  := NumGet(listBuf, offset,             "Ptr" )
        devType := NumGet(listBuf, offset + A_PtrSize, "UInt")
        if devType != 1  ; keyboard only
            continue

        DllCall("GetRawInputDeviceInfo", "Ptr", handle, "UInt", 0x20000007,
            "Ptr", 0, "UInt*", &nameLen := 0)
        nameBuf := Buffer(nameLen * 2)
        DllCall("GetRawInputDeviceInfo", "Ptr", handle, "UInt", 0x20000007,
            "Ptr", nameBuf, "UInt*", &nameLen)

        if InStr(StrGet(nameBuf, "UTF-16"), "VID_05A4&PID_9865")
            return true
    }
    return false
}

; ─── Device plug / unplug ──────────────────────────────────────────────────────
HandleDeviceChange(wParam, lParam, *) {
    ; DBT_DEVICEARRIVAL = 0x8000, DBT_DEVICEREMOVECOMPLETE = 0x8004
    if wParam = 0x8000 || wParam = 0x8004 {
        Sleep(500)  ; let Windows finish registering/unregistering
        if KensingtonPresent()
            Arm()
        else
            Disarm()
    }
}

; ─── Hotkeys ───────────────────────────────────────────────────────────────────
; Active only when g_armed is true (Kensington connected).
; When g_armed is false, all keys pass through to the active application normally.
;
; Enter and Backspace are deliberately excluded — their scan codes are shared with
; the main keyboard body keys, so hotkeying them would break regular typing.
; The Kensington's Enter (SC 01C) is identical to the main keyboard's Enter and
; will type Enter normally. NumpadEnter (SC 11C, extended) is safely capturable.
#HotIf (g_armed)

Numpad0::   RunMacro(96)
Numpad1::   RunMacro(97)
Numpad2::   RunMacro(98)
Numpad3::   RunMacro(99)
Numpad4::   RunMacro(100)
Numpad5::   RunMacro(101)
Numpad6::   RunMacro(102)
Numpad7::   RunMacro(103)
Numpad8::   RunMacro(104)
Numpad9::   RunMacro(105)
NumpadMult:: RunMacro(106)
NumpadAdd::  RunMacro(107)
NumpadSub::  RunMacro(109)
NumpadDot::  RunMacro(110)
NumpadDiv::  RunMacro(111)
NumpadEnter:: RunMacro(13)   ; extended Enter (SC 11C) — main keyboard numpad Enter only
NumLock::    RunMacro(144)

#HotIf

; ─── Test macros (replace with real macros once working) ───────────────────────
; Numpad layout reference (standard grid, top→bottom, left→right):
;   [NumLock=q] [/=r]   [*=s]  [-=t]
;   [7=u]       [8=v]   [9=w]  [+=x]
;   [4=y]       [5=z]   [6=A]
;   [1=B]       [2=C]   [3=D]  [NumpadEnter=E]
;   [0=F]               [.=G]
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
        case 13:  Send "E"   ; NumpadEnter (extended, SC 11C)
        case 96:  Send "F"   ; 0
        case 110: Send "G"   ; .
    }
}
