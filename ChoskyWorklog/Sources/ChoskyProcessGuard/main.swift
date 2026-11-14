import Darwin
import Foundation

nonisolated(unsafe) private var guardedChildPID: pid_t = 0
nonisolated(unsafe) private var terminationRequested: sig_atomic_t = 0

private func stopChild(_ signal: Int32) {
    let pid = guardedChildPID
    if pid > 0 {
        Darwin.kill(pid, signal)
    }
}

private func terminationSignal(_ signal: Int32) {
    terminationRequested = 1
    stopChild(SIGTERM)
}

guard CommandLine.arguments.count >= 2 else {
    FileHandle.standardError.write(Data("Uso: ChoskyProcessGuard <ejecutable> [argumentos]\n".utf8))
    exit(64)
}

let originalParent = getppid()
let child = Process()
child.executableURL = URL(fileURLWithPath: CommandLine.arguments[1])
child.arguments = Array(CommandLine.arguments.dropFirst(2))
child.standardOutput = FileHandle.standardOutput
child.standardError = FileHandle.standardError

signal(SIGTERM, terminationSignal)
signal(SIGINT, terminationSignal)
signal(SIGHUP, terminationSignal)

do {
    try child.run()
    guardedChildPID = child.processIdentifier
    if terminationRequested != 0 {
        stopChild(SIGTERM)
    }
} catch {
    FileHandle.standardError.write(Data("No se pudo iniciar el auxiliar: \(error)\n".utf8))
    exit(70)
}

var terminationPolls = 0
while child.isRunning {
    if terminationRequested != 0 {
        if terminationPolls >= 15 {
            stopChild(SIGKILL)
        }
        terminationPolls += 1
        usleep(100_000)
        continue
    }
    let currentParent = getppid()
    if currentParent == 1 || currentParent != originalParent || Darwin.kill(originalParent, 0) != 0 {
        child.terminate()
        for _ in 0..<20 where child.isRunning {
            usleep(100_000)
        }
        if child.isRunning {
            stopChild(SIGKILL)
        }
        break
    }
    usleep(250_000)
}

child.waitUntilExit()
exit(child.terminationStatus)
