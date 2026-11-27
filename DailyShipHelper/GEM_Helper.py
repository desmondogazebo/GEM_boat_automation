import argparse
import ctypes
import os
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path

from ctypes import wintypes


GAME_EXE = "GRANADO ESPADA M.exe"
OCR_TIMEOUT_SECONDS = 60
DEFAULT_IDLE_TIMEOUT_SECONDS = 300
CONFIRM_OFFSET_X = 290
CREATE_NO_WINDOW = 0x08000000
PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
GW_OWNER = 4
SW_RESTORE = 9
KEYEVENTF_KEYUP = 0x0002
MOUSEEVENTF_LEFTDOWN = 0x0002
MOUSEEVENTF_LEFTUP = 0x0004
MOUSEEVENTF_WHEEL = 0x0800
WHEEL_DELTA = 120


class AutomationError(RuntimeError):
    pass


@dataclass(frozen=True)
class Bounds:
    x: int
    y: int
    width: int
    height: int

    @property
    def center_x(self) -> float:
        return self.x + self.width / 2

    @property
    def center_y(self) -> float:
        return self.y + self.height / 2


@dataclass(frozen=True)
class GameWindow:
    handle: int
    process_id: int


@dataclass(frozen=True)
class MonitorBounds:
    left: int
    top: int
    right: int
    bottom: int

    @property
    def width(self) -> int:
        return self.right - self.left

    @property
    def height(self) -> int:
        return self.bottom - self.top


if os.name == "nt":
    _user32 = ctypes.WinDLL("user32", use_last_error=True)
    _kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    _window_enum_callback = ctypes.WINFUNCTYPE(
        wintypes.BOOL, wintypes.HWND, wintypes.LPARAM
    )

    _user32.EnumWindows.argtypes = [
        _window_enum_callback,
        wintypes.LPARAM,
    ]
    _user32.EnumWindows.restype = wintypes.BOOL
    _user32.GetWindowThreadProcessId.argtypes = [
        wintypes.HWND,
        ctypes.POINTER(wintypes.DWORD),
    ]
    _user32.GetWindowThreadProcessId.restype = wintypes.DWORD
    _user32.IsWindowVisible.argtypes = [wintypes.HWND]
    _user32.IsWindowVisible.restype = wintypes.BOOL
    _user32.GetWindow.argtypes = [wintypes.HWND, wintypes.UINT]
    _user32.GetWindow.restype = wintypes.HWND
    _user32.GetForegroundWindow.restype = wintypes.HWND
    _user32.ShowWindow.argtypes = [wintypes.HWND, ctypes.c_int]
    _user32.SetForegroundWindow.argtypes = [wintypes.HWND]
    _user32.SetForegroundWindow.restype = wintypes.BOOL
    _user32.SetCursorPos.argtypes = [ctypes.c_int, ctypes.c_int]
    _user32.SetCursorPos.restype = wintypes.BOOL
    _user32.keybd_event.argtypes = [
        wintypes.BYTE,
        wintypes.BYTE,
        wintypes.DWORD,
        ctypes.c_size_t,
    ]
    _user32.mouse_event.argtypes = [
        wintypes.DWORD,
        wintypes.LONG,
        wintypes.LONG,
        wintypes.DWORD,
        ctypes.c_size_t,
    ]
    _kernel32.OpenProcess.argtypes = [
        wintypes.DWORD,
        wintypes.BOOL,
        wintypes.DWORD,
    ]
    _kernel32.OpenProcess.restype = wintypes.HANDLE
    _kernel32.QueryFullProcessImageNameW.argtypes = [
        wintypes.HANDLE,
        wintypes.DWORD,
        wintypes.LPWSTR,
        ctypes.POINTER(wintypes.DWORD),
    ]
    _kernel32.QueryFullProcessImageNameW.restype = wintypes.BOOL
    _kernel32.CloseHandle.argtypes = [wintypes.HANDLE]
    _kernel32.CloseHandle.restype = wintypes.BOOL
else:
    _user32 = None
    _kernel32 = None


class MonitorInfo(ctypes.Structure):
    _fields_ = [
        ("cbSize", wintypes.DWORD),
        ("rcMonitor", wintypes.RECT),
        ("rcWork", wintypes.RECT),
        ("dwFlags", wintypes.DWORD),
    ]


def _require_windows() -> None:
    if os.name != "nt":
        raise AutomationError("Daily Ship Helper can only run on Windows.")


def _process_image_name(process_id: int) -> str | None:
    process = _kernel32.OpenProcess(
        PROCESS_QUERY_LIMITED_INFORMATION, False, process_id
    )
    if not process:
        return None

    try:
        image_path = ctypes.create_unicode_buffer(32768)
        path_length = wintypes.DWORD(len(image_path))
        if not _kernel32.QueryFullProcessImageNameW(
            process, 0, image_path, ctypes.byref(path_length)
        ):
            return None
        return Path(image_path.value).name
    finally:
        _kernel32.CloseHandle(process)


def find_game_window() -> GameWindow:
    _require_windows()
    matching_windows: list[GameWindow] = []

    def visit_window(handle: int, _parameter: int) -> bool:
        del _parameter
        if not _user32.IsWindowVisible(handle):
            return True
        if _user32.GetWindow(handle, GW_OWNER):
            return True

        process_id = wintypes.DWORD()
        _user32.GetWindowThreadProcessId(handle, ctypes.byref(process_id))
        image_name = _process_image_name(process_id.value)
        if image_name and image_name.casefold() == GAME_EXE.casefold():
            matching_windows.append(GameWindow(int(handle), process_id.value))
        return True

    callback = _window_enum_callback(visit_window)
    if not _user32.EnumWindows(callback, 0):
        raise ctypes.WinError(ctypes.get_last_error())
    if not matching_windows:
        raise AutomationError(
            f"{GAME_EXE} is not running with a visible game window."
        )
    return matching_windows[0]


def get_primary_monitor_bounds() -> MonitorBounds:
    _require_windows()
    monitor_callback_type = ctypes.WINFUNCTYPE(
        wintypes.BOOL,
        ctypes.c_void_p,
        ctypes.c_void_p,
        ctypes.POINTER(wintypes.RECT),
        wintypes.LPARAM,
    )
    primary_bounds: list[MonitorBounds] = []

    def visit_monitor(
        monitor: int,
        _device_context: int,
        _monitor_rect,
        _parameter: int,
    ) -> bool:
        del _device_context, _monitor_rect, _parameter
        info = MonitorInfo()
        info.cbSize = ctypes.sizeof(MonitorInfo)
        if _user32.GetMonitorInfoW(monitor, ctypes.byref(info)):
            if info.dwFlags & 1:
                rect = info.rcMonitor
                primary_bounds.append(
                    MonitorBounds(rect.left, rect.top, rect.right, rect.bottom)
                )
        return True

    callback = monitor_callback_type(visit_monitor)
    _user32.GetMonitorInfoW.argtypes = [
        ctypes.c_void_p,
        ctypes.POINTER(MonitorInfo),
    ]
    _user32.GetMonitorInfoW.restype = wintypes.BOOL
    _user32.EnumDisplayMonitors.argtypes = [
        ctypes.c_void_p,
        ctypes.POINTER(wintypes.RECT),
        monitor_callback_type,
        wintypes.LPARAM,
    ]
    _user32.EnumDisplayMonitors.restype = wintypes.BOOL
    if not _user32.EnumDisplayMonitors(None, None, callback, 0):
        raise ctypes.WinError(ctypes.get_last_error())
    if not primary_bounds:
        raise AutomationError("Could not determine the primary monitor bounds.")
    bounds = primary_bounds[0]
    if bounds.width <= 0 or bounds.height <= 0:
        raise AutomationError("The primary monitor has invalid dimensions.")
    return bounds


class GameAutomation:
    def __init__(self, window: GameWindow) -> None:
        self.window = window

    def is_active(self) -> bool:
        foreground = _user32.GetForegroundWindow()
        if not foreground:
            return False
        process_id = wintypes.DWORD()
        _user32.GetWindowThreadProcessId(foreground, ctypes.byref(process_id))
        return process_id.value == self.window.process_id

    def activate(self) -> None:
        _user32.ShowWindow(self.window.handle, SW_RESTORE)
        _user32.SetForegroundWindow(self.window.handle)

    def wait_for_active(self) -> None:
        waiting_message_shown = False
        while not self.is_active():
            self.activate()
            if not waiting_message_shown:
                print("Automation paused - waiting for Granado Espada...")
                waiting_message_shown = True
            time.sleep(0.25)
        if waiting_message_shown:
            print("Granado Espada is active; resuming automation.")

    def sleep_while_active(self, milliseconds: int) -> None:
        remaining = milliseconds / 1000
        while remaining > 0:
            self.wait_for_active()
            interval = min(0.05, remaining)
            started = time.monotonic()
            time.sleep(interval)
            if self.is_active():
                remaining = max(0, remaining - (time.monotonic() - started))

    def send_key(self, virtual_key: int) -> None:
        self.wait_for_active()
        _user32.keybd_event(virtual_key, 0, 0, 0)
        _user32.keybd_event(virtual_key, 0, KEYEVENTF_KEYUP, 0)

    def scroll_up(self) -> None:
        self.wait_for_active()
        _user32.mouse_event(MOUSEEVENTF_WHEEL, 0, 0, WHEEL_DELTA, 0)

    def move_mouse(self, x: int, y: int) -> None:
        self.wait_for_active()
        if not _user32.SetCursorPos(round(x), round(y)):
            raise ctypes.WinError(ctypes.get_last_error())

    def click(self, x: int, y: int) -> None:
        self.move_mouse(x, y)
        _user32.mouse_event(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, 0)
        _user32.mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, 0)


class GameOCR:
    def __init__(self, automation: GameAutomation, debug: bool) -> None:
        self.automation = automation
        self.debug = debug
        self.script_path = Path(__file__).resolve().with_name("GameOCR.ps1")
        self.powershell_path = (
            Path(os.environ.get("SystemRoot", r"C:\Windows"))
            / "System32"
            / "WindowsPowerShell"
            / "v1.0"
            / "powershell.exe"
        )

    def read(
        self,
        target_text: str = "",
        target_index: int = 1,
        return_all_matches: bool = False,
        exact_match_only: bool = False,
    ) -> str | Bounds | list[Bounds] | None:
        if not self.script_path.is_file():
            raise AutomationError(f"Missing OCR helper: {self.script_path}")
        if not self.powershell_path.is_file():
            raise AutomationError(
                f"Windows PowerShell was not found: {self.powershell_path}"
            )

        monitor = get_primary_monitor_bounds()
        while True:
            self.automation.wait_for_active()
            output_path = Path(tempfile.gettempdir()) / (
                f"DailyShipHelper-OCR-{os.getpid()}-{time.time_ns()}.txt"
            )
            was_game_active = self.automation.is_active()
            try:
                self._run_ocr(output_path, monitor, target_text, target_index,
                              return_all_matches, exact_match_only)
                output = output_path.read_text(encoding="utf-8-sig").strip()
            except OSError as exc:
                raise AutomationError(f"Could not read OCR output: {exc}") from exc
            finally:
                output_path.unlink(missing_ok=True)

            if output == "OCR_INACTIVE" or not was_game_active:
                continue
            if not self.automation.is_active():
                self.automation.wait_for_active()
                continue

            if not target_text:
                return output
            if output == "NOT_FOUND":
                return [] if return_all_matches else None
            if output.startswith("OCR_ERROR:"):
                raise AutomationError(f"OCR failed: {output}")

            matches = [self._parse_bounds(line) for line in output.splitlines()]
            if return_all_matches:
                return matches
            if len(matches) != 1:
                raise AutomationError(f"OCR returned unexpected match data: {output}")
            return matches[0]

    def _run_ocr(
        self,
        output_path: Path,
        monitor: MonitorBounds,
        target_text: str,
        target_index: int,
        return_all_matches: bool,
        exact_match_only: bool,
    ) -> None:
        command = [
            str(self.powershell_path),
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(self.script_path),
            "-X",
            str(monitor.left),
            "-Y",
            str(monitor.top),
            "-Width",
            str(monitor.width),
            "-Height",
            str(monitor.height),
            "-GameWindowHandle",
            str(self.automation.window.handle),
            "-OutputFile",
            str(output_path),
        ]
        if target_text:
            command.extend(
                ["-TargetText", target_text, "-TargetIndex", str(target_index)]
            )
        if return_all_matches:
            command.append("-ReturnAllMatches")
        if exact_match_only:
            command.append("-ExactMatchOnly")
        if self.debug:
            command.append("-DebugMode")

        try:
            result = subprocess.run(
                command,
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
                timeout=OCR_TIMEOUT_SECONDS,
                creationflags=CREATE_NO_WINDOW,
                check=False,
            )
        except subprocess.TimeoutExpired as exc:
            raise AutomationError(
                f"Windows OCR did not finish within {OCR_TIMEOUT_SECONDS} seconds."
            ) from exc
        if result.returncode != 0:
            error_output = output_path.read_text(
                encoding="utf-8-sig", errors="replace"
            ).strip() if output_path.exists() else ""
            detail = error_output or result.stderr.strip() or "unknown OCR error"
            if not detail.startswith("OCR_INACTIVE"):
                raise AutomationError(f"OCR failed: {detail}")

    @staticmethod
    def _parse_bounds(value: str) -> Bounds:
        parts = value.strip().split("|")
        if len(parts) != 4:
            raise AutomationError(f"OCR returned invalid bounds: {value}")
        try:
            x, y, width, height = (int(part) for part in parts)
        except ValueError as exc:
            raise AutomationError(f"OCR returned invalid bounds: {value}") from exc
        if width <= 0 or height <= 0:
            raise AutomationError(f"OCR returned empty bounds: {value}")
        return Bounds(x, y, width, height)


class DailyShipHelper:
    def __init__(self, automation: GameAutomation, ocr: GameOCR) -> None:
        self.automation = automation
        self.ocr = ocr
        self.monitor = get_primary_monitor_bounds()

    def send_ships(self, batch_number: int) -> None:
        if batch_number not in (1, 2):
            raise AutomationError(f"Unknown batch number: {batch_number}")
        self.automation.activate()
        deadline = time.monotonic() + 3
        while not self.automation.is_active() and time.monotonic() < deadline:
            time.sleep(0.05)
        if not self.automation.is_active():
            raise AutomationError(
                "Could not activate Granado Espada within 3 seconds."
            )

        if batch_number == 1:
            self.assign_ship(1)
            self.assign_ship(3)
        else:
            self.assign_ship(1, "Lupala")
            self.assign_ship(2, "Unguja")
            self.assign_ship(3, "Lupala")

    def wait_for_game_idle(
        self, timeout_seconds: int = DEFAULT_IDLE_TIMEOUT_SECONDS
    ) -> bool:
        started = time.monotonic()
        while True:
            self.automation.wait_for_active()
            if self.wait_for_any_game_text(
                ["Processing Auto Combat", "Waiting", "Moving"], 0
            ):
                return True

            remaining = timeout_seconds - (time.monotonic() - started)
            if remaining <= 0:
                return False
            print(
                "Game is not AFK - waiting up to "
                f"{int(remaining + 0.999)}s for it to become idle..."
            )
            self.automation.sleep_while_active(1000)

    def wait_for_any_game_text(
        self, expected_texts: list[str], timeout_ms: int = 30000
    ) -> bool:
        active_elapsed = 0
        while True:
            self.automation.wait_for_active()
            recognized_text = self.ocr.read()
            if not isinstance(recognized_text, str):
                raise AutomationError("OCR did not return recognized text.")
            if any(expected in recognized_text for expected in expected_texts):
                return True
            if active_elapsed >= timeout_ms:
                return False
            self.automation.sleep_while_active(500)
            active_elapsed += 500

    def wait_for_game_text_bounds(
        self, expected_text: str, timeout_ms: int = 30000, target_index: int = 1
    ) -> Bounds:
        active_elapsed = 0
        while True:
            self.automation.wait_for_active()
            bounds = self.ocr.read(expected_text, target_index)
            if isinstance(bounds, Bounds):
                return bounds
            if active_elapsed >= timeout_ms:
                suffix = (
                    f" (match #{target_index})"
                    if expected_text == "Costa Lake"
                    else ""
                )
                raise AutomationError(
                    f"Expected {expected_text}{suffix} on OCR but did not see it."
                )
            self.automation.sleep_while_active(500)
            active_elapsed += 500

    def wait_for_nearby_game_text_bounds(
        self, expected_text: str, anchor: Bounds, timeout_ms: int = 30000
    ) -> Bounds:
        active_elapsed = 0
        while True:
            bounds_list = self.ocr.read(expected_text, return_all_matches=True)
            if not isinstance(bounds_list, list):
                raise AutomationError("OCR did not return all matching bounds.")
            anchor_center_x = anchor.center_x
            below_matches = [
                bounds
                for bounds in bounds_list
                if bounds.y > anchor.y + anchor.height
            ]
            if below_matches:
                return min(below_matches, key=lambda bounds: abs(
                    bounds.center_x - anchor_center_x
                ))
            if active_elapsed >= timeout_ms:
                raise AutomationError(
                    f"Expected {expected_text} on OCR but did not see it."
                )
            self.automation.sleep_while_active(500)
            active_elapsed += 500

    def wait_for_right_of_game_text_bounds(
        self, expected_text: str, anchor: Bounds, timeout_ms: int = 30000
    ) -> Bounds:
        active_elapsed = 0
        while True:
            bounds_list = self.ocr.read(expected_text, return_all_matches=True)
            if not isinstance(bounds_list, list):
                raise AutomationError("OCR did not return all matching bounds.")
            anchor_center_y = anchor.center_y
            right_matches = [
                bounds
                for bounds in bounds_list
                if bounds.x > anchor.x + anchor.width
                and abs(bounds.center_y - anchor_center_y)
                <= max(bounds.height, anchor.height)
            ]
            if right_matches:
                return min(
                    right_matches,
                    key=lambda bounds: bounds.x - (anchor.x + anchor.width),
                )
            if active_elapsed >= timeout_ms:
                raise AutomationError(
                    "Expected "
                    f"{expected_text} to the right of its neighboring trade "
                    "button on OCR but did not see it."
                )
            self.automation.sleep_while_active(500)
            active_elapsed += 500

    def assign_ship(self, ship_slot: int, destination: str = "") -> None:
        if ship_slot not in (1, 2, 3):
            raise AutomationError("Ship slot must be 1, 2, or 3.")
        if destination not in ("", "Lupala", "Unguja"):
            raise AutomationError(
                "Destination must be Lupala (13h) or Unguja (15h)."
            )

        if not self.wait_for_game_idle():
            raise AutomationError(
                "Game was not idle after waiting 5 minutes; exiting."
            )

        self.automation.send_key(0x1B)
        self.automation.send_key(ord("G"))
        trade_bounds = self.wait_for_game_text_bounds("Trade")
        self.click_bounds(trade_bounds)
        costa_lake_bounds = self.wait_for_game_text_bounds(
            "Costa Lake", target_index=ship_slot
        )
        self.click_bounds(costa_lake_bounds)

        enzaron_bounds = self.wait_for_game_text_bounds("Enzaron")
        prepare_bounds = self.wait_for_nearby_game_text_bounds(
            "Prepare for Trade", enzaron_bounds
        )

        if destination:
            scroll_x = prepare_bounds.center_x
            scroll_y = prepare_bounds.center_y - 300
            self.automation.move_mouse(round(scroll_x), round(scroll_y))
            for _ in range(50):
                self.automation.scroll_up()
            self.automation.sleep_while_active(1000)

            if destination == "Unguja":
                lupala_bounds = self.wait_for_game_text_bounds("Lupala")
                lupala_prepare_bounds = self.wait_for_nearby_game_text_bounds(
                    "Prepare for Trade", lupala_bounds
                )
                prepare_bounds = self.wait_for_right_of_game_text_bounds(
                    "Prepare for Trade", lupala_prepare_bounds
                )
            else:
                destination_bounds = self.wait_for_game_text_bounds(destination)
                prepare_bounds = self.wait_for_nearby_game_text_bounds(
                    "Prepare for Trade", destination_bounds
                )

        self.click_bounds(prepare_bounds)
        self.automation.sleep_while_active(300)
        self.confirm_trade()

        dispatch_bounds = self.wait_for_game_text_bounds("Preparation For Dispatch")
        self.click_bounds(dispatch_bounds)
        auto_team_bounds = self.wait_for_game_text_bounds("Auto Team Setting")
        self.click_bounds(auto_team_bounds)
        start_trade_bounds = self.wait_for_game_text_bounds("Start Trade")
        self.click_bounds(start_trade_bounds)

        self.wait_for_game_text_bounds("Departure")
        self.automation.send_key(0x1B)
        self.automation.send_key(ord("Z"))
        self.wait_for_any_game_text(
            ["Processing Auto Combat", "Waiting", "Moving"]
        )

    def confirm_trade(self) -> None:
        cancel_matches = self.ocr.read(
            "Cancel", return_all_matches=True, exact_match_only=True
        )
        if not isinstance(cancel_matches, list):
            raise AutomationError("OCR did not return all Cancel matches.")
        if not cancel_matches:
            raise AutomationError(
                "Cancel was not found in the trade confirmation."
            )
        if len(cancel_matches) != 1:
            raise AutomationError(
                "Multiple Cancel matches found in the trade confirmation."
            )

        cancel_bounds = cancel_matches[0]
        confirm_x = cancel_bounds.center_x + CONFIRM_OFFSET_X
        confirm_y = cancel_bounds.center_y
        if not (
            self.monitor.left <= confirm_x < self.monitor.right
            and self.monitor.top <= confirm_y < self.monitor.bottom
        ):
            raise AutomationError("Confirm offset is outside the game viewport.")
        self.automation.click(confirm_x, confirm_y)

    def click_bounds(self, bounds: Bounds) -> None:
        self.automation.click(bounds.center_x, bounds.center_y)


def build_argument_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Assign Granado Espada M ships to their trade routes."
    )
    parser.add_argument("function", nargs="?", help="Automation function: sendShips")
    parser.add_argument("batch_number", nargs="?", help="Batch number: 1 or 2")
    parser.add_argument(
        "--debug",
        action="store_true",
        help="save annotated OCR screenshots with red boxes and click markers",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_argument_parser()
    arguments = parser.parse_args(argv)
    if not arguments.function:
        parser.error("function is required (for example: sendShips 1)")
    if arguments.function.casefold() != "sendships":
        raise AutomationError(f"Unknown function: {arguments.function}")
    if arguments.batch_number is None:
        parser.error("sendShips requires a batch number (1 or 2)")
    try:
        batch_number = int(arguments.batch_number)
    except ValueError as exc:
        raise AutomationError(
            f"Unknown batch number: {arguments.batch_number}"
        ) from exc
    if batch_number not in (1, 2):
        raise AutomationError(f"Unknown batch number: {batch_number}")

    window = find_game_window()
    automation = GameAutomation(window)
    helper = DailyShipHelper(automation, GameOCR(automation, arguments.debug))
    helper.send_ships(batch_number)
    return 0


def _show_error(message: str) -> None:
    print(f"Error: {message}", file=sys.stderr)
    if os.name == "nt":
        _user32.MessageBoxW(None, message, "Daily Ship Helper", 0x10)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AutomationError, OSError, subprocess.SubprocessError) as error:
        _show_error(str(error))
        raise SystemExit(1) from error
