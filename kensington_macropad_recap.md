# Kensington Macropad Project Recap

## Goal
Repurpose a **Kensington K72274 USB numpad/calculator** as a macro pad on a Windows work computer, without admin privileges.

---

## Hardware
- **Device:** Kensington K72274 Notebook Keypad/Calculator with USB Hub
- **VID:** `05A4` (Ortek Technology, OEM manufacturer for Kensington)
- **PID:** `9865`
- **Full device string:** `\\?\HID#VID_05A4&PID_9865#...#{884b96c3-56ef-11d1-bc8c-00a0c91405dd}`
- **Keys:** 19 keys — Numpad 0–9, operators, Enter, etc.
- The device registers as a **standard USB HID keyboard** (Type: Keyboard in Raw Input API)

---

## Constraints
- **No admin privileges** on work machine
- This rules out:
  - Kanata + Interception driver (kernel driver, needs admin install)
  - HIDMacros (abandoned, also needs driver)
- Must work entirely in **user space**

---

## Key Findings from Testing

### Key codes (confirmed via AHK Key History)
Both the Kensington and the main keyboard numpad send **identical VK and SC codes** for numpad digits:
- Numpad 1–9: VK 97–105
- Numpad 0: VK 96
- Enter: VK 13

The **only hardware difference** is the Enter key scan code:
- Kensington Enter: SC `01C` (regular Enter, `flags=0`)
- Main keyboard numpad Enter: SC `11C` (extended, `flags=2` in Raw Input — the `RI_KEY_E0` bit)
- Main keyboard regular Enter: SC `01C` (same as Kensington)

This means plain AHK hotkeys **cannot distinguish** between the two numpads, since they produce identical keycodes.

### Raw Input API
The Windows Raw Input API (`WM_INPUT`, `0x00FF`) **can** identify which physical device sent a keypress via the device handle embedded in each message.

- Registration: `RegisterRawInputDevices` with Usage Page 1, Usage 6 (keyboard), flag `RIDEV_INPUTSINK` (`0x100`) to receive input even when the AHK window isn't focused
- Device handle identification: compare `devHandle` from WM_INPUT header against the stored Kensington handle
- The Kensington handle is found at startup (and on plug/unplug) by scanning `GetRawInputDeviceList` for entries containing `VID_05A4&PID_9865`

**Important:** The numeric device index changes between sessions (a known Windows issue). Matching on VID/PID string is the stable approach.

### RAWKEYBOARD struct offsets (confirmed working)
After the RAWINPUTHEADER (`8 + 2*A_PtrSize` bytes):
```
headerSize + 0  = MakeCode  (UShort)
headerSize + 2  = Flags     (UShort)  ← RI_KEY_BREAK (0x1) = key up; RI_KEY_E0 (0x2) = extended
headerSize + 4  = Reserved  (UShort)
headerSize + 6  = VKey      (UShort)  ← the virtual key code
```

### RIDEV_NOLEGACY is not viable
`RIDEV_NOLEGACY` (`0x30`) cannot be combined with `RIDEV_INPUTSINK` (`0x100`) — they require opposite values for `hwndTarget` (non-zero vs zero respectively). Tested and confirmed: the combination registers successfully (returns 1, LastError 0) but NOLEGACY is silently ignored, keys still type normally.

### Hook + Raw Input conflict
The LL keyboard hook (`SetWindowsHookEx`, WH_KEYBOARD_LL = 13) and Raw Input interact in an unexpected way: **when the hook returns 1 to block a key, WM_INPUT is also suppressed**. This broke the initial architecture where both ran simultaneously.

The suspected culprit for an earlier test failure was `Critical` in the WM_INPUT handler blocking the AHK message pump. **This has not been fully confirmed yet** — the next test was to verify whether removing `Critical` fixes the combined hook + Raw Input approach.

---

## Architecture Plan

### Intended design
1. **On startup:** Scan for Kensington by VID/PID. If found, arm the system.
2. **WM_DEVICECHANGE (`0x0219`) listener:** Auto-arm/disarm when Kensington is plugged/unplugged (with 500ms sleep to let Windows finish registering).
3. **LL keyboard hook:** When armed, block all numpad keys from reaching applications.
4. **Raw Input handler:** Receives WM_INPUT for every keypress, identifies source device.
   - If from **Kensington** → run assigned macro
   - If from **main keyboard** → re-inject the key using `Send` (synthesized/injected keys have `LLKHF_INJECTED` flag `0x10` set, which the hook checks for and lets pass)
5. **Macro functions:** One function per Kensington key, easy to edit.

### Re-injection logic
```autohotkey
ReInjectKey(vKey, isExtended) {
    switch vKey {
        case 96:  Send "{Numpad0}"
        case 97:  Send "{Numpad1}"
        ; ... etc
        case 13:
            if isExtended
                Send "{NumpadEnter}"  ; main keyboard numpad Enter
            else
                Send "{Enter}"        ; regular Enter
    }
}
```

---

## Current Status
The last thing tested was a minimal script to verify whether removing `Critical` from `HandleRawInput` allows both the hook and Raw Input to coexist. That test was not run before the session ended.

### Next test to run
```autohotkey
#Requires AutoHotkey v2.0
#SingleInstance Force

global MyGui := Gui(, "Hook + RawInput Test")
MyGui.Add("Text", "w300 vLog", "Waiting...")
MyGui.Show()

ridSize := 8 + A_PtrSize
rid := Buffer(ridSize, 0)
NumPut("UShort", 1,          rid, 0)
NumPut("UShort", 6,          rid, 2)
NumPut("UInt",   0x100,      rid, 4)  ; RIDEV_INPUTSINK only
NumPut("Ptr",    MyGui.Hwnd, rid, 8)
DllCall("RegisterRawInputDevices", "Ptr", rid, "UInt", 1, "UInt", ridSize)

OnMessage(0x00FF, HandleRawInput)

hookCB := CallbackCreate(HookProc, "Fast", 3)
hookID := DllCall("SetWindowsHookEx", "Int", 13, "Ptr", hookCB, "Ptr", 0, "UInt", 0, "Ptr")

HookProc(nCode, wParam, lParam) {
    if (nCode >= 0) {
        vk := NumGet(lParam + 0, "UInt")
        if (vk >= 96 && vk <= 105) || vk = 13
            return 1
    }
    return DllCall("CallNextHookEx", "Ptr", 0, "Int", nCode, "Ptr", wParam, "Ptr", lParam, "Ptr")
}

; NOTE: No Critical directive - that was the suspected culprit
HandleRawInput(wParam, lParam, *) {
    DllCall("GetRawInputData", "Ptr", lParam, "UInt", 0x10000003, "Ptr", 0, "UInt*", &size := 0, "UInt", 8 + 2*A_PtrSize)
    rawBuf := Buffer(size)
    DllCall("GetRawInputData", "Ptr", lParam, "UInt", 0x10000003, "Ptr", rawBuf, "UInt*", &size, "UInt", 8 + 2*A_PtrSize)

    devType := NumGet(rawBuf, 4, "UInt")
    if (devType != 1)
        return

    headerSize := 8 + 2*A_PtrSize
    flags := NumGet(rawBuf, headerSize + 2, "UShort")
    vKey  := NumGet(rawBuf, headerSize + 6, "UShort")
    isKeyDown := !(flags & 1)
    if !isKeyDown
        return

    ToolTip "WM_INPUT received: VK=" vKey
    SetTimer(() => ToolTip(), -2000)
    MyGui["Log"].Value := "Last: VK=" vKey
}
```

**Expected outcomes:**
1. Numpad keys should be **blocked** from typing into other windows (hook working)
2. Tooltips should **still appear** when numpad keys are pressed (Raw Input still firing despite hook)

If both work → the `Critical` directive was the bug, and we can build the full script.
If tooltips don't appear → hook blocking WM_INPUT is a fundamental Windows behavior, not a `Critical` bug, and we need a different architecture.

---

## Files Produced
- `detect_devices.ahk` — lists all connected HID devices with handles, used to identify the Kensington
- `test_kensington.ahk` — confirms device detection, plug/unplug events, and Raw Input source identification (working)
- `kensington_macropad.ahk` — full script with hook + Raw Input + macros (detection/blocking works, macro dispatch broken due to hook/WM_INPUT conflict)

---

## AHK Version
All scripts use **AutoHotkey v2.0** syntax.

---

## Reference Links
- [RAWINPUTDEVICE structure](https://learn.microsoft.com/en-us/windows/win32/api/winuser/ns-winuser-rawinputdevice)
- [RAWKEYBOARD structure](https://learn.microsoft.com/en-us/windows/win32/api/winuser/ns-winuser-rawkeyboard)
- [RegisterRawInputDevices](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-registerrawinputdevices)
- [SetWindowsHookEx](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setwindowshookexw)
- [AHKHID library](https://github.com/jleb/AHKHID) — AHK wrapper for Raw Input (v1 syntax, may need porting)
