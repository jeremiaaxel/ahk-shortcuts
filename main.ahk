#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

; Force script to run with Admin rights to manage protected system windows
if not A_IsAdmin {
    Run('*RunAs "' A_ScriptFullPath '"')
    ExitApp()
}

; ------------------------------------------------------------------------------
; Load Component Modules
; ------------------------------------------------------------------------------
#Include "shortcuts.ahk"
#Include "window_manager.ahk"
#Include "language_engine.ahk"
