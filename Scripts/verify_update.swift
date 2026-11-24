import CryptoKit
import Foundation

guard CommandLine.arguments.count == 4,
      let signature = Data(base64Encoded: CommandLine.arguments[2]),
      let publicKey = Data(base64Encoded: CommandLine.arguments[3]) else {
    throw CocoaError(.fileReadCorruptFile)
}

let archive = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]), options: .mappedIfSafe)
let key = try Curve25519.Signing.PublicKey(rawRepresentation: publicKey)
guard key.isValidSignature(signature, for: archive) else {
    FileHandle.standardError.write(Data("Sparkle signature does not match the release archive and public key.\n".utf8))
    exit(EXIT_FAILURE)
}
