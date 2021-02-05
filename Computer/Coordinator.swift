//
//  Coordinator.swift
//  Computer
//
//  Created by Home on 5/21/19.
//  Copyright © 2019 Home. All rights reserved.
//

import Foundation
import UIKit

protocol Coordinator {
    var childCoordinators: [Coordinator] { get set }
    var navigationController: UINavigationController { get set }
    func start()
}
