using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Text;
using System.Threading;

internal static class DailyShipHelperLauncher
{
    private const string BundleResourceName = "DailyShipHelper.Bundle.zip";
    private static readonly Version MinimumPythonVersion = new Version(3, 11);

    private static int Main(string[] args)
    {
        bool createdNew;
        using (Mutex instanceMutex = new Mutex(
            true, @"Local\DailyShipHelper", out createdNew))
        {
            if (!createdNew)
            {
                Console.Error.WriteLine("Daily Ship Helper is already running.");
                return 1;
            }
            return RunHelper(args);
        }
    }

    private static int RunHelper(string[] args)
    {
        try
        {
            string executableDirectory = Path.GetDirectoryName(
                Assembly.GetExecutingAssembly().Location);
            if (String.IsNullOrEmpty(executableDirectory))
                throw new InvalidOperationException("The executable folder is unavailable.");

            ExtractBundle(executableDirectory);

            string venvDirectory = Path.Combine(executableDirectory, ".venv");
            string venvPython = Path.Combine(venvDirectory, "Scripts", "python.exe");
            EnsureVirtualEnvironment(venvDirectory, venvPython);

            StringBuilder pythonArguments = new StringBuilder();
            pythonArguments.Append(QuoteArgument(
                Path.Combine(executableDirectory, "GEM_Helper.py")));
            foreach (string argument in args)
            {
                pythonArguments.Append(' ');
                pythonArguments.Append(QuoteArgument(argument));
            }

            ProcessStartInfo startInfo = CreateStartInfo(
                venvPython,
                pythonArguments.ToString(),
                executableDirectory);
            using (Process process = Process.Start(startInfo))
            {
                if (process == null)
                    throw new InvalidOperationException(
                        "The Daily Ship Helper Python process could not be started.");
                process.WaitForExit();
                return process.ExitCode;
            }
        }
        catch (Exception exception)
        {
            Console.Error.WriteLine("Daily Ship Helper could not start: " + exception.Message);
            WaitForKey();
            return 1;
        }
    }

    private static void EnsureVirtualEnvironment(
        string venvDirectory,
        string venvPython)
    {
        if (File.Exists(venvPython))
        {
            string error;
            if (ProbePython(venvPython, String.Empty, out error) == null)
                throw new InvalidOperationException(
                    "The adjacent .venv is not usable. Remove the .venv directory and " +
                    "restart. " + error);
            return;
        }

        if (Directory.Exists(venvDirectory) &&
            Directory.GetFileSystemEntries(venvDirectory).Length > 0)
        {
            throw new InvalidOperationException(
                "The .venv directory exists but has no usable Python interpreter. " +
                "Remove that incomplete .venv directory and restart.");
        }

        string basePython = FindPython();
        Console.WriteLine("Creating the isolated Python environment beside the executable...");
        Run(
            basePython,
            "-m venv " + QuoteArgument(venvDirectory),
            Path.GetDirectoryName(venvDirectory),
            "Virtual environment creation");

        if (!File.Exists(venvPython))
            throw new InvalidOperationException(
                "Python completed venv creation without producing " +
                ".venv\\Scripts\\python.exe.");
    }

    private static string FindPython()
    {
        List<string> failures = new List<string>();
        string error;
        string launcher = FindExecutable("py.exe");
        if (!String.IsNullOrEmpty(launcher))
        {
            PythonInstallation installation = ProbePython(launcher, "-3", out error);
            if (installation != null)
                return installation.Executable;
            failures.Add("py.exe: " + error);
        }

        string python = FindExecutable("python.exe");
        if (!String.IsNullOrEmpty(python))
        {
            PythonInstallation installation = ProbePython(python, String.Empty, out error);
            if (installation != null)
                return installation.Executable;
            failures.Add("python.exe: " + error);
        }

        string detail = failures.Count == 0
            ? String.Empty
            : Environment.NewLine + String.Join(Environment.NewLine, failures.ToArray());
        throw new InvalidOperationException(
            "A standard Python 3.11+ installation with venv is required. " +
            "Install Python and make py.exe or python.exe available on PATH." + detail);
    }

    private static PythonInstallation ProbePython(
        string command,
        string prefix,
        out string error)
    {
        string arguments = String.IsNullOrEmpty(prefix) ? String.Empty : prefix + " ";
        arguments += "-c " + QuoteArgument(
            "import sys; print(sys.executable); " +
            "print('%d.%d' % sys.version_info[:2])");

        CommandResult result;
        try
        {
            result = RunCaptured(command, arguments, Environment.CurrentDirectory);
        }
        catch (Win32Exception exception)
        {
            error = exception.Message;
            return null;
        }

        if (result.ExitCode != 0)
        {
            error = String.IsNullOrWhiteSpace(result.StandardError)
                ? "Python could not be launched."
                : result.StandardError.Trim();
            return null;
        }

        string[] lines = result.StandardOutput.Split(
            new char[] { '\r', '\n' },
            StringSplitOptions.RemoveEmptyEntries);
        if (lines.Length < 2)
        {
            error = "Python returned an unexpected version response.";
            return null;
        }

        Version version;
        if (!Version.TryParse(lines[1].Trim(), out version) ||
            version < MinimumPythonVersion)
        {
            error = "Python 3.11 or later is required.";
            return null;
        }

        string executable = lines[0].Trim();
        if (!File.Exists(executable))
        {
            error = "Python reported an executable path that does not exist.";
            return null;
        }

        error = String.Empty;
        return new PythonInstallation(Path.GetFullPath(executable), version);
    }

    private static string FindExecutable(string fileName)
    {
        string path = Environment.GetEnvironmentVariable("PATH") ?? String.Empty;
        foreach (string entry in path.Split(Path.PathSeparator))
        {
            string directory = entry.Trim().Trim('"');
            bool isWindowsApps = directory.IndexOf(
                "\\Microsoft\\WindowsApps", StringComparison.OrdinalIgnoreCase) >= 0;
            bool isPythonLauncher = String.Equals(
                fileName, "py.exe", StringComparison.OrdinalIgnoreCase);
            if (String.IsNullOrEmpty(directory) || (isWindowsApps && !isPythonLauncher))
            {
                continue;
            }

            string candidate = Path.Combine(directory, fileName);
            if (File.Exists(candidate))
                return Path.GetFullPath(candidate);
        }

        if (String.Equals(fileName, "py.exe", StringComparison.OrdinalIgnoreCase))
        {
            string candidate = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.Windows),
                fileName);
            if (File.Exists(candidate))
                return candidate;
        }

        return null;
    }

    private static void ExtractBundle(string destination)
    {
        string destinationRoot = Path.GetFullPath(destination).TrimEnd(
            Path.DirectorySeparatorChar,
            Path.AltDirectorySeparatorChar) + Path.DirectorySeparatorChar;

        using (Stream bundle = Assembly.GetExecutingAssembly()
            .GetManifestResourceStream(BundleResourceName))
        {
            if (bundle == null)
                throw new InvalidOperationException(
                    "The embedded Daily Ship Helper bundle is missing.");

            using (ZipArchive archive = new ZipArchive(bundle, ZipArchiveMode.Read))
            {
                foreach (ZipArchiveEntry entry in archive.Entries)
                {
                    string relativePath = entry.FullName.Replace(
                        '/', Path.DirectorySeparatorChar);
                    string filePath = Path.GetFullPath(
                        Path.Combine(destinationRoot, relativePath));
                    if (!filePath.StartsWith(
                        destinationRoot, StringComparison.OrdinalIgnoreCase))
                    {
                        throw new InvalidDataException(
                            "The embedded bundle contains an invalid path.");
                    }

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

    private static ProcessStartInfo CreateStartInfo(
        string executable,
        string arguments,
        string workingDirectory)
    {
        ProcessStartInfo startInfo = new ProcessStartInfo();
        startInfo.FileName = executable;
        startInfo.Arguments = arguments;
        startInfo.WorkingDirectory = workingDirectory;
        startInfo.UseShellExecute = false;
        startInfo.CreateNoWindow = false;
        startInfo.EnvironmentVariables.Remove("PYTHONPATH");
        startInfo.EnvironmentVariables.Remove("PYTHONHOME");
        startInfo.EnvironmentVariables.Remove("PYTHONUSERBASE");
        startInfo.EnvironmentVariables["PYTHONNOUSERSITE"] = "1";
        return startInfo;
    }

    private static void Run(
        string executable,
        string arguments,
        string workingDirectory,
        string description)
    {
        ProcessStartInfo startInfo = CreateStartInfo(
            executable, arguments, workingDirectory);
        Console.WriteLine(description + "...");
        using (Process process = Process.Start(startInfo))
        {
            if (process == null)
                throw new InvalidOperationException(description + " could not be started.");
            process.WaitForExit();
            if (process.ExitCode != 0)
                throw new InvalidOperationException(
                    description + " failed with exit code " + process.ExitCode + ".");
        }
    }

    private static CommandResult RunCaptured(
        string executable,
        string arguments,
        string workingDirectory)
    {
        ProcessStartInfo startInfo = CreateStartInfo(
            executable, arguments, workingDirectory);
        startInfo.CreateNoWindow = true;
        startInfo.RedirectStandardOutput = true;
        startInfo.RedirectStandardError = true;

        using (Process process = Process.Start(startInfo))
        {
            if (process == null)
                throw new InvalidOperationException("Python could not be started.");
            string standardOutput = process.StandardOutput.ReadToEnd();
            string standardError = process.StandardError.ReadToEnd();
            process.WaitForExit();
            return new CommandResult(
                process.ExitCode, standardOutput, standardError);
        }
    }

    private static string QuoteArgument(string value)
    {
        StringBuilder quoted = new StringBuilder();
        quoted.Append('"');
        int backslashes = 0;
        foreach (char character in value)
        {
            if (character == '\\')
            {
                backslashes++;
            }
            else if (character == '"')
            {
                quoted.Append('\\', backslashes * 2 + 1);
                quoted.Append('"');
                backslashes = 0;
            }
            else
            {
                quoted.Append('\\', backslashes);
                quoted.Append(character);
                backslashes = 0;
            }
        }
        quoted.Append('\\', backslashes * 2);
        quoted.Append('"');
        return quoted.ToString();
    }

    private static void WaitForKey()
    {
        if (!Console.IsInputRedirected)
        {
            Console.WriteLine();
            Console.WriteLine("Press any key to close.");
            Console.ReadKey(true);
        }
    }

    private sealed class PythonInstallation
    {
        public PythonInstallation(string executable, Version version)
        {
            Executable = executable;
            Version = version;
        }

        public string Executable { get; private set; }
        public Version Version { get; private set; }
    }

    private sealed class CommandResult
    {
        public CommandResult(int exitCode, string standardOutput, string standardError)
        {
            ExitCode = exitCode;
            StandardOutput = standardOutput;
            StandardError = standardError;
        }

        public int ExitCode { get; private set; }
        public string StandardOutput { get; private set; }
        public string StandardError { get; private set; }
    }
}
