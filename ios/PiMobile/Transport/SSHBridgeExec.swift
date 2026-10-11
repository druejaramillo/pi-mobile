import Citadel

/// Host bridge exec failures preserve the remote status without exposing raw stderr or retrying the command.
@available(macOS 15.0, *)
struct SSHBridgeExec {
    static func run(client: SSHClient, command: String,
                    perform: (TTYOutput, TTYStdinWriter) async throws -> Void) async throws {
        do { try await client.withExec(command, perform: perform) }
        catch let failure as SSHClient.CommandFailed {
            throw SSHBridgeError.hostBridgeExited(failure.exitCode)
        }
    }
}
