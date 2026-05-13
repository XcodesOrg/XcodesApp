import Combine
import Darwin
import Foundation
import libunxip
import Path
import XcodesKit

public struct Shell: @unchecked Sendable {
    public var unxip: (URL) -> AnyPublisher<ProcessOutput, Error> = { Process.run(
        Path.root.usr.bin.xip,
        workingDirectory: $0.deletingLastPathComponent(),
        "--expand",
        "\($0.path)"
    ) }
    public var spctlAssess: (URL) -> AnyPublisher<ProcessOutput, Error> = { Process.run(
        Path.root.usr.sbin.spctl,
        "--assess",
        "--verbose",
        "--type",
        "execute",
        "\($0.path)"
    ) }
    public var codesignVerify: (URL) -> AnyPublisher<ProcessOutput, Error> = { Process.run(
        Path.root.usr.bin.codesign,
        "-vv",
        "-d",
        "\($0.path)"
    ) }
    public var buildVersion: () -> AnyPublisher<ProcessOutput, Error> = { Process.run(
        Path.root.usr.bin.sw_vers,
        "-buildVersion"
    ) }
    public var xcodeBuildVersion: (InstalledXcode) -> AnyPublisher<ProcessOutput, Error> = { Process.run(
        Path.root.usr.libexec.PlistBuddy,
        "-c",
        "Print :ProductBuildVersion",
        "\($0.path.string)/Contents/version.plist"
    ) }
    public var getUserCacheDir: () -> AnyPublisher<ProcessOutput, Error> = { Process.run(
        Path.root.usr.bin.getconf,
        "DARWIN_USER_CACHE_DIR"
    ) }
    public var touchInstallCheck: (String, String, String) -> AnyPublisher<ProcessOutput, Error> = { Process.run(
        Path.root.usr.bin / "touch",
        "\($0)com.apple.dt.Xcode.InstallCheckCache_\($1)_\($2)"
    ) }
    public var xcodeSelectPrintPath: () -> AnyPublisher<ProcessOutput, Error> = { Process.run(
        Path.root.usr.bin.join("xcode-select"),
        "-p"
    ) }
    public var aria2Path: () -> Path? = { systemExecutablePath(named: "aria2c") }

    public var downloadWithAria2: (Path, URL, Path, [HTTPCookie])
        -> (Progress, AnyPublisher<Void, Error>) = aria2Download
    public var downloadWithAria2Async: (Path, URL, Path, [HTTPCookie])
        -> AsyncThrowingStream<Progress, Error> = aria2DownloadStream
    public var unxipExperiment: (URL) -> AnyPublisher<ProcessOutput, Error> = unxipPublisher
    public var downloadRuntime: (String, String, String?)
        -> AsyncThrowingStream<Progress, Error> = runtimeDownloadStream
}

private final class FuturePromiseBox<Output>: @unchecked Sendable {
    typealias Promise = (Result<Output, Error>) -> Void

    private nonisolated(unsafe) let promise: Promise

    nonisolated init(_ promise: @escaping Promise) {
        self.promise = promise
    }

    nonisolated func resolve(_ result: Result<Output, Error>) {
        promise(result)
    }
}

private final class NotificationObserverBox: @unchecked Sendable {
    private nonisolated(unsafe) let observer: NSObjectProtocol

    nonisolated init(_ observer: NSObjectProtocol) {
        self.observer = observer
    }

    nonisolated func remove() {
        NotificationCenter.default.removeObserver(observer, name: .NSFileHandleDataAvailable, object: nil)
    }
}

private func aria2Download(
    aria2Path: Path,
    url: URL,
    destination: Path,
    cookies: [HTTPCookie]
) -> (Progress, AnyPublisher<Void, Error>) {
    let process = configuredAria2Process(aria2Path: aria2Path, url: url, destination: destination, cookies: cookies)
    let pipes = attachPipes(to: process)
    let progress = downloadProgress()
    let observer = observeProcessOutput(pipes: pipes) { progress.updateFromAria2(string: $0) }

    startReading(pipes)

    do {
        try process.run()
    } catch {
        observer.remove()
        return (progress, Fail(error: error).eraseToAnyPublisher())
    }

    return (progress, processSuccessPublisher(process: process, observer: observer, aria2Errors: true))
}

private func aria2DownloadStream(
    aria2Path: Path,
    url: URL,
    destination: Path,
    cookies: [HTTPCookie]
) -> AsyncThrowingStream<Progress, Error> {
    AsyncThrowingStream<Progress, Error> { continuation in
        Task {
            let progress = downloadProgress()
            let process = configuredAria2Process(
                aria2Path: aria2Path,
                url: url,
                destination: destination,
                cookies: cookies
            )
            let pipes = attachPipes(to: process)
            let observer = observeProcessOutput(pipes: pipes) {
                progress.updateFromAria2(string: $0)
                continuation.yield(progress)
            }

            runDownloadProcess(process, observer: observer, continuation: continuation)
        }
    }
}

private func runtimeDownloadStream(
    platform: String,
    version: String,
    architecture: String?
) -> AsyncThrowingStream<Progress, Error> {
    AsyncThrowingStream<Progress, Error> { continuation in
        Task {
            let progress = downloadProgress()
            let process = configuredRuntimeDownloadProcess(
                platform: platform,
                version: version,
                architecture: architecture
            )
            let pipes = attachPipes(to: process)
            let observer = observeProcessOutput(pipes: pipes) {
                progress.updateFromXcodebuild(text: $0)
                continuation.yield(progress)
            }

            runDownloadProcess(process, observer: observer, continuation: continuation)
        }
    }
}

private func unxipPublisher(url: URL) -> AnyPublisher<ProcessOutput, Error> {
    Deferred {
        Future<ProcessOutput, Error> { promise in
            let promiseBox = FuturePromiseBox(promise)
            Task.detached(priority: .userInitiated) {
                do {
                    let output = try await runLibUnxip(url)
                    promiseBox.resolve(.success(output))
                } catch {
                    promiseBox.resolve(.failure(error))
                }
            }
        }
    }
    .eraseToAnyPublisher()
}

func configuredAria2Process(
    aria2Path: Path,
    url: URL,
    destination: Path,
    cookies: [HTTPCookie]
) -> Process {
    let process = Process()
    process.executableURL = aria2Path.url
    process.arguments = [
        "--max-connection-per-server=16",
        "--split=16",
        "--summary-interval=1",
        "--stop-with-process=\(ProcessInfo.processInfo.processIdentifier)",
        "--dir=\(destination.parent.string)",
        "--out=\(destination.basename())",
        "--human-readable=false",
        "--input-file=-"
    ]

    let inputPipe = Pipe()
    inputPipe.fileHandleForWriting.write(Data(aria2InputFileContents(url: url, cookies: cookies).utf8))
    inputPipe.fileHandleForWriting.closeFile()
    process.standardInput = inputPipe.fileHandleForReading
    return process
}

func aria2InputFileContents(url: URL, cookies: [HTTPCookie]) -> String {
    let cookieHeader = cookies
        .map { "\($0.name)=\($0.value)" }
        .joined(separator: "; ")

    guard !cookieHeader.isEmpty else {
        return "\(url.absoluteString)\n"
    }
    return """
    \(url.absoluteString)
     header=Cookie: \(cookieHeader)

    """
}

private func configuredRuntimeDownloadProcess(platform: String, version: String, architecture: String?) -> Process {
    let process = Process()
    process.executableURL = Path.root.usr.bin.join("xcodebuild").url
    process.arguments = [
        "-downloadPlatform",
        "\(platform)",
        "-buildVersion",
        "\(version)"
    ]

    if let architecture {
        process.arguments?.append(contentsOf: [
            "-architectureVariant",
            "\(architecture)"
        ])
    }

    return process
}

private typealias ProcessPipes = (stdOutPipe: Pipe, stdErrPipe: Pipe)

private func attachPipes(to process: Process) -> ProcessPipes {
    let stdOutPipe = Pipe()
    process.standardOutput = stdOutPipe
    let stdErrPipe = Pipe()
    process.standardError = stdErrPipe

    return (stdOutPipe, stdErrPipe)
}

private func observeProcessOutput(
    pipes: ProcessPipes,
    receiveText: @escaping (String) -> Void
) -> NotificationObserverBox {
    nonisolated(unsafe) let receiveText = receiveText

    return NotificationObserverBox(NotificationCenter.default.addObserver(
        forName: .NSFileHandleDataAvailable,
        object: nil,
        queue: OperationQueue.main
    ) { note in
        guard
            let handle = note.object as? FileHandle,
            handle === pipes.stdOutPipe.fileHandleForReading || handle === pipes.stdErrPipe.fileHandleForReading
        else { return }

        defer { handle.waitForDataInBackgroundAndNotify() }

        receiveText(String(bytes: handle.availableData, encoding: .utf8) ?? "")
    })
}

private func startReading(_ pipes: ProcessPipes) {
    pipes.stdOutPipe.fileHandleForReading.waitForDataInBackgroundAndNotify()
    pipes.stdErrPipe.fileHandleForReading.waitForDataInBackgroundAndNotify()
}

private func processSuccessPublisher(
    process: Process,
    observer: NotificationObserverBox,
    aria2Errors: Bool
) -> AnyPublisher<Void, Error> {
    Deferred {
        Future<Void, Error> { promise in
            let promiseBox = FuturePromiseBox(promise)
            DispatchQueue.global(qos: .default).async {
                process.waitUntilExit()
                observer.remove()
                promiseBox.resolve(processCompletionResult(process: process, aria2Errors: aria2Errors))
            }
        }
    }
    .handleEvents(receiveCancel: {
        process.terminate()
        observer.remove()
    })
    .eraseToAnyPublisher()
}

private func runDownloadProcess(
    _ process: Process,
    observer: NotificationObserverBox,
    continuation: AsyncThrowingStream<Progress, Error>.Continuation
) {
    continuation.onTermination = { @Sendable _ in
        process.terminate()
        observer.remove()
    }

    do {
        try process.run()
    } catch {
        observer.remove()
        continuation.finish(throwing: error)
        return
    }

    process.waitUntilExit()
    observer.remove()

    switch processCompletionResult(process: process, aria2Errors: false) {
    case .success:
        continuation.finish()
    case .failure(let error):
        continuation.finish(throwing: error)
    }
}

private func processCompletionResult(process: Process, aria2Errors: Bool) -> Result<Void, Error> {
    guard process.terminationReason == .exit, process.terminationStatus == 0 else {
        if aria2Errors, let aria2cError = Aria2CError(exitStatus: process.terminationStatus) {
            return .failure(aria2cError)
        }

        return .failure(ProcessExecutionError(process: process, standardOutput: "", standardError: ""))
    }

    return .success(())
}

private func downloadProgress() -> Progress {
    let progress = Progress()
    progress.kind = .file
    progress.fileOperationKind = .downloading
    return progress
}

private func runLibUnxip(_ url: URL) async throws -> ProcessOutput {
    let outputDirectory = url.deletingLastPathComponent()
    let outputDescriptor = open(outputDirectory.path, O_RDONLY | O_DIRECTORY)
    guard outputDescriptor >= 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    defer { _ = close(outputDescriptor) }

    let inputDescriptor = open(url.path, O_RDONLY)
    guard inputDescriptor >= 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }

    let input = DataReader.data(readingFrom: inputDescriptor)
    for try await _ in Unxip.makeStream(
        from: .xip(),
        to: .disk(),
        input: DataReader(data: input),
        nil,
        nil,
        .init(compress: true, dryRun: false, output: outputDescriptor)
    ) {}

    return ProcessOutput(status: 0, out: "", err: "")
}

private func systemExecutablePath(named executableName: String) -> Path? {
    let environmentPaths = ProcessInfo.processInfo.environment["PATH"]?
        .split(separator: ":")
        .map(String.init) ?? []
    let fallbackPaths = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
        "/usr/sbin",
        "/sbin"
    ]

    var seenPaths = Set<String>()
    for directory in environmentPaths + fallbackPaths where seenPaths.insert(directory).inserted {
        let candidateURL = URL(fileURLWithPath: directory, isDirectory: true)
            .appendingPathComponent(executableName)

        guard
            FileManager.default.isExecutableFile(atPath: candidateURL.path),
            let candidatePath = Path(url: candidateURL)
        else { continue }

        return candidatePath
    }

    return nil
}
