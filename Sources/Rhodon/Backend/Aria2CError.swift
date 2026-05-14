import Foundation

struct Aria2UnavailableError: LocalizedError {
    static let aria2HomepageURL = URL(string: "https://aria2.github.io")!
    static let homebrewFormulaURL = URL(string: "https://formulae.brew.sh/formula/aria2")!

    static let installationInstructions = """
    aria2 is not available on this Mac. Install aria2 to use the aria2 downloader option.

    More information: https://aria2.github.io
    Homebrew formula: https://formulae.brew.sh/formula/aria2

    The recommended installation command is:
    brew install aria2
    """

    var errorDescription: String? {
        Self.installationInstructions
    }
}

/// A LocalizedError that represents a non-zero exit code from running aria2c.
struct Aria2CError: LocalizedError {
    var code: Code

    init?(exitStatus: Int32) {
        guard let code = Code(rawValue: exitStatus) else { return nil }
        self.code = code
    }

    var errorDescription: String? {
        "aria2c error: \(code.description)"
    }

    /// https://github.com/aria2/aria2/blob/master/src/error_code.h
    enum Code: Int32, CustomStringConvertible {
        case undefined = -1
        // Ignoring, not an error
        // case finished = 0
        case unknownError = 1
        case timeOut
        case resourceNotFound
        case maxFileNotFound
        case tooSlowDownloadSpeed
        case networkProblem
        case inProgress
        case cannotResume
        case notEnoughDiskSpace
        case pieceLengthChanged
        case duplicateDownload
        case duplicateInfoHash
        case fileAlreadyExists
        case fileRenamingFailed
        case fileOpenError
        case fileCreateError
        case fileIoError
        case dirCreateError
        case nameResolveError
        case metalinkParseError
        case ftpProtocolError
        case httpProtocolError
        case httpTooManyRedirects
        case httpAuthFailed
        case bencodeParseError
        case bittorrentParseError
        case magnetParseError
        case optionError
        case httpServiceUnavailable
        case jsonParseError
        case removed
        case checksumError

        var description: String {
            switch self {
            case .undefined:
                "Undefined"
            case .unknownError:
                "Unknown error"
            case .timeOut:
                "Timed out"
            case .resourceNotFound:
                "Resource not found"
            case .maxFileNotFound:
                "Maximum number of file not found errors reached"
            case .tooSlowDownloadSpeed:
                "Download speed too slow"
            case .networkProblem:
                "Network problem"
            case .inProgress:
                "Unfinished downloads in progress"
            case .cannotResume:
                "Remote server did not support resume when resume was required to complete download"
            case .notEnoughDiskSpace:
                "Not enough disk space available"
            case .pieceLengthChanged:
                "Piece length was different from one in .aria2 control file"
            case .duplicateDownload:
                "Duplicate download"
            case .duplicateInfoHash:
                "Duplicate info hash torrent"
            case .fileAlreadyExists:
                "File already exists"
            case .fileRenamingFailed:
                "Renaming file failed"
            case .fileOpenError:
                "Could not open existing file"
            case .fileCreateError:
                "Could not create new file or truncate existing file"
            case .fileIoError:
                "File I/O error"
            case .dirCreateError:
                "Could not create directory"
            case .nameResolveError:
                "Name resolution failed"
            case .metalinkParseError:
                "Could not parse Metalink document"
            case .ftpProtocolError:
                "FTP command failed"
            case .httpProtocolError:
                "HTTP response header was bad or unexpected"
            case .httpTooManyRedirects:
                "Too many redirects occurred"
            case .httpAuthFailed:
                "HTTP authorization failed"
            case .bencodeParseError:
                "Could not parse bencoded file (usually \".torrent\" file)"
            case .bittorrentParseError:
                "\".torrent\" file was corrupted or missing information"
            case .magnetParseError:
                "Magnet URI was bad"
            case .optionError:
                "Bad/unrecognized option was given or unexpected option argument was given"
            case .httpServiceUnavailable:
                "HTTP service unavailable"
            case .jsonParseError:
                "Could not parse JSON-RPC request"
            case .removed:
                "Reserved. Not used."
            case .checksumError:
                "Checksum validation failed"
            }
        }
    }
}
