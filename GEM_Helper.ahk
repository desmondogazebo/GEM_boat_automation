
#Requires AutoHotkey v2.0
#SingleInstance Force
CoordMode("Mouse", "Screen")

gameExe := "GRANADO ESPADA M.exe"
gameWin := "ahk_exe " gameExe

; Pass --debug anywhere in the arguments to save annotated OCR screenshots
; (red boxes/lines) to %TEMP%\GameOCR_debug.png after every OCR read.
; Debug is on by default for now; pass --no-debug to turn it off.
debugOCR := true
scriptArgs := []
for arg in A_Args {
    if (arg = "--debug")
        debugOCR := true
    else if (arg = "--no-debug")
        debugOCR := false
    else
        scriptArgs.Push(arg)
}

; Usage: GEM.exe <function> [args...] [--debug]   e.g. GEM.exe sendShips 1
if (scriptArgs.Length < 1)
    ExitWithMessage("Usage: GEM <function> [args] [--debug]`nAvailable functions: sendShips <batchNumber>")

functionName := scriptArgs[1]
switch StrLower(functionName) {
    case "sendships":
        if (scriptArgs.Length < 2)
            ExitWithMessage("Usage: GEM sendShips <batchNumber>")
        sendShips(scriptArgs[2] + 0)
    default:
        ExitWithMessage("Unknown function: " functionName)
}

ExitApp()


ExitWithMessage(message) {
    MsgBox(message)
    ExitApp()
}


; Send the ships of a batch on their trade routes.
;   Batch 1: ships 1 and 3 on the first available route.
;   Batch 2: ships 1 and 3 to Lupala (13h), ship 2 to Unguja (15h).
sendShips(batchNumber) {
    ; Activate game or exit.
    if !WinExist(gameWin)
        ExitApp()

    WinActivate(gameWin)

    if !WinWaitActive(gameWin, , 3)
        ExitApp()

    switch batchNumber {
        case 1:
            AssignShip(1)
            AssignShip(3)
        case 2:
            AssignShip(1, "Lupala")
            AssignShip(2, "Unguja")
            AssignShip(3, "Lupala")
        default:
            ExitWithMessage("Unknown batch number: " batchNumber)
    }
}


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


; Send input only when the game is active.
GameSend(keys) {
    WaitForGameActive()
    Send(keys)
}


GameClick(x, y) {
    WaitForGameActive()
    viewport := GetGameViewport()
    Click(Round(viewport.X + x), Round(viewport.Y + y))
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


GameMove(x, y) {
    WaitForGameActive()
    viewport := GetGameViewport()
    MouseMove(Round(viewport.X + x), Round(viewport.Y + y))
}


; destination is "Lupala" (13h), "Unguja" (15h), or empty for the default (first) route.
AssignShip(shipSlot, destination := "") {
    if (shipSlot < 1 || shipSlot > 3)
        throw Error("Ship slot must be 1, 2, or 3.")

    if (destination != "" && destination != "Lupala" && destination != "Unguja")
        throw Error("Destination must be Lupala (13h) or Unguja (15h).")

    ; Confirm the game is idle before opening the faction menu.
    if !WaitForGameIdle() {
        MsgBox("Game was not idle after waiting 5 minutes, exiting.")
        ExitApp()
    }

    GameSend("{Esc}")
    GameSend("g")                   ; Open faction
    tradeBounds := WaitForGameTextBounds("Trade")

    GameClickTextBounds(tradeBounds)
    costaLakeBounds := WaitForCostaLakeSlot(shipSlot)

    GameClickTextBounds(costaLakeBounds)
    enzaronBounds := WaitForGameTextBounds("Enzaron")

    prepareBounds := WaitForNearbyGameTextBounds("Prepare for Trade", enzaronBounds)

    if (destination != "") {
        scrollX := prepareBounds.X + prepareBounds.Width / 2
        scrollY := prepareBounds.Y + prepareBounds.Height / 2 - 300
        GameMove(scrollX, scrollY)
        Loop 50
            GameSend("{WheelUp}")
        GameSleep(1000) ;this is to allow the game to finish scrolling before interacting with the destination

        destinationBounds := WaitForGameTextBounds(destination)
        prepareBounds := WaitForNearbyGameTextBounds("Prepare for Trade", destinationBounds)
    }

    GameClickTextBounds(prepareBounds)
    confirmBounds := WaitForGameTextBounds("Confirm", 30000, false, 2)
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
                expectedText .= " (match #" targetIndex ")"

            MsgBox("Expected " expectedText " on OCR but didn't see it.")
            ExitApp()
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
        nearestDistance := ""

        for bounds in boundsList {
            if (bounds.Y <= anchorBounds.Y + anchorBounds.Height)
                continue

            distance := Abs(bounds.X + bounds.Width / 2 - anchorCenterX)
            if (nearestDistance = "" || distance < nearestDistance) {
                nearestBounds := bounds
                nearestDistance := distance
            }
        }

        if IsObject(nearestBounds)
            return nearestBounds

        if (activeElapsed >= timeoutMs) {
            MsgBox("Expected " expectedText " on OCR but didn't see it.")
            ExitApp()
        }

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

        if debugOCR
            command .= ' -DebugMode'

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
