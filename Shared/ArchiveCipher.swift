import Foundation
import CryptoKit
import CommonCrypto

/// Portable authenticated archive encryption. A random salt and nonce are
/// generated for every export; the passphrase and derived key are never saved.
enum ArchiveCipher {
    struct Envelope: Codable {
        var cipherVersion = 1
        let salt: Data
        let rounds: UInt32
        let sealed: Data
    }
    enum Failure: LocalizedError {
        case invalid, passphrase, derivation
        var errorDescription: String? {
            switch self {
            case .invalid: "The encrypted archive is damaged or uses an unsupported format."
            case .passphrase: "Enter the archive passphrase. New encrypted backups need at least 10 characters."
            case .derivation: "The archive key could not be created."
            }
        }
    }
    static func isEncrypted(_ data: Data) -> Bool {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["cipherVersion"] != nil
    }
    static func seal(_ data: Data, passphrase: String) throws -> Data {
        guard passphrase.count >= 10 else { throw Failure.passphrase }
        let salt = SymmetricKey(size: .bits128).withUnsafeBytes { Data($0) }
        let rounds: UInt32 = 210_000
        let key = try derive(passphrase, salt: salt, rounds: rounds)
        let sealed = try AES.GCM.seal(data, using: key)
        guard let combined = sealed.combined else { throw Failure.invalid }
        return try JSONEncoder().encode(Envelope(salt: salt, rounds: rounds, sealed: combined))
    }
    static func open(_ data: Data, passphrase: String) throws -> Data {
        guard !passphrase.isEmpty else { throw Failure.passphrase }
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        guard envelope.cipherVersion == 1, envelope.salt.count == 16,
              (210_000...1_000_000).contains(envelope.rounds) else { throw Failure.invalid }
        let key = try derive(passphrase, salt: envelope.salt, rounds: envelope.rounds)
        return try AES.GCM.open(AES.GCM.SealedBox(combined: envelope.sealed), using: key)
    }
    private static func derive(_ passphrase: String, salt: Data, rounds: UInt32) throws -> SymmetricKey {
        var bytes = [UInt8](repeating: 0, count: 32)
        let result = passphrase.withCString { password in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), password, passphrase.utf8.count,
                    saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), rounds, &bytes, bytes.count)
            }
        }
        guard result == kCCSuccess else { throw Failure.derivation }
        defer { bytes.withUnsafeMutableBytes { $0.initializeMemory(as: UInt8.self, repeating: 0) } }
        return SymmetricKey(data: bytes)
    }
}
