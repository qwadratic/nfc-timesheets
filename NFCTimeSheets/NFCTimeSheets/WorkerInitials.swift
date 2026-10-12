//
//  WorkerInitials.swift
//  NFCTimeSheets
//
//  The two letters in the identity card's circle (Android WorkerHomeCards.kt `WorkerIdentity`):
//  the first character of each of the first two whitespace-separated parts of the name, in the
//  case the name was written in. "Anna Rig" -> "AR", "Hans Peter Müller" -> "HP", "Cher" -> "C",
//  an empty name -> "". Foundation-only so checks/version-tap-gate-check.swift runs it on a Mac.
//

import Foundation

enum WorkerInitials {
    static func of(_ name: String) -> String {
        name.split(whereSeparator: { $0.isWhitespace })
            .prefix(2)
            .compactMap { $0.first }
            .map(String.init)
            .joined()
    }
}
