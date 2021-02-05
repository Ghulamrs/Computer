//
//  ComputeViewController.swift
//  Computer: G. R. Akhtar
//
//  Created by Home on 5/21/19.
//  Copyright © 2019 Home. All rights reserved.
//

import UIKit
import Messages
import MessageUI

class ComputeViewController: UIViewController, Storyboarded, UITextViewDelegate {
    weak var coordinator: MainCoordinator?
    @IBOutlet var lineview: UITextView!
    @IBOutlet var program: UITextView!
    @IBOutlet var console: UITextView!
    var count: Int = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        lineview.delegate = self
        lineview.textColor = UIColor.init(displayP3Red: 0.75, green: 0.75, blue: 0.75, alpha: 1)
        lineview.font = program.font
        lineview.isScrollEnabled = true
        lineview.translatesAutoresizingMaskIntoConstraints = false
        [
            lineview.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            lineview.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            lineview.trailingAnchor.constraint(lessThanOrEqualToSystemSpacingAfter: view.trailingAnchor, multiplier: 0),
            lineview.heightAnchor.constraint(equalToConstant: 244)
        ].forEach{ $0.isActive = true }
        lineview.text = ""
        for i in 1..<100 {
            lineview.text += String(i) + "\n"
        }
        
        program.delegate = self
        program.backgroundColor = UIColor.init(displayP3Red: 0.8, green: 1, blue: 0.95, alpha: 1)
        console.backgroundColor = UIColor.init(white: 0.8, alpha: 0.5)
        program.textColor = UIColor.init(displayP3Red: 0.8, green: 0.5, blue: 0.95, alpha: 1)
        program.translatesAutoresizingMaskIntoConstraints = false
        [
            program.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            program.leadingAnchor.constraint(equalTo: lineview.trailingAnchor),
            program.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            program.heightAnchor.constraint(equalToConstant: 244)
        ].forEach{ $0.isActive = true }
        
        console.textColor = UIColor.red
        console.isScrollEnabled = true
        console.isEditable = false
        load(fileName: coordinator!.fileURL)
        
        let tap2 = UITapGestureRecognizer(target: self, action: #selector(doubleTapped))
        tap2.numberOfTapsRequired = 2
        console.addGestureRecognizer(tap2)
        
        let tap1 = UITapGestureRecognizer(target: self, action: #selector(textTapped(_:)))
        tap1.numberOfTapsRequired = 1
        console.addGestureRecognizer(tap1)
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        if !program.text.isEmpty { self.count = 0 }
    }
    
    @objc func doubleTapped() {
        if program.text.isEmpty {
            let x = console.text.components(separatedBy: ["\n"])
            program.text += x[5] + "\n"
            program.text += x[6] + "\n"
            program.text += x[7] + "\n  "
            program.text += x[18] + "\n"
            program.text += x[8] + "\n"
        }
    }
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        lineview.contentOffset = program.contentOffset
    }
    
    @objc func updateTextView(notification: Notification) {
        let userInfo = notification.userInfo!
        let keyboardEndFrameScreenCoordinate = (userInfo[UIResponder.keyboardFrameEndUserInfoKey] as! NSValue).cgRectValue
        let keyboardEndFrame = self.view.convert(keyboardEndFrameScreenCoordinate, to: view.window)
        if notification.name == UIResponder.keyboardWillHideNotification {
            program.contentInset = UIEdgeInsets.zero
        } else {
            program.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: keyboardEndFrame.height, right: 0)
            program.scrollIndicatorInsets = program.contentInset
        }
    }
    
    @IBAction func ComputeTapped(_ sender: Any) {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        
        var eline = ""
        let line = program.text.components(separatedBy: ["\n"])
        let x = Express(source: program.text)
        let v = Bundle.main.infoDictionary?["CFBundleVersion"] as! String
        if program.text.isEmpty {
            console.text = "Shalimar, \(v)"
            console.text += templateText // defined in template.swift
            return
        }

        do {
            console.text = try x.run(times: ++count, fileURL: coordinator!.fileURL)
            if !x.main.isEmpty { save(fileName: x.main) }
        } catch let error as ParseError {
            if error.line < line.count { eline = String(line[error.line]) }
            let a = UIAlertController(title: "Runtime Error", message: "\(error.kind)\nline \(error.line+1): \(eline)", preferredStyle: .alert)
            a.addAction(UIAlertAction(title: "Ok", style: .default, handler: nil))
            present(a, animated: true, completion: nil)
        } catch let error {
            let a = UIAlertController(title: "Runtime Error", message: "\(error)", preferredStyle: .alert)
            a.addAction(UIAlertAction(title: "Ok", style: .default, handler: nil))
            present(a, animated: true, completion: nil)
        }
    }

    @objc private func textTapped(_ tapGesture: UITapGestureRecognizer) {
        let textView = tapGesture.view as? UITextView
        let point = tapGesture.location(in: textView!)
        if let detectedWord = getWordAtPosition(tapGesture, point) {
            if self.count == 0 { program.text += detectedWord + "\n" }
        }
    }

    private func getWordAtPosition(_ tapGesture: UITapGestureRecognizer, _ point: CGPoint) -> String? {
        let textView = tapGesture.view as? UITextView
        if let textPosition = textView!.closestPosition(to: point) {
            if let range = textView!.tokenizer.rangeEnclosingPosition(
                textPosition, with: .line, inDirection: UITextDirection(rawValue: 1)) {
                return textView!.text(in: range)
            }
        }

        return nil
    }

    func save(fileName: String) {
        let DocDirURL = try! FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let fileURL = DocDirURL.appendingPathComponent(fileName).appendingPathExtension("shm")
        do {
            try program.text.write(to: fileURL, atomically: true, encoding: String.Encoding.utf8)
        } catch let error as NSError {
            print(error)
        }
    }

    func load(fileName: String) {
        let DocDirURL = try! FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let fileURL = DocDirURL.appendingPathComponent(fileName) //.appendingPathExtension("sha")
        var readString = ""
        do {
            readString = try String(contentsOf: fileURL)
            program.text = readString
        } catch let error as NSError {
            print(error)
        }
    }
}
