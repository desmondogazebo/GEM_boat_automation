using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Text;

internal static class ClientExeLauncher
{
    private const string BundleResourceName = "DeathCheckerClient.Bundle.zip";
    private const string DefaultConfigJson =
        "{\r\n" +
        "  \"monitorIntervalMinutes\": 30,\r\n" +
        "  \"discordId\": \"\"\r\n" +
        "}\r\n";

    private static int Main()
    {
        try
        {
            string localAppData = Environment.GetEnvironmentVariable("LOCALAPPDATA");
            if (String.IsNullOrEmpty(localAppData))
                localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            if (String.IsNullOrEmpty(localAppData))
                throw new InvalidOperationException("The local application data folder is unavailable.");

            string executableDirectory = Path.GetDirectoryName(
                Assembly.GetExecutingAssembly().Location);
            if (String.IsNullOrEmpty(executableDirectory))
                throw new InvalidOperationException("The executable folder is unavailable.");

            string clientDirectory = Path.Combine(localAppData, "EchelonDeathMonitor", "ClientApp");
            Directory.CreateDirectory(clientDirectory);
            ExtractBundle(clientDirectory);

            string configPath = Path.Combine(executableDirectory, "config.json");
            RemoveLegacyConfiguration(clientDirectory, localAppData, configPath);
            if (!File.Exists(configPath))
            {
                File.WriteAllText(configPath, DefaultConfigJson, new UTF8Encoding(false));
                Console.WriteLine("Created config.json beside the executable:");
                Console.WriteLine(configPath);
                Console.WriteLine("Set discordId and monitorIntervalMinutes, then launch this executable again.");
                WaitForKey();
                return 0;
            }

            string pwshPath = FindPwsh();
            if (pwshPath == null)
            {
                Console.Error.WriteLine("PowerShell 7 or later (pwsh.exe) is required.");
                WaitForKey();
                return 1;
            }

            string runtimePath = Path.Combine(clientDirectory, "ClientRuntime.ps1");
            ProcessStartInfo startInfo = new ProcessStartInfo();
            startInfo.FileName = pwshPath;
            startInfo.Arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -NoExit -File " +
                QuoteArgument(runtimePath) + " -ConfigPath " + QuoteArgument(configPath);
            startInfo.WorkingDirectory = clientDirectory;
            startInfo.UseShellExecute = false;

            using (Process process = Process.Start(startInfo))
            {
                process.WaitForExit();
                return process.ExitCode;
            }
        }
        catch (Exception exception)
        {
            Console.Error.WriteLine("DeathChecker could not start: " + exception.Message);
            WaitForKey();
            return 1;
        }
    }

    private static void RemoveLegacyConfiguration(
        string clientDirectory,
        string localAppData,
        string currentConfigPath)
    {
        string[] legacyFiles = new string[] {
            Path.Combine(clientDirectory, "config.json"),
            Path.Combine(clientDirectory, "config.example.json"),
            Path.Combine(localAppData, "EchelonDeathMonitor", "discord-id.txt")
        };
        foreach (string path in legacyFiles)
        {
            if (String.Equals(
                Path.GetFullPath(path),
                Path.GetFullPath(currentConfigPath),
                StringComparison.OrdinalIgnoreCase))
                continue;

            if (File.Exists(path))
                File.Delete(path);
        }
    }

    private static void ExtractBundle(string destination)
    {
        string destinationRoot = Path.GetFullPath(destination).TrimEnd(
            Path.DirectorySeparatorChar,
            Path.AltDirectorySeparatorChar) + Path.DirectorySeparatorChar;

        using (Stream bundle = Assembly.GetExecutingAssembly().GetManifestResourceStream(BundleResourceName))
        {
            if (bundle == null)
                throw new InvalidOperationException("The embedded client bundle is missing.");

            using (ZipArchive archive = new ZipArchive(bundle, ZipArchiveMode.Read))
            {
                foreach (ZipArchiveEntry entry in archive.Entries)
                {
                    string relativePath = entry.FullName.Replace('/', Path.DirectorySeparatorChar);
                    string filePath = Path.GetFullPath(Path.Combine(destinationRoot, relativePath));
                    if (!filePath.StartsWith(destinationRoot, StringComparison.OrdinalIgnoreCase))
                        throw new InvalidDataException("The embedded client bundle contains an invalid path.");

                    if (entry.FullName.EndsWith("/", StringComparison.Ordinal) ||
                        entry.FullName.EndsWith("\\", StringComparison.Ordinal))
                    {
                        Directory.CreateDirectory(filePath);
                        continue;
                    }

                    Directory.CreateDirectory(Path.GetDirectoryName(filePath));
                    using (Stream source = entry.Open())
                    using (FileStream target = File.Create(filePath))
                        source.CopyTo(target);
                }
            }
        }
    }

    private static string FindPwsh()
    {
        string path = Environment.GetEnvironmentVariable("PATH") ?? String.Empty;
        foreach (string directory in path.Split(Path.PathSeparator))
        {
            string candidate = Path.Combine(directory.Trim('"'), "pwsh.exe");
            if (File.Exists(candidate))
                return candidate;
        }
        return null;
    }

    private static string QuoteArgument(string value)
    {
        return "\"" + value.Replace("\"", "\\\"") + "\"";
    }

    private static void WaitForKey()
    {
        Console.WriteLine();
        Console.WriteLine("Press any key to close.");
        if (!Console.IsInputRedirected)
            Console.ReadKey(true);
    }
}
