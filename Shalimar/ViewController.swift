//
//  ViewController.swift
//  Shalimar: G. R. Akhtar
//
//  Created by Home on 5/21/19.
//  Updated by Hone on 9/9/19
//  Copyright © 2019-2026 G. R. Akhtar. All rights reserved.
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

        title = "Shalimar"
        // The app's own name, given the weight of one: 30pt heavy against the 17pt
        // semibold every other screen's title uses. Only this screen - the appearance is
        // set on the navigation item rather than on the bar, so "Shalimar Reference" and
        // the editor's own bar are untouched.
        //
        // Green rather than the yellow the bar sets, and as deep a green as the purple
        // behind it allows: a true dark green measures 1.3:1 there, which is a title you
        // cannot read, where this holds 3.5:1 and still reads as green rather than mint.
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor.purple
        appearance.titleTextAttributes = [
            .foregroundColor: UIColor(displayP3Red: 0.0, green: 0.70, blue: 0.25, alpha: 1),
            .font: UIFont.systemFont(ofSize: 30, weight: .heavy)
        ]
        navigationItem.standardAppearance = appearance
        navigationItem.scrollEdgeAppearance = appearance
        navigationItem.compactAppearance = appearance

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add, target: self, action: #selector(newProgramTapped))
    }

    @objc func newProgramTapped() {
        coordinator?.fileURL = ""
        coordinator?.compute()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        option.removeAll()

        let list:[URL] = FileManager.default.urls(for: .documentDirectory)!
        for index in list.indices {
            let name = list[index].lastPathComponent
            if(!option.contains(name)) {
                option.append(name)
            }
        }
        tableView.backgroundView = option.isEmpty ? emptyStateView() : nil
        tableView.reloadData()
    }

    // Every row is a program the user saved, so before they have saved one there is
    // nothing here at all - and a blank white screen under a title reads as a screen that
    // failed to load rather than one that is waiting. The label says where the programs
    // will come from and points at the one control on the screen that makes one.
    private func emptyStateView() -> UIView {
        let label = UILabel()
        label.text = "No programs yet.\n\nTap + to write one."
        label.numberOfLines = 0
        label.textAlignment = .center
        label.textColor = UIColor.secondaryLabel
        label.font = UIFont.systemFont(ofSize: 17)
        return label
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
        coordinator?.fileURL = option[indexPath.row]
        coordinator?.compute()
    }

    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let delete = deleteAction(at: indexPath)
        return UISwipeActionsConfiguration(actions: [delete])
    }

    func deleteAction(at indexPath:IndexPath) -> UIContextualAction {
        let action = UIContextualAction(style: .destructive, title: "Delete") {
            (action, view, completion) in
            
            if  self.deleteItem(urlName: self.option[indexPath.row]) {
                self.option.remove(at: indexPath.row)
                self.tableView.deleteRows(at: [indexPath], with: .automatic)
                // Deleting the last program empties the list without leaving the screen,
                // so the empty state has to be put up here too and not only on appearing.
                self.tableView.backgroundView = self.option.isEmpty ? self.emptyStateView() : nil
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
