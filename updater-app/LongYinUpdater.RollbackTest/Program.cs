using System.Reflection;
using System.Text.RegularExpressions;

const string existingRelativePath = "payload/existing.txt";
const string createdRelativePath = "payload/created.txt";

var testRoot = Path.Combine(
    Path.GetTempPath(),
    "longyin-updater-rollback-test",
    Guid.NewGuid().ToString("N"));
var stageRoot = Path.Combine(testRoot, "stage");
var targetRoot = Path.Combine(testRoot, "target");
var logPath = Path.Combine(testRoot, "update.log");
string? backupRoot = null;

try
{
    Directory.CreateDirectory(Path.Combine(stageRoot, "payload"));
    Directory.CreateDirectory(Path.Combine(targetRoot, "payload"));
    File.WriteAllText(Path.Combine(stageRoot, existingRelativePath), "replacement");
    File.WriteAllText(Path.Combine(stageRoot, createdRelativePath), "new file");
    File.WriteAllText(Path.Combine(targetRoot, existingRelativePath), "original");

    var updaterAssembly = Assembly.Load("LongYinUpdater");
    var optionsType = updaterAssembly.GetType("LongYinUpdater.UpdateOptions", throwOnError: true)!;
    var parseMethod = optionsType.GetMethod("Parse", BindingFlags.Public | BindingFlags.Static)
        ?? throw new MissingMethodException(optionsType.FullName, "Parse");
    var options = parseMethod.Invoke(null, new object[]
    {
        new[]
        {
            "--wait-pid", "0",
            "--source", stageRoot,
            "--target", targetRoot,
            "--exe", "intentionally-missing.exe",
            "--log", logPath,
            "--version", "rollback-test"
        }
    }) ?? throw new InvalidOperationException("UpdateOptions.Parse returned null.");

    var runnerType = updaterAssembly.GetType(
        "LongYinUpdater.UpdaterForm+UpdateRunner",
        throwOnError: true)!;
    var runMethod = runnerType.GetMethod(
        "RunAsync",
        BindingFlags.Public | BindingFlags.Static,
        binder: null,
        types: new[] { optionsType, typeof(Action<string, int>) },
        modifiers: null)
        ?? throw new MissingMethodException(runnerType.FullName, "RunAsync");
    Action<string, int> progress = (_, _) => { };
    var task = (Task?)runMethod.Invoke(null, new[] { options, progress })
        ?? throw new InvalidOperationException("UpdateRunner.RunAsync returned null.");

    var failedAsExpected = false;
    try
    {
        await task;
    }
    catch (FileNotFoundException ex) when (ex.Message.Contains("主程序不存在", StringComparison.Ordinal))
    {
        failedAsExpected = true;
    }

    Assert(failedAsExpected, "Updater did not reach the intentional post-copy launch failure.");
    Assert(
        File.ReadAllText(Path.Combine(targetRoot, existingRelativePath)) == "original",
        "Rollback did not restore the replaced file.");
    Assert(
        !File.Exists(Path.Combine(targetRoot, createdRelativePath)),
        "Rollback did not remove the newly-created file.");
    Assert(
        Directory.Exists(stageRoot),
        "Failed update removed the stage directory, preventing retry or diagnosis.");
    Assert(
        !File.Exists(Path.Combine(targetRoot, "intentionally-missing.exe")),
        "Updater unexpectedly launched or created the missing application.");
    Assert(
        !File.Exists(Path.Combine(Path.GetDirectoryName(logPath)!, "ota-update-complete.json")),
        "Failed update left a false completion marker.");

    var logText = File.ReadAllText(logPath);
    Assert(
        logText.Contains($"Rollback restored: {Path.Combine("payload", "existing.txt")}", StringComparison.Ordinal),
        "Updater log did not record restoration of the replaced file.");
    Assert(
        logText.Contains($"Rollback removed newly-created file: {Path.Combine("payload", "created.txt")}", StringComparison.Ordinal),
        "Updater log did not record removal of the newly-created file.");

    var processFailureStageRoot = Path.Combine(testRoot, "process-query-failure-stage");
    var processFailureTargetRoot = Path.Combine(testRoot, "process-query-failure-target");
    var processFailureLogPath = Path.Combine(testRoot, "process-query-failure.log");
    Directory.CreateDirectory(processFailureStageRoot);
    Directory.CreateDirectory(processFailureTargetRoot);
    File.WriteAllText(Path.Combine(processFailureStageRoot, "app.txt"), "replacement");
    File.WriteAllText(Path.Combine(processFailureTargetRoot, "app.txt"), "original");

    var processFailureOptions = parseMethod.Invoke(null, new object[]
    {
        new[]
        {
            "--wait-pid", "12345",
            "--source", processFailureStageRoot,
            "--target", processFailureTargetRoot,
            "--exe", "LongYinProMaxApp.exe",
            "--log", processFailureLogPath,
            "--version", "process-query-failure-test"
        }
    }) ?? throw new InvalidOperationException("UpdateOptions.Parse returned null.");

    var injectableRunMethod = runnerType.GetMethod(
        "RunAsync",
        BindingFlags.Public | BindingFlags.Static,
        binder: null,
        types: new[] { optionsType, typeof(Action<string, int>), typeof(Func<int, bool>) },
        modifiers: null)
        ?? throw new MissingMethodException(runnerType.FullName, "RunAsync with process query injection");
    Func<int, bool> failingProcessQuery = _ =>
        throw new InvalidOperationException("simulated process query failure");
    var processFailureTask = (Task?)injectableRunMethod.Invoke(
        null,
        new object[] { processFailureOptions, progress, failingProcessQuery })
        ?? throw new InvalidOperationException("Injected UpdateRunner.RunAsync returned null.");

    var processQueryFailedClosed = false;
    try
    {
        await processFailureTask;
    }
    catch (InvalidOperationException ex) when (
        ex.Message.Contains("simulated process query failure", StringComparison.Ordinal))
    {
        processQueryFailedClosed = true;
    }

    Assert(processQueryFailedClosed, "Process query failure did not stop the update.");
    Assert(
        File.ReadAllText(Path.Combine(processFailureTargetRoot, "app.txt")) == "original",
        "Updater replaced a target file after process state query failed.");
    Assert(
        Directory.Exists(processFailureStageRoot),
        "Updater removed the stage directory after process state query failed.");
    Assert(
        !File.Exists(Path.Combine(Path.GetDirectoryName(processFailureLogPath)!, "ota-update-complete.json")),
        "Updater wrote a completion marker after process state query failed.");
    Assert(
        !File.ReadAllText(processFailureLogPath).Contains("Stage file count=", StringComparison.Ordinal),
        "Updater entered the replacement phase after process state query failed.");

    var backupMatch = Regex.Match(logText, @"backupRoot=(?<path>[^\r\n]+)");
    if (backupMatch.Success)
    {
        backupRoot = backupMatch.Groups["path"].Value.Trim();
    }

    Console.WriteLine(
        "PASS: updater rolls back failed replacement and fails closed before replacement when process queries fail.");
}
finally
{
    if (!string.IsNullOrWhiteSpace(backupRoot) && Directory.Exists(backupRoot))
    {
        var allowedBackupParent = Path.Combine(
            Path.GetTempPath(),
            "longyin-plus-update",
            "backups");
        AssertPathWithin(backupRoot, allowedBackupParent, "rollback backup cleanup");
        Directory.Delete(backupRoot, recursive: true);
    }

    if (Directory.Exists(testRoot))
    {
        var allowedTestParent = Path.Combine(Path.GetTempPath(), "longyin-updater-rollback-test");
        AssertPathWithin(testRoot, allowedTestParent, "test cleanup");
        Directory.Delete(testRoot, recursive: true);
    }
}

static void Assert(bool condition, string message)
{
    if (!condition)
    {
        throw new InvalidOperationException(message);
    }
}

static void AssertPathWithin(string candidate, string parent, string label)
{
    var fullCandidate = Path.GetFullPath(candidate);
    var fullParent = Path.GetFullPath(parent)
        .TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar)
        + Path.DirectorySeparatorChar;
    if (!fullCandidate.StartsWith(fullParent, StringComparison.OrdinalIgnoreCase))
    {
        throw new InvalidOperationException($"Unsafe {label} path: {fullCandidate}");
    }
}
