//
//  MainCoordinator.swift
//  Computer
//
//  Created by Home on 5/21/19.
//  Copyright © 2019 Home. All rights reserved.
//

import Foundation
import UIKit

class MainCoordinator: Coordinator {
    var childCoordinators = [Coordinator]()
    var navigationController: UINavigationController
    var fileURL: String

    init(navigationController: UINavigationController) {
        self.navigationController = navigationController
        fileURL = ""
    }
    
    func start() {
        let vc = FirstViewController.instantiate()
        vc.coordinator = self
        navigationController.pushViewController(vc, animated: true)
    }
    
    func calculate() {
        let vc = CalculateViewController.instantiate()
        vc.coordinator = self
        navigationController.pushViewController(vc, animated: true)
    }
    
    func compute() {
        let vc = ComputeViewController.instantiate()
        vc.coordinator = self
        navigationController.pushViewController(vc, animated: true)
    }
}
