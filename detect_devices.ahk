#Requires AutoHotkey v2.0

; Lists all connected HID input devices and their hardware IDs
; Run this with the Kensington plugged in to find its VID/PID

output := ""

; Get count of raw input devices
DllCall("GetRawInputDeviceList", "Ptr", 0, "UInt*", &count := 0, "UInt", 8 + A_PtrSize)

; Allocate buffer for device list
bufSize := (8 + A_PtrSize) * count
buf := Buffer(bufSize)
DllCall("GetRawInputDeviceList", "Ptr", buf, "UInt*", &count, "UInt", 8 + A_PtrSize)

loop count {
    offset := (A_Index - 1) * (8 + A_PtrSize)
    handle := NumGet(buf, offset, "Ptr")
    devType := NumGet(buf, offset + A_PtrSize, "UInt")

    ; Get device name length
    DllCall("GetRawInputDeviceInfo", "Ptr", handle, "UInt", 0x20000007, "Ptr", 0, "UInt*", &nameLen := 0)

    ; Get device name
    nameBuf := Buffer(nameLen * 2)
    DllCall("GetRawInputDeviceInfo", "Ptr", handle, "UInt", 0x20000007, "Ptr", nameBuf, "UInt*", &nameLen)
    devName := StrGet(nameBuf, "UTF-16")

    ; Human-readable device type
    typeName := (devType = 0) ? "Mouse" : (devType = 1) ? "Keyboard" : "HID"

    ; Only show keyboards and HID devices (skip mice to reduce noise)
    if (devType = 1 || devType = 2)
        output .= "Type: " typeName "`nName: " devName "`n`n"
}

; Show in a scrollable window
MyGui := Gui(, "HID Device List")
MyGui.Add("Edit", "r30 w700 ReadOnly", output)
MyGui.Add("Button", "Default w100", "Copy All").OnEvent("Click", (*) => A_Clipboard := output)
MyGui.Show()