//
//  ViewController.swift
//  Computer: G. R. Akhtar
//
//  Created by Home on 5/21/19.
//  Updated by Hone on 9/9/19
//  Copyright © 2019 Home. All rights reserved.
//

import UIKit

extension FileManager {
    func urls(for directory: FileManager.SearchPathDirectory, skipsHiddenFiles: Bool = true ) -> [URL]? {
        let documentsURL = urls(for: directory, in: .userDomainMask)[0]
        let fileURLs = try? contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil, options: skipsHiddenFiles ? .skipsHiddenFiles : [] )
        return fileURLs
    }
}

class FirstViewController: UITableViewController, Storyboarded {
    weak var coordinator: MainCoordinator?
    var option = [String]()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Do any additional setup after loading the view.
        title = "Shalimar"
    }
    
    override func viewDidAppear(_ animated: Bool) {
        option.removeAll()
        
        option.append("Compute")
        let list:[URL] = FileManager.default.urls(for: .documentDirectory)!
        if  list.isEmpty { option.append("primes") }
        for index in list.indices {
            let name = list[index].lastPathComponent
            if(!option.contains(name)) {
                option.append(name)
            }
        }
        tableView.reloadData()
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return option.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath) as UITableViewCell
        
        let item: String = option[indexPath.row]
        cell.textLabel?.text = item
        
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didUnhighlightRowAt indexPath: IndexPath) {
        switch indexPath.row {
        case 0:
            coordinator?.calculate()
        default:
            coordinator?.fileURL = option[indexPath.row]
            coordinator?.compute()
        }
    }

    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        if indexPath.row==0 { return nil }
        let delete = deleteAction(at: indexPath)
        return UISwipeActionsConfiguration(actions: [delete])
    }

    func deleteAction(at indexPath:IndexPath) -> UIContextualAction {
        let action = UIContextualAction(style: .destructive, title: "Delete") {
            (action, view, completion) in
            
            if  self.deleteItem(urlName: self.option[indexPath.row]) {
                self.option.remove(at: indexPath.row)
                self.tableView.deleteRows(at: [indexPath], with: .automatic)
            }
            completion(true)
        }
        
        return action
    }

    func deleteItem(urlName: String) -> Bool {
        let list:[URL] = FileManager.default.urls(for: .documentDirectory)!
        for index in list.indices {
            let url: URL = list[index]
            let name = url.lastPathComponent
            if( name.contains(urlName)) {
                self.removeThisURL(url: url)
                return true
            }
        }
        return false
    }

    func removeThisURL(url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
        } catch  let error as NSError {
            showAlert(title: navigationItem.title!, message: error.localizedFailureReason!)
        }
    }

    func showAlert(title: String, message: String, style: UIAlertController.Style = .alert) {
        let alertController = UIAlertController(title: title, message: message, preferredStyle: style)
        let action = UIAlertAction(title: "OK", style: .default) { (action) in
            self.dismiss(animated: true, completion: nil)
        }
        alertController.addAction(action)
        self.present(alertController, animated: true, completion: nil)
    }
/*
    func askingAlert(title: String, message: String, style: UIAlertController.Style = .alert) -> Bool {
        var resp:Bool = false
        let alertController = UIAlertController(title: title, message: message, preferredStyle: style)
        let actionY = UIAlertAction(title: "Yes", style: .default) { (action) in
            self.dismiss(animated: true, completion: nil)
            resp = true
        }
        let actionN = UIAlertAction(title: "No", style: .default) { (action) in
            self.dismiss(animated: true, completion: nil)
        }
        alertController.addAction(actionY)
        alertController.addAction(actionN)
        
        self.present(alertController, animated: true, completion: nil)
        return resp
    } */
}
