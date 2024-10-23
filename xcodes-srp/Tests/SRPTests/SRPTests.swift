import XCTest
import BigNum
import Crypto
@testable import SRP

final class SRPTests: XCTestCase {

    func testSRPSharedSecret() {
        let username = "adamfowler"
        let password = "testpassword"
        let configuration = SRPConfiguration<Insecure.SHA1>(.N2048)
        let client = SRPClient<Insecure.SHA1>(configuration: configuration)
        let server = SRPServer<Insecure.SHA1>(configuration: configuration)

        let (salt, verifier) = client.generateSaltAndVerifier(username: username, password: password)

        let clientKeys = client.generateKeys()
        let serverKeys = server.generateKeys(verifier: verifier)

        do {
            let sharedSecret = try client.calculateSharedSecret(
                username: username,
                password: password,
                salt: salt,
                clientKeys: clientKeys,
                serverPublicKey: serverKeys.public)

            let serverSharedSecret = try server.calculateSharedSecret(
                clientPublicKey: clientKeys.public,
                serverKeys: serverKeys,
                verifier: verifier)

            XCTAssertEqual(sharedSecret, serverSharedSecret)
        } catch {
            XCTFail("\(error)")
        }
    }

    func testVerifySRP<H: HashFunction>(configuration: SRPConfiguration<H>) {
        let username = "adamfowler"
        let password = "testpassword"
        let client = SRPClient<H>(configuration: configuration)
        let server = SRPServer<H>(configuration: configuration)

        let (salt, verifier) = client.generateSaltAndVerifier(username: username, password: password)

        do {
            // client initiates authentication
            let clientKeys = client.generateKeys()
            // provides the server with an A value and username from which it gets the password verifier.
            // server initiates authentication
            let serverKeys = server.generateKeys(verifier: verifier)
            // server passes back B value and a salt which was attached to the user
            // client calculates verification code from username, password, current authenticator state, B and salt
            let clientSharedSecret = try client.calculateSharedSecret(username: username, password: password, salt: salt, clientKeys: clientKeys, serverPublicKey: serverKeys.public)
            let clientProof = client.calculateClientProof(username: username, salt: salt, clientPublicKey: clientKeys.public, serverPublicKey: serverKeys.public, sharedSecret: clientSharedSecret)
            // client passes proof key to server
            // server validates the key and then returns a server validation key
            let serverSharedSecret = try server.calculateSharedSecret(clientPublicKey: clientKeys.public, serverKeys: serverKeys, verifier: verifier)
            let serverProof = try server.verifyClientProof(proof: clientProof, username: username, salt: salt, clientPublicKey: clientKeys.public, serverPublicKey: serverKeys.public, sharedSecret: serverSharedSecret)
            // client verifies server validation key
            try client.verifyServerProof(serverProof: serverProof, clientProof: clientProof, clientKeys: clientKeys, sharedSecret: clientSharedSecret)
        } catch {
            XCTFail("\(error)")
        }
    }

    func testVerifySRP() {
        testVerifySRP(configuration: SRPConfiguration<SHA256>(.N1024))
        testVerifySRP(configuration: SRPConfiguration<SHA256>(.N1536))
        testVerifySRP(configuration: SRPConfiguration<SHA256>(.N2048))
        testVerifySRP(configuration: SRPConfiguration<SHA256>(.N3072))
        testVerifySRP(configuration: SRPConfiguration<Insecure.SHA1>(.N4096))
        testVerifySRP(configuration: SRPConfiguration<Insecure.SHA1>(.N6144))
        testVerifySRP(configuration: SRPConfiguration<Insecure.SHA1>(.N8192))
    }

    func testVerifySRPCustomConfiguration() {
        testVerifySRP(configuration: SRPConfiguration<SHA384>(N: BigNum(37), g: BigNum(3)))
    }

    func testClientSessionProof() {
        let configuration = SRPConfiguration<Insecure.SHA1>(.N1024)
        let username = "alice"
        let salt = "bafa3be2813c9326".bytes(using: .hexadecimal)!
        let A = BigNum(hex: "b525e8fe2eac8f5da6b3220e66a0ab6f833a59d5f079fe9ddcdf111a22eaec95850374d9d7597f45497eb429bcde5057a450948de7d48edc034264916a01e6c0690e14b0a527f107d3207fd2214653c9162f5745e7cbeb19a550a072d4600ce8f4ef778f6d6899ba718adf0a462e7d981ed689de93ea1bda773333f23ebb4a9b")!
        let B = BigNum(hex: "2bfc8559a022497f1254af3c76786b95cb0dfb449af15501aa51eefe78947d7ef06df4fcc07a899bcaae0e552ca72c7a1f3016f3ec357a86a1428dad9f98cb8a69d405404e57e9aaf01e51a46a73b3fc7bc1d212569e4a882ae6d878599e098c89033838ec069fe368a49461f531e5b4662700d56d8c252d0aea9da6abe9b014")!
        let secret = "b6288955afd690a13686d65886b5f82018515df3".bytes(using: .hexadecimal)!
        let clientProof = SRP<Insecure.SHA1>.calculateClientProof(configuration: configuration, username: username, salt: salt, clientPublicKey: SRPKey(A), serverPublicKey: SRPKey(B), hashSharedSecret: secret)

        XCTAssertEqual(clientProof.hexdigest(), "e4c5c2e145ea2de18d0cc1ac9dc2a0d0988706d6")
    }

    func testServerSessionProof() {
        let A = BigNum(hex: "eade4992a46182e9ffe2e69f3e2639ca5f8c29b2868083c45d0972b72bb6003911b64a7ea6738061d705d368ddbe2bdb251bec63184db09b8990d8a7415dc449fbab720626fc25d6bd33c32234973c1e41c25b18d1824590c807c491221be5493878bd27a5ca507fd3963c849b07a9ec413e13253c6c61e7f3219b247cfa574a")!
        let secret = "d89740e18a9fb597aef8f2ecc0e66f4b31c2ae08".bytes(using: .hexadecimal)!
        let clientProof = "e1a8629a723039a61be91a173ab6260fc582192f".bytes(using: .hexadecimal)!

        let serverProof = SRP<Insecure.SHA1>.calculateServerVerification(clientPublicKey: SRPKey(A), clientProof: clientProof, sharedSecret: secret)

        XCTAssertEqual(serverProof.hexdigest(), "8342bd06bdf4d263de2df9a56da8e581fb38c769")
    }

    // Test results against RFC5054 Appendix B
    func testRFC5054Appendix() throws {
        let username = "alice"
        let password = "password123"
        let salt = "BEB25379D1A8581EB5A727673A2441EE".bytes(using: .hexadecimal)!
        let configuration = SRPConfiguration<Insecure.SHA1>(.N1024)
        let client = SRPClient<Insecure.SHA1>(configuration: configuration)

        XCTAssertEqual(configuration.k.hex, "7556AA045AEF2CDD07ABAF0F665C3E818913186F".lowercased())

        let verifier = client.generatePasswordVerifier(username: username, password: password, salt: salt)

        XCTAssertEqual(verifier.hex, "7E273DE8696FFC4F4E337D05B4B375BEB0DDE1569E8FA00A9886D8129BADA1F1822223CA1A605B530E379BA4729FDC59F105B4787E5186F5C671085A1447B52A48CF1970B4FB6F8400BBF4CEBFBB168152E08AB5EA53D15C1AFF87B2B9DA6E04E058AD51CC72BFC9033B564E26480D78E955A5E29E7AB245DB2BE315E2099AFB".lowercased())

        let a = BigNum(hex: "60975527035CF2AD1989806F0407210BC81EDC04E2762A56AFD529DDDA2D4393")!
        // copied from client.swift
        let A = configuration.g.power(a, modulus: configuration.N)

        XCTAssertEqual(A.hex, "61D5E490F6F1B79547B0704C436F523DD0E560F0C64115BB72557EC44352E8903211C04692272D8B2D1A5358A2CF1B6E0BFCF99F921530EC8E39356179EAE45E42BA92AEACED825171E1E8B9AF6D9C03E1327F44BE087EF06530E69F66615261EEF54073CA11CF5858F0EDFDFE15EFEAB349EF5D76988A3672FAC47B0769447B".lowercased())

        let b = BigNum(hex: "E487CB59D31AC550471E81F00F6928E01DDA08E974A004F49E61F5D105284D20")!
        // copied from server.swift
        let B = (configuration.k * verifier + configuration.g.power(b, modulus: configuration.N)) % configuration.N

        XCTAssertEqual(B.hex, "BD0C61512C692C0CB6D041FA01BB152D4916A1E77AF46AE105393011BAF38964DC46A0670DD125B95A981652236F99D9B681CBF87837EC996C6DA04453728610D0C6DDB58B318885D7D82C7F8DEB75CE7BD4FBAA37089E6F9C6059F388838E7A00030B331EB76840910440B1B27AAEAEEB4012B7D7665238A8E3FB004B117B58".lowercased())

        let u = SRP<Insecure.SHA1>.calculateU(clientPublicKey: A.bytes, serverPublicKey: B.bytes, pad: configuration.sizeN)

        XCTAssertEqual(u.hex, "CE38B9593487DA98554ED47D70A7AE5F462EF019".lowercased())

        let sharedSecret = try client.calculateSharedSecret(username: username, password: password, salt: salt, clientKeys: SRPKeyPair(public: SRPKey(A), private: SRPKey(a)), serverPublicKey: SRPKey(B))

        XCTAssertEqual(sharedSecret.number.hex, "B0DC82BABCF30674AE450C0287745E7990A3381F63B387AAF271A10D233861E359B48220F7C4693C9AE12B0A6F67809F0876E2D013800D6C41BB59B6D5979B5C00A172B4A2A5903A0BDCAF8A709585EB2AFAFA8F3499B200210DCC1F10EB33943CD67FC88A2F39A4BE5BEC4EC0A3212DC346D7E474B29EDE8A469FFECA686E5A".lowercased())
    }

    /// Test library against Mozilla test vectors https://wiki.mozilla.org/Identity/AttachedServices/KeyServerProtocol#SRP_Verifier
    func testMozillaTestVectors() throws {
        let username = "andré@example.org"
        let password = "00f9b71800ab5337d51177d8fbc682a3653fa6dae5b87628eeec43a18af59a9d".bytes(using: .hexadecimal)!
        let salt = "00f1000000000000000000000000000000000000000000000000000000000179".bytes(using: .hexadecimal)!
        let configuration = SRPConfiguration<SHA256>(.N2048)
        let client = SRPClient(configuration: configuration)

        XCTAssertEqual(configuration.k.dec, "2590038599070950300691544216303772122846747035652616593381637186118123578112")

        let message = [UInt8]("\(username):".utf8) + password
        let verifier = client.generatePasswordVerifier(message: message, salt: salt)

        XCTAssertEqual(verifier.hex, "173ffa0263e63ccfd6791b8ee2a40f048ec94cd95aa8a3125726f9805e0c8283c658dc0b607fbb25db68e68e93f2658483049c68af7e8214c49fde2712a775b63e545160d64b00189a86708c69657da7a1678eda0cd79f86b8560ebdb1ffc221db360eab901d643a75bf1205070a5791230ae56466b8c3c1eb656e19b794f1ea0d2a077b3a755350208ea0118fec8c4b2ec344a05c66ae1449b32609ca7189451c259d65bd15b34d8729afdb5faff8af1f3437bbdc0c3d0b069a8ab2a959c90c5a43d42082c77490f3afcc10ef5648625c0605cdaace6c6fdc9e9a7e6635d619f50af7734522470502cab26a52a198f5b00a279858916507b0b4e9ef9524d6")
        
        let b = BigNum(hex: "00f3000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000f")!
        // copied from server.swift
        let B = (configuration.k * verifier + configuration.g.power(b, modulus: configuration.N)) % configuration.N
        
        XCTAssertEqual(B.hex, "22ce5a7b9d81277172caa20b0f1efb4643b3becc53566473959b07b790d3c3f08650d5531c19ad30ebb67bdb481d1d9cf61bf272f8439848fdda58a4e6abc5abb2ac496da5098d5cbf90e29b4b110e4e2c033c70af73925fa37457ee13ea3e8fde4ab516dff1c2ae8e57a6b264fb9db637eeeae9b5e43dfaba9b329d3b8770ce89888709e026270e474eef822436e6397562f284778673a1a7bc12b6883d1c21fbc27ffb3dbeb85efda279a69a19414969113f10451603065f0a012666645651dde44a52f4d8de113e2131321df1bf4369d2585364f9e536c39a4dce33221be57d50ddccb4384e3612bbfd03a268a36e4f7e01de651401e108cc247db50392")
        
        let a = BigNum(hex: "00f2000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000d3d7")!
        // copied from client.swift
        let A = configuration.g.power(a, modulus: configuration.N)
        
        XCTAssertEqual(A.hex, "7da76cb7e77af5ab61f334dbd5a958513afcdf0f47ab99271fc5f7860fe2132e5802ca79d2e5c064bb80a38ee08771c98a937696698d878d78571568c98a1c40cc6e7cb101988a2f9ba3d65679027d4d9068cb8aad6ebff0101bab6d52b5fdfa81d2ed48bba119d4ecdb7f3f478bd236d5749f2275e9484f2d0a9259d05e49d78a23dd26c60bfba04fd346e5146469a8c3f010a627be81c58ded1caaef2363635a45f97ca0d895cc92ace1d09a99d6beb6b0dc0829535c857a419e834db12864cd6ee8a843563b0240520ff0195735cd9d316842d5d3f8ef7209a0bb4b54ad7374d73e79be2c3975632de562c596470bb27bad79c3e2fcddf194e1666cb9fc")
        
        let u = SRP<SHA256>.calculateU(clientPublicKey: A.bytes, serverPublicKey: B.bytes, pad: configuration.sizeN)

        XCTAssertEqual(u.hex, "b284aa1064e8775150da6b5e2147b47ca7df505bed94a6f4bb2ad873332ad732")

        let sharedSecret = try client.calculateSharedSecret(message: message, salt: salt, clientKeys: SRPKeyPair(public: SRPKey(A), private: SRPKey(a)), serverPublicKey: SRPKey(B))

        XCTAssertEqual(sharedSecret.hex, "92aaf0f527906aa5e8601f5d707907a03137e1b601e04b5a1deb02a981f4be037b39829a27dba50f1b27545ff2e28729c2b79dcbdd32c9d6b20d340affab91a626a8075806c26fe39df91d0ad979f9b2ee8aad1bc783e7097407b63bfe58d9118b9b0b2a7c5c4cdebaf8e9a460f4bf6247b0da34b760a59fac891757ddedcaf08eed823b090586c63009b2d740cc9f5397be89a2c32cdcfe6d6251ce11e44e6ecbdd9b6d93f30e90896d2527564c7eb9ff70aa91acc0bac1740a11cd184ffb989554ab58117c2196b353d70c356160100ef5f4c28d19f6e59ea2508e8e8aac6001497c27f362edbafb25e0f045bfdf9fb02db9c908f10340a639fe84c31b27")
    }
    
    static var allTests = [
        ("testSRPSharedSecret", testSRPSharedSecret),
        ("testVerifySRP", testVerifySRP),
        ("testVerifySRPCustomConfiguration", testVerifySRPCustomConfiguration),
        ("testClientSessionProof", testClientSessionProof),
        ("testServerSessionProof", testServerSessionProof),
        ("testRFC5054Appendix", testRFC5054Appendix),
        ("testMozillaTestVectors", testMozillaTestVectors),
    ]
}

extension String {
    enum ExtendedEncoding {
        case hexadecimal
    }

    func bytes(using encoding:ExtendedEncoding) -> [UInt8]? {
        guard self.count % 2 == 0 else { return nil }

        var bytes: [UInt8] = []

        var indexIsEven = true
        for i in self.indices {
            if indexIsEven {
                let byteRange = i...self.index(after: i)
                guard let byte = UInt8(self[byteRange], radix: 16) else { return nil }
                bytes.append(byte)
            }
            indexIsEven.toggle()
        }
        return bytes
    }
}
