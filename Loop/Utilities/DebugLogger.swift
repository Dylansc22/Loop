//
//  DebugLogger.swift
//  Loop
//
//  Shared file-based debug logger for development use.
//

import Foundation

enum DebugLogger {
    private static let fileHandle: FileHandle? = {
        let path = "/tmp/loop-debug.log"
        FileManager.default.createFile(atPath: path, contents: nil)
        return FileHandle(forWritingAtPath: path)
    }()

    static func log(_ msg: String) {
        guard let fh = fileHandle,
              let data = (msg + "\n").data(using: .utf8) else { return }
        fh.seekToEndOfFile()
        fh.write(data)
    }
}
