//////////////////////////////////////////////////////////////////////////////////
//
// B L I N K
//
// Copyright (C) 2016-2019 Blink Mobile Shell Project
//
// This file is part of Blink.
//
// Blink is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Blink is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with Blink. If not, see <http://www.gnu.org/licenses/>.
//
// In addition, Blink is also subject to certain additional terms under
// GNU GPL version 3 section 7.
//
// You should have received a copy of these additional terms immediately
// following the terms and conditions of the GNU General Public License
// which accompanied the Blink Source Code. If not, see
// <http://www.github.com/blinksh/blink>.
//
////////////////////////////////////////////////////////////////////////////////


import Foundation


@objc class Migrator : NSObject {
  @objc static func perform() {
    // HermesLink has a new bundle identifier and therefore no legacy Blink
    // data to migrate. More importantly, TrollStore/ad-hoc installs do not
    // have the provisioned containers expected by these old migrations.
    // Running them during launch can throw Objective-C exceptions before the
    // first scene is created, so HermesLink must start without legacy work.
    guard Bundle.main.bundleIdentifier != "com.hermeslink.app" else {
      return
    }

    Self.perform(steps: [MigrationToAppGroup(),
                         MigrationAddSnippetsShortcut(),
                         MigrationStyleFromDefaults(),
                         MigrationWipeSessionRegistry()
                        ])
  }

  static func perform(steps: [MigrationStep]) {
    let migratorFileURL = URL(fileURLWithPath: BlinkPaths.groupContainerPath()).appendingPathComponent(".migrator")

    let currentVersionString = try? String(contentsOf: migratorFileURL, encoding: .utf8)
    var currentVersion = Int(currentVersionString ?? "0") ?? 0

    steps.forEach { step in
      guard step.version > currentVersion else {
        return
      }

      do {
        try step.execute()
        currentVersion = step.version
        try String(currentVersion)
          .data(using: .utf8)!
          .write(to: migratorFileURL,
                 options:  [.atomic, .noFileProtection])
      } catch {
        print(error)
        exit(0)
      }
    }
  }
}

protocol MigrationStep {
  // Migration steps should be idempotent
  func execute() throws
  // After a step is applied, the version is updated
  var version: Int { get }
}
