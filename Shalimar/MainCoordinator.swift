//
//  MainCoordinator.swift
//  Shalimar
//
//  Created by Home on 5/21/19.
//  Copyright © 2019-2026 G. R. Akhtar. All rights reserved.
//

import Foundation
import UIKit

/// The example programs shipped inside the app.
///
/// They are read-only by construction rather than by a flag anyone has to remember to
/// check: the bundle is not writable on a device at all. That is the whole point of
/// keeping them here instead of seeding them into Documents on first launch - a
/// baseline that can be edited or deleted stops being a baseline, quietly, and the
/// user finds out only when they go looking for the syntax it was meant to preserve.
///
/// Read from the directory rather than from a list in code, so a new `.shm` added to
/// `Examples/` appears here without a second edit - the same rule the regression suite
/// follows.
enum BundledExamples {
    static var directory: URL? {
        Bundle.main.url(forResource: "Examples", withExtension: nil)
    }

    static func names() -> [String] {
        guard let directory = directory,
              let files = try? FileManager.default.contentsOfDirectory(
                  at: directory, includingPropertiesForKeys: nil) else { return [] }
        return files.filter { $0.pathExtension == "shm" }
                    .map { $0.lastPathComponent }
                    .sorted()
    }

    static func url(for name: String) -> URL? {
        directory?.appendingPathComponent(name)
    }
}

class MainCoordinator: Coordinator {
    var childCoordinators = [Coordinator]()
    var navigationController: UINavigationController
    var fileURL: String

    // Whether fileURL names a program in the bundle rather than one of the user's own.
    // The editor reads from a different place for each, and saving an example writes a
    // copy into Documents instead of writing back.
    var fileIsExample = false

    init(navigationController: UINavigationController) {
        self.navigationController = navigationController
        fileURL = ""
    }
    
    func start() {
        let vc = FirstViewController.instantiate()
        vc.coordinator = self
        navigationController.pushViewController(vc, animated: true)
    }
    
    func compute() {
        let vc = ComputeViewController.instantiate()
        vc.coordinator = self
        navigationController.pushViewController(vc, animated: true)
    }
}
