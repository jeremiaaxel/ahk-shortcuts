#Requires AutoHotkey v2.0

; Initialize the OSD overlay window globally
global langGui := Gui("-Caption +AlwaysOnTop +Owner +ToolWindow +LastFound")
langGui.BackColor := "1F1F1F"
langGui.SetFont("s48 w700 cWhite", "Segoe UI")
global langText := langGui.Add("Text", "Center w260 y25", "")
WinSetTransparent(0, langGui.Hwnd)

; Set up a background monitor loop to watch for language changes
SetTimer(CheckLanguageAndForceHiragana, 250)

; Ctrl + Space cycles layout indices and triggers the OSD indicator
^Space:: {
    hwnd := WinExist("A")
    if hwnd {
        PostMessage(0x50, 1, 0,, hwnd)
        Sleep(100) ; Increased slightly for stable thread handoff
        CheckLanguageAndForceHiragana(true)
    }
}

; Linux-Style Panic Reset: Press Alt + Escape to cleanly force Hiragana [あ]
!Esc:: {
    SetImeModeToHiragana()
    ShowLanguageOSD("あ")
}

CheckLanguageAndForceHiragana(forceOSD := false) {
    static lastLang := 0
    activeHwnd := WinActive("A")
    if !activeHwnd
        return
        
    threadId := DllCall("user32.dll\GetWindowThreadProcessId", "Ptr", activeHwnd, "UInt", 0, "UInt")
    if !threadId
        return
        
    currentLayout := DllCall("user32.dll\GetKeyboardLayout", "UInt", threadId, "Ptr")
    currentLang := currentLayout & 0xFFFF
    
    if (currentLang = 0x0411) { ; Japanese Layout
        if (lastLang != 0x0411) {
            SetImeModeToHiragana()
            ShowLanguageOSD("あ")
        } else if (forceOSD) {
            ShowLanguageOSD("あ")
        }
    } else { ; English Layout
        if (lastLang == 0x0411 || forceOSD) {
            ShowLanguageOSD("ENG")
        }
    }
    lastLang := currentLang
}

SetImeModeToHiragana() {
    hwnd := WinActive("A")
    if !hwnd
        return
    
    ; 1. Try native AHK ControlSend virtual key to switch IME mode directly to Hiragana
    ; This bypasses thread context locks that break traditional ImmGetDefaultIMEWnd calls.
    oldKeyDelay := A_KeyDelay
    SetKeyDelay(-1)
    
    ; Sends the standard VK code for Hiragana/Katakana key (0xF2) directly to the window thread
    ControlSend("{vkF2}",, "ahk_id " hwnd)
    
    ; 2. Fallback to API Message Injection with explicit UI target thread matching
    imeHwnd := DllCall("imm32\ImmGetDefaultIMEWnd", "Ptr", hwnd, "Ptr")
    if imeHwnd {
        ; Set Open Status to true (0x0006, 1)
        DllCall("user32\SendMessage", "Ptr", imeHwnd, "UInt", 0x0283, "Ptr", 0x0006, "Ptr", 1)
        ; Set Conversion Mode to Hiragana (0x0002, 0x19)
        DllCall("user32\SendMessage", "Ptr", imeHwnd, "UInt", 0x0283, "Ptr", 0x0002, "Ptr", 0x19)
    }
    
    SetKeyDelay(oldKeyDelay)
}

ShowLanguageOSD(textToDisplay) {
    global langGui, langText
    SetTimer(FadeOutOSD, 0)
    langText.Value := textToDisplay
    
    hwndActive := WinExist("A")
    monitorNum := hwndActive ? DllCall("User32\MonitorFromWindow", "Ptr", hwndActive, "UInt", 2, "Ptr") : DllCall("User32\MonitorFromPoint", "Int64", 0, "UInt", 1, "Ptr")
    
    varStruct := Buffer(40)
    NumPut("UInt", 40, varStruct)
    DllCall("User32\GetMonitorInfo", "Ptr", monitorNum, "Ptr", varStruct)
    
    mL := NumGet(varStruct, 4, "Int"), mT := NumGet(varStruct, 8, "Int")
    mR := NumGet(varStruct, 12, "Int"), mB := NumGet(varStruct, 16, "Int")
    mW := mR - mL, mH := mB - mT
    
    gW := 260, gH := 140
    gX := mL + ((mW - gW) // 2)
    gY := mT + ((mH - gH) // 2)
    
    WinSetTransparent(220, langGui.Hwnd)
    langGui.Show("X" gX " Y" gY " W" gW " H" gH " NoActivate")
    SetTimer(FadeOutOSD, -1000)
}

FadeOutOSD() {
    global langGui
    currentAlpha := 220
    Loop 11 {
        currentAlpha -= 20
        if (currentAlpha < 0)
            currentAlpha := 0
        WinSetTransparent(currentAlpha, langGui.Hwnd)
        Sleep(15)
    }
    langGui.Hide()
}

