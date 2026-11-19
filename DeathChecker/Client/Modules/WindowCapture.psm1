if (-not ("Echelon.WindowCapture" -as [type])) {
    Add-Type -AssemblyName System.Drawing
    $drawingAssembly = [System.Drawing.Bitmap].Assembly.Location
    Add-Type -ReferencedAssemblies $drawingAssembly -TypeDefinition @"
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

namespace Echelon {
    public static class WindowCapture {
        [StructLayout(LayoutKind.Sequential)]
        private struct RECT { public int Left, Top, Right, Bottom; }

        [DllImport("user32.dll")]
        private static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
        [DllImport("user32.dll")]
        private static extern IntPtr GetWindowDC(IntPtr hWnd);
        [DllImport("user32.dll")]
        private static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);
        [DllImport("user32.dll")]
        private static extern bool PrintWindow(IntPtr hWnd, IntPtr hDC, uint flags);
        [DllImport("gdi32.dll")]
        private static extern IntPtr CreateCompatibleDC(IntPtr hDC);
        [DllImport("gdi32.dll")]
        private static extern IntPtr CreateCompatibleBitmap(IntPtr hDC, int width, int height);
        [DllImport("gdi32.dll")]
        private static extern IntPtr SelectObject(IntPtr hDC, IntPtr hObject);
        [DllImport("gdi32.dll")]
        private static extern bool DeleteDC(IntPtr hDC);
        [DllImport("gdi32.dll")]
        private static extern bool DeleteObject(IntPtr hObject);

        public static void Capture(IntPtr hWnd, string path,
                                   double left, double top, double cropWidth, double cropHeight) {
            RECT rect;
            if (hWnd == IntPtr.Zero || !GetWindowRect(hWnd, out rect))
                throw new InvalidOperationException("The GE M window is unavailable.");
            int width = rect.Right - rect.Left, height = rect.Bottom - rect.Top;
            if (width <= 0 || height <= 0)
                throw new InvalidOperationException("The GE M window has no capturable area.");

            IntPtr windowDC = GetWindowDC(hWnd);
            IntPtr memoryDC = IntPtr.Zero, bitmap = IntPtr.Zero, previous = IntPtr.Zero;
            try {
                if (windowDC == IntPtr.Zero)
                    throw new InvalidOperationException("Could not access the GE M window.");
                memoryDC = CreateCompatibleDC(windowDC);
                bitmap = CreateCompatibleBitmap(windowDC, width, height);
                if (memoryDC == IntPtr.Zero || bitmap == IntPtr.Zero)
                    throw new InvalidOperationException("Could not allocate a GE M capture surface.");
                previous = SelectObject(memoryDC, bitmap);
                if (previous == IntPtr.Zero)
                    throw new InvalidOperationException("Could not prepare the GE M capture surface.");
                if (!PrintWindow(hWnd, memoryDC, 2))
                    throw new InvalidOperationException(
                        "Windows could not capture the GE M window. Try borderless windowed mode.");
                using (Bitmap image = Bitmap.FromHbitmap(bitmap)) {
                    int x = (int)Math.Round(width * left);
                    int y = (int)Math.Round(height * top);
                    int w = (int)Math.Round(width * cropWidth);
                    int h = (int)Math.Round(height * cropHeight);
                    if (x < 0 || y < 0 || w <= 0 || h <= 0 ||
                        x + w > width || y + h > height)
                        throw new InvalidOperationException("The configured death-screen crop is outside the game window.");
                    using (Bitmap crop = image.Clone(new Rectangle(x, y, w, h), PixelFormat.Format24bppRgb))
                        crop.Save(path, ImageFormat.Png);
                }
            } finally {
                if (previous != IntPtr.Zero) SelectObject(memoryDC, previous);
                if (bitmap != IntPtr.Zero) DeleteObject(bitmap);
                if (memoryDC != IntPtr.Zero) DeleteDC(memoryDC);
                if (windowDC != IntPtr.Zero) ReleaseDC(hWnd, windowDC);
            }
        }
    }
}
"@
}

function Save-GameWindowScreenshot {
    param(
        [Parameter(Mandatory)][IntPtr]$WindowHandle,
        [Parameter(Mandatory)][double[]]$DeathScreenCrop
    )

    if ($DeathScreenCrop.Count -ne 4 -or
        $DeathScreenCrop[0] -lt 0 -or $DeathScreenCrop[1] -lt 0 -or
        $DeathScreenCrop[2] -le 0 -or $DeathScreenCrop[3] -le 0 -or
        $DeathScreenCrop[0] + $DeathScreenCrop[2] -gt 1 -or
        $DeathScreenCrop[1] + $DeathScreenCrop[3] -gt 1) {
        throw "Set deathScreenCrop to [left, top, width, height] normalized to the GE M window after calibrating against a real death screen."
    }

    $path = Join-Path ([IO.Path]::GetTempPath()) (
        "echelon-{0}.png" -f [Guid]::NewGuid().ToString("N")
    )
    try {
        [Echelon.WindowCapture]::Capture(
            $WindowHandle, $path,
            $DeathScreenCrop[0], $DeathScreenCrop[1],
            $DeathScreenCrop[2], $DeathScreenCrop[3]
        )
        return $path
    } catch {
        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Force
        }
        throw
    }
}

Export-ModuleMember -Function Save-GameWindowScreenshot
