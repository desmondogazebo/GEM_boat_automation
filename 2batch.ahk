#Requires AutoHotkey v2.0
#SingleInstance Force
CoordMode("Mouse", "Screen")

gameExe := "GRANADO ESPADA M.exe"
gameWin := "ahk_exe " gameExe

; Activate game or exit.
if !WinExist(gameWin)
    ExitApp()

WinActivate(gameWin)

if !WinWaitActive(gameWin, , 3)
    ExitApp()

; Assign two 13-hour Lupala routes and one 15-hour Unguja route.
AssignShip(1, "Lupala")
AssignShip(2, "Unguja")
AssignShip(3, "Lupala")

ExitApp()


; Wait until the game is active.
WaitForGameActive() {
    global gameWin

    while !WinActive(gameWin) {
        ToolTip("Automation paused - waiting for Granado Espada...")
        Sleep(250)
    }

    ToolTip()
}


; Wait up to 5 minutes for the game to be idle, showing the status at the mouse.
WaitForGameIdle(timeoutMs := 300000) {
    started := A_TickCount

    loop {
        WaitForGameActive()

        if WaitForAnyGameText(["Processing Auto Combat", "Waiting", "Moving"], 0) {
            ToolTip()
            return true
        }

        remaining := timeoutMs - (A_TickCount - started)
        if (remaining <= 0) {
            ToolTip()
            return false
        }

        ToolTip("Game is not AFK - waiting up to " Ceil(remaining / 1000) "s for it to become idle...")
        Sleep(1000)
    }
}


; Count down only while the game is active.
GameSleep(ms) {
    global gameWin
    remaining := ms

    while (remaining > 0) {
        WaitForGameActive()
        started := A_TickCount
        Sleep(Min(50, remaining))

        if WinActive(gameWin)
            remaining := Max(0, remaining - (A_TickCount - started))
        else
            WaitForGameActive()
    }
}


GameSend(keys) {
    WaitForGameActive()
    Send(keys)
}


GameClick(x, y) {
    WaitForGameActive()
    viewport := GetGameViewport()
    Click(Round(viewport.X + x), Round(viewport.Y + y))
}


GameMove(x, y) {
    WaitForGameActive()
    viewport := GetGameViewport()
    MouseMove(Round(viewport.X + x), Round(viewport.Y + y))
}


GetGameViewport() {
    monitor := MonitorGetPrimary()
    MonitorGet(monitor, &left, &top, &right, &bottom)
    width := right - left
    height := bottom - top

    if (width <= 0 || height <= 0)
        throw Error("Could not determine the primary monitor size.")

    return {X: left, Y: top, Width: width, Height: height}
}


GameClickTextBounds(bounds) {
    GameClick(
        bounds.X + bounds.Width / 2,
        bounds.Y + bounds.Height / 2
    )
}


AssignShip(shipSlot, destination) {
    if (shipSlot < 1 || shipSlot > 3)
        throw Error("Ship slot must be 1, 2, or 3.")

    if (destination != "Lupala" && destination != "Unguja")
        throw Error("Destination must be Lupala (13h) or Unguja (15h).")

    if !WaitForGameIdle() {
        MsgBox("Game was not idle after waiting 5 minutes, exiting.")
        ExitApp()
    }

    GameSend("{Esc}")
    GameSend("g")

    tradeBounds := WaitForGameTextBounds("Trade")
    GameClickTextBounds(tradeBounds)

    costaLakeBounds := WaitForCostaLakeSlot(shipSlot)
    GameClickTextBounds(costaLakeBounds)
    enzaronBounds := WaitForGameTextBounds("Enzaron")

    prepareButtonBounds := WaitForNearbyGameTextBounds("Prepare for Trade", enzaronBounds)
    scrollX := prepareButtonBounds.X + prepareButtonBounds.Width / 2
    scrollY := prepareButtonBounds.Y + prepareButtonBounds.Height / 2 - 300
    GameMove(scrollX, scrollY)
    Loop 50
        GameSend("{WheelUp}")

    destinationBounds := WaitForGameTextBounds(destination)
    prepareBounds := WaitForNearbyGameTextBounds("Prepare for Trade", destinationBounds)
    GameClickTextBounds(prepareBounds)

    confirmBounds := WaitForGameTextBounds("Confirm")
    GameClickTextBounds(confirmBounds)

    dispatchBounds := WaitForGameTextBounds("Preparation For Dispatch")
    GameClickTextBounds(dispatchBounds)

    autoTeamBounds := WaitForGameTextBounds("Auto Team Setting")
    GameClickTextBounds(autoTeamBounds)

    startTradeBounds := WaitForGameTextBounds("Start Trade")
    GameClickTextBounds(startTradeBounds)

    WaitForGameTextBounds("Departure")
    GameSend("{Esc}")
    GameSend("z")
    WaitForAnyGameText(["Processing Auto Combat", "Waiting", "Moving"])
}


WaitForCostaLakeSlot(shipSlot) {
    return WaitForGameTextBounds("Costa Lake", 30000, false, shipSlot)
}

WaitForGameTextBounds(expectedText, timeoutMs := 30000, returnEmptyOnTimeout := false, targetIndex := 1) {
    activeElapsed := 0

    loop {
        WaitForGameActive()
        bounds := ReadGameOCR(expectedText, targetIndex)

        if IsObject(bounds)
            return bounds

        if (activeElapsed >= timeoutMs) {
            if returnEmptyOnTimeout
                return ""

            if (expectedText = "Costa Lake")
                throw Error("Timed out waiting for Costa Lake OCR match #" targetIndex ".")

            throw Error("Timed out waiting for game text bounds for '" expectedText "'.")
        }

        GameSleep(500)
        activeElapsed += 500
    }
}


WaitForAnyGameText(expectedTexts, timeoutMs := 30000) {
    activeElapsed := 0

    loop {
        WaitForGameActive()
        recognizedText := ReadGameOCR()

        for expectedText in expectedTexts {
            if InStr(recognizedText, expectedText)
                return true
        }

        if (activeElapsed >= timeoutMs)
            return false

        GameSleep(500)
        activeElapsed += 500
    }
}


WaitForNearbyGameTextBounds(expectedText, anchorBounds, timeoutMs := 30000) {
    activeElapsed := 0

    loop {
        boundsList := ReadGameOCR(expectedText, 1, true)
        anchorCenterX := anchorBounds.X + anchorBounds.Width / 2
        nearestBounds := ""
        nearestVerticalDistance := ""
        nearestHorizontalDistance := ""

        for bounds in boundsList {
            if (bounds.Y <= anchorBounds.Y + anchorBounds.Height)
                continue

            verticalDistance := bounds.Y - (anchorBounds.Y + anchorBounds.Height)
            horizontalDistance := Abs(bounds.X + bounds.Width / 2 - anchorCenterX)
            if (nearestVerticalDistance = ""
                || verticalDistance < nearestVerticalDistance
                || (verticalDistance = nearestVerticalDistance
                    && horizontalDistance < nearestHorizontalDistance)) {
                nearestBounds := bounds
                nearestVerticalDistance := verticalDistance
                nearestHorizontalDistance := horizontalDistance
            }
        }

        if IsObject(nearestBounds)
            return nearestBounds

        if (activeElapsed >= timeoutMs)
            throw Error("Timed out waiting for '" expectedText "' below anchor text.")

        GameSleep(500)
        activeElapsed += 500
    }
}


ReadGameOCR(targetText := "", targetIndex := 1, returnAllMatches := false) {
    global gameWin
    psScript := A_ScriptDir "\GameOCR.ps1"
    outputFile := A_Temp "\GameOCR.txt"

    if !FileExist(psScript)
        throw Error("Missing OCR helper: " psScript)

    loop {
        WaitForGameActive()
        try FileDelete(outputFile)
        viewport := GetGameViewport()

        command := 'powershell.exe -NoProfile -ExecutionPolicy Bypass'
            . ' -File "' psScript '"'
            . ' -X ' viewport.X
            . ' -Y ' viewport.Y
            . ' -Width ' viewport.Width
            . ' -Height ' viewport.Height
            . ' -OutputFile "' outputFile '"'

        if (targetText != "")
            command .= ' -TargetText "' targetText '" -TargetIndex ' targetIndex

        if returnAllMatches
            command .= ' -ReturnAllMatches'

        exitCode := RunWait(command, , "Hide")
        WaitForGameActive()

        if !FileExist(outputFile)
            throw Error("OCR helper did not produce output.")

        text := Trim(FileRead(outputFile, "UTF-8"))
        text := Trim(StrReplace(text, Chr(0xFEFF)))

        if (exitCode != 0 || InStr(text, "OCR_ERROR:") = 1)
            throw Error("OCR failed: " text)

        if !WinActive(gameWin)
            continue

        if (targetText != "") {
            if InStr(text, "NOT_FOUND")
                return returnAllMatches ? [] : ""

            if returnAllMatches {
                boundsList := []
                for line in StrSplit(text, "`n") {
                    line := Trim(line, "`r `t ")
                    if (line = "")
                        continue

                    parts := StrSplit(line, "|")
                    if (parts.Length != 4)
                        throw Error("OCR returned invalid text bounds: " line)

                    boundsList.Push({
                        X: parts[1] * 1 - viewport.X,
                        Y: parts[2] * 1 - viewport.Y,
                        Width: parts[3] * 1,
                        Height: parts[4] * 1
                    })
                }
                return boundsList
            }

            parts := StrSplit(text, "|")
            if (parts.Length != 4)
                throw Error("OCR returned invalid text bounds: " text)

            return {
                X: parts[1] * 1 - viewport.X,
                Y: parts[2] * 1 - viewport.Y,
                Width: parts[3] * 1,
                Height: parts[4] * 1
            }
        }

        return text
    }
}
