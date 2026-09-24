// Verify a Sparkle EdDSA signature against the public key embedded in the app.
// Usage: swift verify-update-signature.swift <public-key> <archive> <signature>
import CryptoKit
import Foundation

let arguments = CommandLine.arguments.dropFirst()
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("Usage: verify-update-signature.swift <public-key> <archive> <signature>\n".utf8))
    exit(2)
}
let values = Array(arguments)
guard let keyData = Data(base64Encoded: values[0]),
      let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData),
      let signature = Data(base64Encoded: values[2]),
      let archive = FileManager.default.contents(atPath: values[1]),
      publicKey.isValidSignature(signature, for: archive) else {
    FileHandle.standardError.write(Data("The update signature does not match SPARKLE_PUBLIC_KEY.\n".utf8))
    exit(1)
}
