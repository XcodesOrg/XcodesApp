import Path
import CryptoKit
import Version
@testable import Xcodes
import XCTest
import CommonCrypto
import BigNum
import SRP

class AppStateUpdateTests: XCTestCase {
    var subject: AppState!
    
    override func setUpWithError() throws {
        Current = .mock
        subject = AppState()
    }

    func testDoesNotReplaceInstallState() throws {
        subject.allXcodes = [
            Xcode(version: Version("0.0.0")!, installState: .installing(.unarchiving), selected: false, icon: nil)
        ]
        
        subject.updateAllXcodes(
            availableXcodes: [
                AvailableXcode(version: Version("0.0.0")!, url: URL(string: "https://apple.com/xcode.xip")!, filename: "mock.xip", releaseDate: nil)
            ], 
            installedXcodes: [
            ], 
            selectedXcodePath: nil
        )
        
        XCTAssertEqual(subject.allXcodes[0].installState, .installing(.unarchiving))
    }
    
    func testRemovesUninstalledVersion() throws {
        subject.allXcodes = [
            Xcode(version: Version("0.0.0")!, installState: .installed(Path("/Applications/Xcode-0.0.0.app")!), selected: true, icon: NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil))
        ]
        
        subject.updateAllXcodes(
            availableXcodes: [
                AvailableXcode(version: Version("0.0.0")!, url: URL(string: "https://apple.com/xcode.xip")!, filename: "mock.xip", releaseDate: nil)
            ], 
            installedXcodes: [
            ], 
            selectedXcodePath: nil
        )
        
        XCTAssertEqual(subject.allXcodes[0].installState, .notInstalled)
    }
    
    func testDeterminesIfInstalledByBuildMetadataAlone() throws {
        Current.defaults.string = { key in
            if key == "dataSource" {
                return "apple" 
            } else {
                return nil
            }
        }
        
        subject.allXcodes = [
        ]
        
        subject.updateAllXcodes(
            availableXcodes: [
                // Note "GM" prerelease identifier
                AvailableXcode(version: Version("0.0.0-GM+ABC123")!, url: URL(string: "https://apple.com/xcode.xip")!, filename: "mock.xip", releaseDate: nil)
            ], 
            installedXcodes: [
                InstalledXcode(path: Path("/Applications/Xcode-0.0.0.app")!)!
            ], 
            selectedXcodePath: nil
        )
        
        XCTAssertEqual(subject.allXcodes[0].version, Version("0.0.0+ABC123")!) 
        XCTAssertEqual(subject.allXcodes[0].installState, .installed(Path("/Applications/Xcode-0.0.0.app")!))
        XCTAssertEqual(subject.allXcodes[0].selected, false)
    }
    
    func testAdjustedVersionsAreUsedToLookupAvailableXcode() throws {
        Current.defaults.string = { key in
            if key == "dataSource" {
                return "apple" 
            } else {
                return nil
            }
        }

        subject.allXcodes = [
        ]
        
        subject.updateAllXcodes(
            availableXcodes: [
                // Note "GM" prerelease identifier
                AvailableXcode(version: Version("0.0.0-GM+ABC123")!, url: URL(string: "https://apple.com/xcode.xip")!, filename: "mock.xip", releaseDate: nil, sdks: .init(iOS: .init("14.3")))
            ], 
            installedXcodes: [
                InstalledXcode(path: Path("/Applications/Xcode-0.0.0.app")!)!
            ], 
            selectedXcodePath: nil
        )
        
        XCTAssertEqual(subject.allXcodes[0].version, Version("0.0.0+ABC123")!) 
        XCTAssertEqual(subject.allXcodes[0].installState, .installed(Path("/Applications/Xcode-0.0.0.app")!))
        XCTAssertEqual(subject.allXcodes[0].selected, false)
        // XCModel types aren't equatable, so just check for non-nil for now
        XCTAssertNotNil(subject.allXcodes[0].sdks)
    }

    func testAppendingInstalledVersionThatIsNotAvailable() {
        subject.allXcodes = [
        ]
        
        subject.updateAllXcodes(
            availableXcodes: [
                AvailableXcode(version: Version("1.2.3")!, url: URL(string: "https://apple.com/xcode.xip")!, filename: "mock.xip", releaseDate: nil, sdks: .init(iOS: .init("14.3")))
            ], 
            installedXcodes: [
                // There's a version installed which for some reason isn't listed online
                InstalledXcode(path: Path("/Applications/Xcode-0.0.0.app")!)!
            ], 
            selectedXcodePath: nil
        )
        
        XCTAssertEqual(subject.allXcodes.map(\.version), [Version("1.2.3")!, Version("0.0.0+ABC123")!]) 
    }
    
    
    func testIdenticalBuilds_KeepsReleaseVersion_WithNeitherInstalled() {
        Current.defaults.string = { key in
            if key == "dataSource" {
                return "xcodeReleases" 
            } else {
                return nil
            }
        }

        subject.allXcodes = [
        ]
        
        subject.updateAllXcodes(
            availableXcodes: [
                AvailableXcode(version: Version("12.4.0+12D4e")!, url: URL(string: "https://apple.com/xcode.xip")!, filename: "mock.xip", releaseDate: nil),
                AvailableXcode(version: Version("12.4.0-RC+12D4e")!, url: URL(string: "https://apple.com/xcode.xip")!, filename: "mock.xip", releaseDate: nil),
            ], 
            installedXcodes: [
            ], 
            selectedXcodePath: nil
        )
        
        XCTAssertEqual(subject.allXcodes.map(\.version), [Version("12.4.0+12D4e")!])
        XCTAssertEqual(subject.allXcodes.map(\.identicalBuilds), [[Version("12.4.0+12D4e")!, Version("12.4.0-RC+12D4e")!]])
    }
    
    func testIdenticalBuilds_DoNotMergeReleaseVersions() {
        Current.defaults.string = { key in
            if key == "dataSource" {
                return "xcodeReleases" 
            } else {
                return nil
            }
        }

        subject.allXcodes = [
        ]
        
        subject.updateAllXcodes(
            availableXcodes: [
                AvailableXcode(version: Version("3.2.3+10M2262")!, url: URL(string: "https://apple.com/xcode.xip")!, filename: "mock.xip", releaseDate: nil),
                AvailableXcode(version: Version("3.2.3+10M2262")!, url: URL(string: "https://apple.com/xcode.xip")!, filename: "mock.xip", releaseDate: nil),
            ], 
            installedXcodes: [
            ], 
            selectedXcodePath: nil
        )
        
        XCTAssertEqual(subject.allXcodes.map(\.version), [Version("3.2.3+10M2262")!, Version("3.2.3+10M2262")!])
        XCTAssertEqual(subject.allXcodes.map(\.identicalBuilds), [[], []])
    }
    
    func testIdenticalBuilds_KeepsReleaseVersion_WithPrereleaseInstalled() {
        Current.defaults.string = { key in
            if key == "dataSource" {
                return "xcodeReleases" 
            } else {
                return nil
            }
        }

        subject.allXcodes = [
        ]
        
        Current.files.contentsAtPath = { path in
            if path.contains("Info.plist") {
                return """
                    <?xml version="1.0" encoding="UTF-8"?>
                    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
                    <plist version="1.0">
                    <dict>
                        <key>CFBundleIdentifier</key>
                        <string>com.apple.dt.Xcode</string>
                        <key>CFBundleShortVersionString</key>
                        <string>12.4.0</string>
                    </dict>
                    </plist>
                    """.data(using: .utf8)
            }
            else if path.contains("version.plist") {
                return """
                    <?xml version="1.0" encoding="UTF-8"?>
                    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
                    <plist version="1.0">
                    <dict>
                        <key>ProductBuildVersion</key>
                        <string>12D4e</string>
                    </dict>
                    </plist>
                    """.data(using: .utf8)
            }
            else {
                return nil
            }
        }
        
        subject.updateAllXcodes(
            availableXcodes: [
                AvailableXcode(version: Version("12.4.0+12D4e")!, url: URL(string: "https://apple.com/xcode.xip")!, filename: "mock.xip", releaseDate: nil),
                AvailableXcode(version: Version("12.4.0-RC+12D4e")!, url: URL(string: "https://apple.com/xcode.xip")!, filename: "mock.xip", releaseDate: nil),
            ], 
            installedXcodes: [
                InstalledXcode(path: Path("/Applications/Xcode-12.4.0-RC.app")!)!
            ], 
            selectedXcodePath: nil
        )
        
        XCTAssertEqual(subject.allXcodes.map(\.version), [Version("12.4.0+12D4e")!])
        XCTAssertEqual(subject.allXcodes.map(\.identicalBuilds), [[Version("12.4.0+12D4e")!, Version("12.4.0-RC+12D4e")!]])
    }
    
    func testIdenticalBuilds_AppleDataSource_DoNotMergeVersionsWithoutBuildIdentifiers() {
        Current.defaults.string = { key in
            if key == "dataSource" {
                return "apple" 
            } else {
                return nil
            }
        }

        subject.allXcodes = [
        ]
        
        subject.updateAllXcodes(
            availableXcodes: [
                AvailableXcode(version: Version("12.4.0")!, url: URL(string: "https://apple.com/xcode.xip")!, filename: "mock.xip", releaseDate: nil),
                AvailableXcode(version: Version("12.3.0-RC")!, url: URL(string: "https://apple.com/xcode.xip")!, filename: "mock.xip", releaseDate: nil),
            ], 
            installedXcodes: [
            ], 
            selectedXcodePath: nil
        )
        
        XCTAssertEqual(subject.allXcodes.map(\.version), [Version("12.4.0")!, Version("12.3.0-RC")!])
        XCTAssertEqual(subject.allXcodes.map(\.identicalBuilds), [[], []])
    }

    func sha256(data : Data) -> Data {
        var hash = [UInt8](repeating: 0,  count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }
        return Data(hash)
    }

    func testSIRP() throws {
        /*
         Obtaind by running fastlane spaceauth --verbose -u anand.appleseed@example.com with some custom logging

         Starting SIRP Apple ID login
         a: {"a":"VLEKLa+n2cyeYNWbECm45CuS4kCdCxodlTDGlW1FKaUyOrv/RbtN2sM0pVE12zI7k3VkocPC3rN5DZBIkahR6I8JHj/J97dtTvzsR+aNRWTYCT2HGP1PBI0QArp3eitAbFqTWI4+Zw+oOnV8+AYdH/wjbq7gOK4C4dvIHE+FzRwIlmguPb5qu2r47R9W3y1msVdoUGlFBOMOMb7Gyq7F0MaEIFH63lNzGomwq74mfss/cFqurd6fxU+Y7tdVTPZw1GWyBEPiXWpk8sNm2zE+S6zWo5tOsICprU75IC9galh1igfzN7VNe0SUFLNFTbFK+Bb1SFAOrAbBZOmyOG5uSQ==","accountName":"anand.appleseed@example.com","protocols":["s2k","s2k_fo"]}
         Received SIRP signin init response: {"iteration"=>20309, "salt"=>"fIjNflgqSJXACWwwvhDU+w==", "protocol"=>"s2k", "b"=>"PMbU75wwG6rDTySXn2ASWyfQuPoW5ham15SzIscpInwOPE2uk7sePsW4ra0dHcLDUMFQn/LgBggIKOo7YZ9hf1VReiAzXwSKSHdJHjHUURTC2eNpANGUPO1qzuXYgc/MP3MR+GipKHsz+KTLT+8wLjNaiCIHsL/7evJBMw9QqiwhyXlAIm5mGZfhdTVbGpLz2/QzrFmI6pUTrHpio6m1Q74DH3FBxxIeiIcuEdGdeVt9iUweowBRyf2woasTvSV1fbMQbl+lsWPwzt/a73+J30eOGFdSubqSVYh2pV0OLqRz7zPzJars12teCWUV+0WUIaxb14Mp7tlmqcTPuqZe9w==", "c"=>"d-533-eccbc4e9-9564-11ef-84a6-018111c8cc60:PRN"}
         encrypted_password: 40532b4de9353fc537dc62ee84eacebd7ecb5ec26efca98bd01b0380e302100f 32
         bb: 7672345903537871991962715758896796468138571329014139041563495295907370682045347022183702983061785424983278857706335295545994877883818377653653442007828499221881058994644619578239367613808278802931379172730746665773282250642455690715139985911303055104847971308813151718669484181874342088801251592138154023949370621963319928723678385968989085032385411532317797659749008135679504901238396934480214258070495365760319076978872181485178648397361564241555189629889320567561713407566532187413091018319494367244540399242523126294027225387432028960726767445027313453858210115810946641002311734776929442587065438110307439763191
         x: 726436461883978586175291668001486484510457416477927591386889224605776454162
         u: 49415306980415573732801389514223606278850554555635359953422678270536095422201
         private 23161374166158551996079451276150657702422963034121842124445818241826569345033578345120284496449280736328513302994568402583647660370960353252836732307301957364261384324957527103960720408713825427474127658415917826326829664923997096839970397226662116904369925262192683131695683487505523842260218490007066160096482662715246662018133837725691586205535995663334471723776536640973591229093933458552240634178864509015968350855952558520147559154646484379002445961375384929682566525908284011230815908584648931495968206840416022306138033496705677078512266958633477047047323620540878121579549170392075029336954975132431417099801
         S: 4f75b6ea99c2d7d121357cce80c75c8e1bf74a65e8f66f75f8f66a481301afb8bebf0e54a3fac4f8bfdd60c77d6e670c87968b341f62175e25eb1d4f496e4e6596e1a387f2840688a35002419b70115b7902a46544cc7b31eb4c909c0acaeb752835d1562a687c431421510ebc7535c007a2bd12a4f7696c8c96a75a491b1eb9189ade2bef23dd5b0bb962b4f03e7fba7f6ba6fe67ba34cc18647daf3e474876f85dac5a15eb51c99d1ed78783579ffd6c8b6911f72564d87dc8f76519c8fc1535b83743ed5f7d6b8461d7154ce2a874cbb45bf63018352b9b997fbafbd6b15eac2a544a801c0152470796f3b69a84a4a653e5186b30efeeb148ff3c32ab8e08
         K: c5207f707186a52f1adee41bf0a7bc41e51e6dffc25cdaeca8acb7de2710b20a
         hN: 65908899099613711898698321155848703477601840791750658211391687862255842366922
         hG: 23094592799618609623465742609366149076596436609130823198107630312273622653270
         hxor 73599884097654065452785151481733181870375477364472235597514429707329935690908
         response: {"accountName":"anand.appleseed@example.com","c":"d-533-eccbc4e9-9564-11ef-84a6-018111c8cc60:PRN","m1":"f/Bkq8gBTYxl7SyiRd4SXTyE/jM/g6E0mVyZIQDIsPg=","m2":"R2rgqC9cMAtWiXUImOrvs4oF+ccibf8KaFsZQ22WokM=","rememberMe":false}
         */

        let publicKey = Data(base64Encoded:  "VLEKLa+n2cyeYNWbECm45CuS4kCdCxodlTDGlW1FKaUyOrv/RbtN2sM0pVE12zI7k3VkocPC3rN5DZBIkahR6I8JHj/J97dtTvzsR+aNRWTYCT2HGP1PBI0QArp3eitAbFqTWI4+Zw+oOnV8+AYdH/wjbq7gOK4C4dvIHE+FzRwIlmguPb5qu2r47R9W3y1msVdoUGlFBOMOMb7Gyq7F0MaEIFH63lNzGomwq74mfss/cFqurd6fxU+Y7tdVTPZw1GWyBEPiXWpk8sNm2zE+S6zWo5tOsICprU75IC9galh1igfzN7VNe0SUFLNFTbFK+Bb1SFAOrAbBZOmyOG5uSQ==".data(using: .utf8)!)

        let clientKeys = SRPKeyPair(public: .init([UInt8](publicKey!)),
                              private: .init(BigNum("23161374166158551996079451276150657702422963034121842124445818241826569345033578345120284496449280736328513302994568402583647660370960353252836732307301957364261384324957527103960720408713825427474127658415917826326829664923997096839970397226662116904369925262192683131695683487505523842260218490007066160096482662715246662018133837725691586205535995663334471723776536640973591229093933458552240634178864509015968350855952558520147559154646484379002445961375384929682566525908284011230815908584648931495968206840416022306138033496705677078512266958633477047047323620540878121579549170392075029336954975132431417099801")!))

        let password = sha256(data: "example".data(using: .utf8)!)
        let salt = Data(base64Encoded: "fIjNflgqSJXACWwwvhDU+w==".data(using: .utf8)!)!
        let iterations: Int = 20309
        let derivedKeyLength: Int = 32
        var keyArray = Array<UInt8>(repeating: 0, count: derivedKeyLength)

        let result:Int32 = keyArray.withUnsafeMutableBytes { keyBytes -> Int32 in
            let keyBuffer = UnsafeMutablePointer<UInt8>(keyBytes.baseAddress!.assumingMemoryBound(to: UInt8.self))
            return password.withUnsafeBytes { passwordDigestBytes -> Int32 in
                let passwordBuffer = UnsafePointer<UInt8>(passwordDigestBytes.baseAddress!.assumingMemoryBound(to: UInt8.self))
                return salt.withUnsafeBytes { saltBytes -> Int32 in
                    let saltBuffer = UnsafePointer<UInt8>(saltBytes.baseAddress!.assumingMemoryBound(to: UInt8.self))
                    return  CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBuffer,
                        password.count,
                        saltBuffer,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations),
                        keyBuffer,
                        derivedKeyLength)

                }
            }
        }

        let expectedKey: [UInt8] = [0x40, 0x53, 0x2b, 0x4d, 0xe9, 0x35, 0x3f, 0xc5, 0x37, 0xdc, 0x62, 0xee, 0x84, 0xea, 0xce, 0xbd, 0x7e, 0xcb, 0x5e, 0xc2, 0x6e, 0xfc, 0xa9, 0x8b, 0xd0, 0x1b, 0x03, 0x80, 0xe3, 0x02, 0x10, 0x0f]

        XCTAssertEqual(expectedKey, keyArray)

        let decodedB = Data(base64Encoded: "PMbU75wwG6rDTySXn2ASWyfQuPoW5ham15SzIscpInwOPE2uk7sePsW4ra0dHcLDUMFQn/LgBggIKOo7YZ9hf1VReiAzXwSKSHdJHjHUURTC2eNpANGUPO1qzuXYgc/MP3MR+GipKHsz+KTLT+8wLjNaiCIHsL/7evJBMw9QqiwhyXlAIm5mGZfhdTVbGpLz2/QzrFmI6pUTrHpio6m1Q74DH3FBxxIeiIcuEdGdeVt9iUweowBRyf2woasTvSV1fbMQbl+lsWPwzt/a73+J30eOGFdSubqSVYh2pV0OLqRz7zPzJars12teCWUV+0WUIaxb14Mp7tlmqcTPuqZe9w==".data(using: .utf8)!)!

        let client = SRPClient(configuration: SRPConfiguration<SHA256>(.N2048))
        let sharedSecret = try client.calculateSharedSecret(password: Data(keyArray), salt: [UInt8](salt), clientKeys: clientKeys, serverPublicKey: .init([UInt8](decodedB)))

        let accountName = "anand.appleseed@example.com"
        let m1 = client.calculateClientProof(username: accountName, salt: [UInt8](salt), clientPublicKey: clientKeys.public, serverPublicKey: .init([UInt8](decodedB)), sharedSecret: .init(sharedSecret.bytes))
        let m2 = client.calculateServerProof(clientPublicKey: clientKeys.public, clientProof: m1, sharedSecret: .init([UInt8](sharedSecret.bytes)))

        XCTAssertEqual(Data(m1).base64EncodedString(), "f/Bkq8gBTYxl7SyiRd4SXTyE/jM/g6E0mVyZIQDIsPg=")
        XCTAssertEqual(Data(m2).base64EncodedString(), "R2rgqC9cMAtWiXUImOrvs4oF+ccibf8KaFsZQ22WokM=")
    }
}
