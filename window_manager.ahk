#Requires AutoHotkey v2.0

; ============================================================
; Window Manager v0.2.5
; Paired Tiling, Smart Resizing & Active Window Border
; ============================================================

global TilePair := 0
global AlmostMaxWindows := Map()
global BorderWindow := 0

; COLORREF format: 0x00BBGGRR
; Muted red: RGB(200, 102, 91)
global ActiveBorderColor := 0x005B66C8
global DefaultBorderColor := 0xFFFFFFFF

SetTimer(UpdateActiveBorder, 150)
OnExit(ResetActiveBorder)

TileNotice("Window Manager v0.2.5 Loaded")

; ------------------------------------------------------------
; Ctrl + Alt + Enter: Toggle Maximize / Restore
; ------------------------------------------------------------

^!Enter:: {
    global TilePair, AlmostMaxWindows

    hwnd := WinExist("A")
    if !hwnd
        return

    ; Maximizing or restoring a paired window breaks the pair.
    if IsObject(TilePair)
        && (hwnd = TilePair.first || hwnd = TilePair.second)
        TilePair := 0

    ; Discard the saved almost-maximized state.
    if AlmostMaxWindows.Has(hwnd)
        AlmostMaxWindows.Delete(hwnd)

    if (WinGetMinMax(hwnd) = 1)
        WinRestore(hwnd)
    else
        WinMaximize(hwnd)
}

; ------------------------------------------------------------
; Ctrl + Alt + \: Toggle Almost Maximize / Restore
; ------------------------------------------------------------

^!\::AlmostMaximize()

; ------------------------------------------------------------
; Standard Snapping: Ctrl + Alt + H/J/K/L
; ------------------------------------------------------------

^!h::MoveActiveWindow("left")
^!l::MoveActiveWindow("right")
^!k::MoveActiveWindow("top")
^!j::MoveActiveWindow("bottom")

; ------------------------------------------------------------
; Paired Tiling: Ctrl + Alt + Shift + H/J/K/L
; ------------------------------------------------------------

^!+h::CreateTilePair("left")
^!+l::CreateTilePair("right")
^!+k::CreateTilePair("top")
^!+j::CreateTilePair("bottom")

; ------------------------------------------------------------
; Smart Resizing: Ctrl + Alt + U/I/O/P
;
; U: Move horizontal edge/divider left
; P: Move horizontal edge/divider right
; O: Move vertical edge/divider up
; I: Move vertical edge/divider down
;
; Right-edge window: moves its left edge.
; Bottom-edge window: moves its top edge.
; ------------------------------------------------------------

^!u::SmartResize("horizontal", -0.05)
^!i::SmartResize("vertical", 0.05)
^!o::SmartResize("vertical", -0.05)
^!p::SmartResize("horizontal", 0.05)

; ------------------------------------------------------------
; Move Focus: Alt + H/J/K/L
; ------------------------------------------------------------

#HotIf !WinActive("ahk_class XYANTaskbarWindow32") and !WinActive("ahk_class MultitaskingViewFrame") and !WinActive("ahk_class XamlExplorerHostIslandWindow")

!h::FocusWindowDir("left")
!l::FocusWindowDir("right")
!k::FocusWindowDir("up")
!j::FocusWindowDir("down")

#HotIf

; ============================================================
; Active Window Border
; ============================================================

UpdateActiveBorder() {
    global BorderWindow, ActiveBorderColor, DefaultBorderColor

    active := WinExist("A")

    ; Only highlight visible windows with a title bar.
    if active {
        try {
            style := WinGetStyle(active)

            if !(style & 0x10000000)
                || !(style & 0x00C00000)
                || WinGetCloaked(active)
                active := 0
        } catch {
            active := 0
        }
    }

    if (active = BorderWindow)
        return

    ; Restore the previous window's border to the Windows default.
    if BorderWindow && WinExist(BorderWindow)
        SetWindowBorderColor(BorderWindow, DefaultBorderColor)

    BorderWindow := 0

    if active {
        if SetWindowBorderColor(active, ActiveBorderColor)
            BorderWindow := active
    }
}

SetWindowBorderColor(hwnd, color) {
    ; DWMWA_BORDER_COLOR = 34.
    ; Supported by Windows 11; applications can override it.
    try {
        result := DllCall(
            "dwmapi\DwmSetWindowAttribute",
            "Ptr", hwnd,
            "UInt", 34,
            "UInt*", color,
            "UInt", 4,
            "Int"
        )

        return result = 0
    } catch {
        return false
    }
}

ResetActiveBorder(exitReason, exitCode) {
    global BorderWindow, DefaultBorderColor

    SetTimer(UpdateActiveBorder, 0)

    if BorderWindow && WinExist(BorderWindow)
        SetWindowBorderColor(BorderWindow, DefaultBorderColor)
}

; ============================================================
; Almost Maximize
; ============================================================

AlmostMaximize() {
    global TilePair, AlmostMaxWindows

    hwnd := WinExist("A")
    if !hwnd
        return

    try {
        style := WinGetStyle(hwnd)

        ; Require a title bar and a resizable border.
        if !(style & 0x00C00000) || !(style & 0x00040000) {
            TileNotice("The active window cannot be resized.")
            return
        }

        ; Almost maximizing either paired window breaks the pair.
        if IsObject(TilePair)
            && (hwnd = TilePair.first || hwnd = TilePair.second)
            TilePair := 0

        ; Second press: restore the saved position and size.
        if AlmostMaxWindows.Has(hwnd) {
            saved := AlmostMaxWindows[hwnd]

            if (WinGetMinMax(hwnd) != 0)
                WinRestore(hwnd)

            WinMove(saved.x, saved.y, saved.w, saved.h, hwnd)

            if saved.wasMaximized
                WinMaximize(hwnd)

            AlmostMaxWindows.Delete(hwnd)
            return
        }

        wasMaximized := (WinGetMinMax(hwnd) = 1)

        if (WinGetMinMax(hwnd) != 0)
            WinRestore(hwnd)

        WinGetPos(&x, &y, &w, &h, hwnd)

        monitor := TileMonitor(hwnd)
        area := TileWorkArea(monitor)

        if !area {
            TileNotice("Could not get the monitor work area.")
            return
        }

        ; 90% of the work area, centered.
        newW := Round(area.W * 0.90)
        newH := Round(area.H * 0.90)
        newX := area.L + Round((area.W - newW) / 2)
        newY := area.T + Round((area.H - newH) / 2)

        AlmostMaxWindows[hwnd] := {
            x: x,
            y: y,
            w: w,
            h: h,
            wasMaximized: wasMaximized
        }

        WinMove(newX, newY, newW, newH, hwnd)
    } catch as err {
        TileNotice("Could not toggle almost maximize: " err.Message)
    }
}

; ============================================================
; Paired Tiling
; ============================================================

CreateTilePair(side) {
    global TilePair, AlmostMaxWindows

    active := WinExist("A")
    if !active || !IsTileCandidate(active) {
        TileNotice("The active window cannot be tiled.")
        return
    }

    monitor := TileMonitor(active)
    if !monitor {
        TileNotice("Could not identify the monitor.")
        return
    }

    WinGetPos(&ax, &ay, &aw, &ah, active)
    acx := ax + (aw / 2)
    acy := ay + (ah / 2)

    partner := 0
    bestScore := 9999999

    for hwnd in WinGetList() {
        if (hwnd = active || !WinExist(hwnd))
            continue

        if !IsTileCandidate(hwnd) || TileMonitor(hwnd) != monitor
            continue

        try {
            WinGetPos(&wx, &wy, &ww, &wh, hwnd)
        } catch {
            continue
        }

        wcx := wx + (ww / 2)
        wcy := wy + (wh / 2)

        dx := wcx - acx
        dy := wcy - acy

        score := 0
        isCorrectDir := false

        switch side {
            case "left":
                if (dx < -10) {
                    isCorrectDir := true
                    score := Abs(dx) + (Abs(dy) * 2)
                }

            case "right":
                if (dx > 10) {
                    isCorrectDir := true
                    score := Abs(dx) + (Abs(dy) * 2)
                }

            case "top":
                if (dy < -10) {
                    isCorrectDir := true
                    score := Abs(dy) + (Abs(dx) * 2)
                }

            case "bottom":
                if (dy > 10) {
                    isCorrectDir := true
                    score := Abs(dy) + (Abs(dx) * 2)
                }
        }

        if (isCorrectDir && score < bestScore) {
            bestScore := score
            partner := hwnd
        }
    }

    if !partner {
        TileNotice("No eligible window found in that direction.")
        return
    }

    axis := (side = "left" || side = "right")
        ? "horizontal"
        : "vertical"

    try {
        ; Sort by center coordinates, matching partner selection.
        WinGetPos(&x1, &y1, &w1, &h1, active)
        WinGetPos(&x2, &y2, &w2, &h2, partner)

        if (axis = "horizontal") {
            if (x1 + w1 / 2 < x2 + w2 / 2) {
                first := active
                second := partner
            } else {
                first := partner
                second := active
            }
        } else {
            if (y1 + h1 / 2 < y2 + h2 / 2) {
                first := active
                second := partner
            } else {
                first := partner
                second := active
            }
        }

        ; Tiling replaces any saved almost-maximized state.
        if AlmostMaxWindows.Has(first)
            AlmostMaxWindows.Delete(first)

        if AlmostMaxWindows.Has(second)
            AlmostMaxWindows.Delete(second)

        TilePair := {
            first: first,
            second: second,
            axis: axis,
            fraction: 0.5,
            monitor: monitor
        }

        if (WinGetMinMax(first) = 1)
            WinRestore(first)

        if (WinGetMinMax(second) = 1)
            WinRestore(second)

        ApplyTilePair()
        WinActivate(active)

        TileNotice("Tile Pair Created (" side ")")
    } catch as err {
        TilePair := 0
        TileNotice("Could not tile the windows: " err.Message
            "`nThe windows may have moved partially.")
    }
}

SmartResize(targetAxis, change) {
    global TilePair, AlmostMaxWindows

    active := WinExist("A")
    if !active
        return

    ; Discard the pair if either window no longer exists.
    if IsObject(TilePair) {
        if !WinExist(TilePair.first) || !WinExist(TilePair.second)
            TilePair := 0
    }

    isPaired := IsObject(TilePair)
        && (active = TilePair.first || active = TilePair.second)

    if isPaired {
        if (TilePair.axis != targetAxis) {
            TileNotice("Axis mismatch! This pair uses the "
                TilePair.axis " axis.")
            return
        }

        oldFraction := TilePair.fraction
        TilePair.fraction := Max(0.2, Min(0.8, oldFraction + change))

        try {
            ApplyTilePair()
        } catch as err {
            TilePair.fraction := oldFraction
            TileNotice("Could not resize the pair: " err.Message
                "`nThe windows may have moved partially.")
        }

        return
    }

    try {
        ; Do not resize minimized or maximized windows.
        if (WinGetMinMax(active) != 0)
            return

        monitor := TileMonitor(active)
        area := TileWorkArea(monitor)
        if !area
            return

        WinGetPos(&x, &y, &w, &h, active)

        ; Manual smart resizing replaces almost-maximized state.
        if AlmostMaxWindows.Has(active)
            AlmostMaxWindows.Delete(active)

        tolerance := 25

        if (targetAxis = "horizontal") {
            delta := Round(area.W * change)
            rightEdge := x + w

            ; Keep the right edge fixed and move the left edge.
            anchoredRight := Abs(rightEdge - (area.L + area.W)) <= tolerance
                && Abs(x - area.L) > tolerance

            if anchoredRight {
                maxWidth := Max(1, rightEdge - area.L)
                minWidth := Min(200, maxWidth)
                newWidth := Max(minWidth, Min(maxWidth, w - delta))
                newX := rightEdge - newWidth

                WinMove(newX, y, newWidth, h, active)
            } else {
                maxWidth := Max(1, area.L + area.W - x)
                minWidth := Min(200, maxWidth)
                newWidth := Max(minWidth, Min(maxWidth, w + delta))

                WinMove(x, y, newWidth, h, active)
            }
        } else {
            delta := Round(area.H * change)
            bottomEdge := y + h

            ; Keep the bottom edge fixed and move the top edge.
            anchoredBottom := Abs(bottomEdge - (area.T + area.H)) <= tolerance
                && Abs(y - area.T) > tolerance

            if anchoredBottom {
                maxHeight := Max(1, bottomEdge - area.T)
                minHeight := Min(200, maxHeight)
                newHeight := Max(minHeight, Min(maxHeight, h - delta))
                newY := bottomEdge - newHeight

                WinMove(x, newY, w, newHeight, active)
            } else {
                maxHeight := Max(1, area.T + area.H - y)
                minHeight := Min(200, maxHeight)
                newHeight := Max(minHeight, Min(maxHeight, h + delta))

                WinMove(x, y, w, newHeight, active)
            }
        }
    } catch as err {
        TileNotice("Could not resize the window: " err.Message)
    }
}

ApplyTilePair() {
    global TilePair

    area := TileWorkArea(TilePair.monitor)
    if !area
        throw Error("Could not get the monitor work area.")

    if (TilePair.axis = "horizontal") {
        firstWidth := Round(area.W * TilePair.fraction)
        secondWidth := area.W - firstWidth

        WinMove(area.L, area.T, firstWidth, area.H, TilePair.first)
        WinMove(
            area.L + firstWidth,
            area.T,
            secondWidth,
            area.H,
            TilePair.second
        )
    } else {
        firstHeight := Round(area.H * TilePair.fraction)
        secondHeight := area.H - firstHeight

        WinMove(area.L, area.T, area.W, firstHeight, TilePair.first)
        WinMove(
            area.L,
            area.T + firstHeight,
            area.W,
            secondHeight,
            TilePair.second
        )
    }
}

IsTileCandidate(hwnd) {
    try {
        style := WinGetStyle(hwnd)
        exStyle := WinGetExStyle(hwnd)

        ; Must be visible, have a title bar, and be resizable.
        if !(style & 0x10000000)
            return false

        if !(style & 0x00C00000) || !(style & 0x00040000)
            return false

        ; Exclude tool windows.
        if (exStyle & 0x00000080)
            return false

        if (WinGetMinMax(hwnd) = -1) || WinGetCloaked(hwnd)
            return false

        ; Exclude owned windows.
        owner := DllCall(
            "user32\GetWindow",
            "Ptr", hwnd,
            "UInt", 4,
            "Ptr"
        )

        if owner
            return false

        title := WinGetTitle(hwnd)
        if (title = "" || title = "Program Manager" || title = "Start")
            return false

        return true
    } catch {
        return false
    }
}

TileMonitor(hwnd) {
    return DllCall(
        "user32\MonitorFromWindow",
        "Ptr", hwnd,
        "UInt", 2,
        "Ptr"
    )
}

TileWorkArea(monitor) {
    if !monitor
        return 0

    info := Buffer(40, 0)
    NumPut("UInt", 40, info, 0)

    if !DllCall("user32\GetMonitorInfoW", "Ptr", monitor, "Ptr", info)
        return 0

    left := NumGet(info, 20, "Int")
    top := NumGet(info, 24, "Int")
    right := NumGet(info, 28, "Int")
    bottom := NumGet(info, 32, "Int")

    return {
        L: left,
        T: top,
        W: right - left,
        H: bottom - top
    }
}

TileNotice(message) {
    ToolTip(message)
    SetTimer(() => ToolTip(), -2500)
}

; ============================================================
; Standard Snapping
; ============================================================

MoveActiveWindow(direction) {
    global TilePair, AlmostMaxWindows

    hwnd := WinExist("A")
    if !hwnd || !(WinGetStyle(hwnd) & 0x00C00000)
        return

    ; Snapping either paired window breaks the pair.
    if IsObject(TilePair)
        && (hwnd = TilePair.first || hwnd = TilePair.second)
        TilePair := 0

    ; Snapping replaces the saved almost-maximized state.
    if AlmostMaxWindows.Has(hwnd)
        AlmostMaxWindows.Delete(hwnd)

    if (WinGetMinMax(hwnd) != 0)
        WinRestore(hwnd)

    WinGetPos(&wx, &wy, &ww, &wh, hwnd)

    monCount := MonitorGetCount()
    currentMon := 1
    monitors := []

    Loop monCount {
        MonitorGetWorkArea(A_Index, &mL, &mT, &mR, &mB)

        monitors.Push({
            Index: A_Index,
            L: mL,
            T: mT,
            R: mR,
            B: mB,
            W: mR - mL,
            H: mB - mT
        })

        wXCenter := wx + (ww / 2)
        wYCenter := wy + (wh / 2)

        if (wXCenter >= mL && wXCenter <= mR
            && wYCenter >= mT && wYCenter <= mB)
            currentMon := A_Index
    }

    cur := monitors[currentMon]

    isLeftHalf := (
        Abs(wx - cur.L) < 25
        && Abs(ww - (cur.W // 2)) < 25
    )

    isRightHalf := (
        Abs(wx - (cur.L + (cur.W // 2))) < 25
        && Abs(ww - (cur.W // 2)) < 25
    )

    isTopHalf := (
        Abs(wy - cur.T) < 25
        && Abs(wh - (cur.H // 2)) < 25
    )

    isBotHalf := (
        Abs(wy - (cur.T + (cur.H // 2))) < 25
        && Abs(wh - (cur.H // 2)) < 25
    )

    targetMon := currentMon
    targetSide := direction

    if (direction = "left") {
        if isLeftHalf {
            bestX := -999999

            Loop monCount {
                if (monitors[A_Index].R <= cur.L
                    && monitors[A_Index].R > bestX) {
                    bestX := monitors[A_Index].R
                    targetMon := A_Index
                }
            }

            targetSide := (targetMon != currentMon) ? "right" : "left"
        } else if isRightHalf {
            targetSide := "left"
        }
    } else if (direction = "right") {
        if isRightHalf {
            bestX := 999999

            Loop monCount {
                if (monitors[A_Index].L >= cur.R
                    && monitors[A_Index].L < bestX) {
                    bestX := monitors[A_Index].L
                    targetMon := A_Index
                }
            }

            targetSide := (targetMon != currentMon) ? "left" : "right"
        } else if isLeftHalf {
            targetSide := "right"
        }
    } else if (direction = "top") {
        if isTopHalf {
            bestY := -999999

            Loop monCount {
                if (monitors[A_Index].B <= cur.T
                    && monitors[A_Index].B > bestY) {
                    bestY := monitors[A_Index].B
                    targetMon := A_Index
                }
            }

            targetSide := (targetMon != currentMon) ? "bottom" : "top"
        } else if isBotHalf {
            targetSide := "top"
        }
    } else if (direction = "bottom") {
        if isBotHalf {
            bestY := 999999

            Loop monCount {
                if (monitors[A_Index].T >= cur.B
                    && monitors[A_Index].T < bestY) {
                    bestY := monitors[A_Index].T
                    targetMon := A_Index
                }
            }

            targetSide := (targetMon != currentMon) ? "top" : "bottom"
        } else if isTopHalf {
            targetSide := "bottom"
        }
    }

    t := monitors[targetMon]
    halfW := t.W // 2
    halfH := t.H // 2

    switch targetSide {
        case "left":
            WinMove(t.L, t.T, halfW, t.H, hwnd)

        case "right":
            WinMove(t.L + halfW, t.T, t.W - halfW, t.H, hwnd)

        case "top":
            WinMove(t.L, t.T, t.W, halfH, hwnd)

        case "bottom":
            WinMove(t.L, t.T + halfH, t.W, t.H - halfH, hwnd)
    }
}

; ============================================================
; Directional Focus
; ============================================================

FocusWindowDir(dir) {
    activeHwnd := WinActive("A")
    if !activeHwnd
        return

    try {
        WinGetPos(&ax, &ay, &aw, &ah, activeHwnd)
    } catch {
        return
    }

    acx := ax + (aw / 2)
    acy := ay + (ah / 2)

    bestHwnd := 0
    bestScore := 9999999

    for hwnd in WinGetList() {
        if (hwnd = activeHwnd || !WinExist(hwnd))
            continue

        try {
            style := WinGetStyle(hwnd)
            exStyle := WinGetExStyle(hwnd)
            cloaked := WinGetCloaked(hwnd)

            if !(style & 0x10000000) || (exStyle & 0x00000040) || cloaked
                continue

            title := WinGetTitle(hwnd)
            if (title = "" || title = "Program Manager" || title = "Start")
                continue

            WinGetPos(&wx, &wy, &ww, &wh, hwnd)
        } catch {
            continue
        }

        wcx := wx + (ww / 2)
        wcy := wy + (wh / 2)

        dx := wcx - acx
        dy := wcy - acy

        score := 0
        isCorrectDir := false

        switch dir {
            case "left":
                if (dx < -10) {
                    isCorrectDir := true
                    score := Abs(dx) + (Abs(dy) * 2)
                }

            case "right":
                if (dx > 10) {
                    isCorrectDir := true
                    score := Abs(dx) + (Abs(dy) * 2)
                }

            case "up":
                if (dy < -10) {
                    isCorrectDir := true
                    score := Abs(dy) + (Abs(dx) * 2)
                }

            case "down":
                if (dy > 10) {
                    isCorrectDir := true
                    score := Abs(dy) + (Abs(dx) * 2)
                }
        }

        if (isCorrectDir && score < bestScore) {
            bestScore := score
            bestHwnd := hwnd
        }
    }

    if bestHwnd {
        try WinActivate(bestHwnd)
    }
}

WinGetCloaked(hwnd) {
    cloaked := 0

    DllCall(
        "dwmapi\DwmGetWindowAttribute",
        "Ptr", hwnd,
        "UInt", 14,
        "UInt*", &cloaked,
        "UInt", 4
    )

    return cloaked
}