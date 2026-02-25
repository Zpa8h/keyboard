#Requires AutoHotkey v2.0
#SingleInstance Force

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
    }

    return DllCall("CallNextHookEx", "Ptr", 0, "Int", nCode, "Ptr", wParam, "Ptr", lParam, "Ptr")
}


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
