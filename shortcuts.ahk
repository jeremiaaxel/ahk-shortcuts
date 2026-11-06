#Requires AutoHotkey v2.0

; Home-Row Ergonomic Close: Win + W closes the active application window completely
#w::Send "!{F4}"

; Ctrl + Alt + Q locks your computer session
^!q::DllCall("user32.dll\LockWorkStation")

; ==============================================================================
; Alt + Tab HJKL Navigation 
; ==============================================================================
#HotIf WinActive("ahk_class XYANTaskbarWindow32") or WinActive("ahk_class MultitaskingViewFrame") or WinActive("ahk_class XamlExplorerHostIslandWindow")
*h::Send "{Blind}{Left}"
*j::Send "{Blind}{Down}"
*k::Send "{Blind}{Up}"
*l::Send "{Blind}{Right}"
#HotIf
