//
//  CalculateViewController.swift
//  Computer
//
//  Created by Home on 5/21/19.
//  Copyright © 2019 Home. All rights reserved.
//

import UIKit

class CalculateViewController: UIViewController, Storyboarded, UITextFieldDelegate {
    weak var coordinator: MainCoordinator?
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        lat1d.delegate = self
        lat1m.delegate = self
        lat1s.delegate = self
        lng1d.delegate = self
        lng1m.delegate = self
        lng1s.delegate = self
        lat2d.delegate = self
        lat2m.delegate = self
        lat2s.delegate = self
        lng2d.delegate = self
        lng2m.delegate = self
        lng2s.delegate = self
        
        let myKeyboard = UIKeyboardType.numberPad
        let myKeyboard1 = UIKeyboardType.decimalPad
        lat1d.keyboardType = myKeyboard
        lat2d.keyboardType = myKeyboard
        lat1m.keyboardType = myKeyboard
        lat2m.keyboardType = myKeyboard
        lat1d.keyboardType = myKeyboard
        lat1s.keyboardType = myKeyboard1
        lat2s.keyboardType = myKeyboard1
        
        lng1d.keyboardType = myKeyboard
        lng2d.keyboardType = myKeyboard
        lng1m.keyboardType = myKeyboard
        lng2m.keyboardType = myKeyboard
        lng1d.keyboardType = myKeyboard
        lng1s.keyboardType = myKeyboard1
        lng2s.keyboardType = myKeyboard1
        
        lat1d.text = "33"; lat1m.text = "0"; lat1s.text = "0.0"
        lng1d.text = "73"; lng1m.text = "0"; lng1s.text = "0.0"
        lat2d.text = "34"; lat2m.text = "0"; lat2s.text = "0.0"
        lng2d.text = "74"; lng2m.text = "0"; lng2s.text = "0.0"
    }
    
    @IBOutlet var lat1d: UITextField!
    @IBOutlet var lat1m: UITextField!
    @IBOutlet var lat1s: UITextField!
    @IBOutlet var lng1d: UITextField!
    @IBOutlet var lng1m: UITextField!
    @IBOutlet var lng1s: UITextField!
    
    @IBOutlet var lat2d: UITextField!
    @IBOutlet var lat2m: UITextField!
    @IBOutlet var lat2s: UITextField!
    @IBOutlet var lng2d: UITextField!
    @IBOutlet var lng2m: UITextField!
    @IBOutlet var lng2s: UITextField!
    
    @IBOutlet var distance: UITextField!
    @IBOutlet var bearing: UITextField!
    @IBOutlet var bearing_dms: UITextField!
    
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        let allowedChars = "-0123456789."
        let allowedCharSet = CharacterSet(charactersIn: allowedChars)
        let typedCharSet = CharacterSet(charactersIn: string)
        
        return allowedCharSet.isSuperset(of: typedCharSet)
    }
    
    @IBAction func CalculateTapped(_ sender: Any) {
        let d2r = 1.745329251994330e-02
        let Req = 6378137.0 // metres
        let msg = "Invalid value found!"
        let rngmsg = "Value is out of range!"
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        guard let lat1D = Double(lat1d.text!) else { showAlert(title: "Lat1-deg", message: msg); return }
        guard let lat1M = Double(lat1m.text!) else { showAlert(title: "Lat1-min", message: msg); return }
        guard let lat1S = Double(lat1s.text!) else { showAlert(title: "Lat1-sec", message: msg); return }
        if lat1D < -90 || lat1D > 90 || lat1M < 0 || lat1M > 59 || lat1S < 0 || lat1S >= 60.0 {
            showAlert(title: "First point Lat", message: rngmsg); return
        }
        let lat1  = lat1D + (lat1M + lat1S / 60.0) / 60.0
        
        guard let lat2D = Double(lat2d.text!) else { showAlert(title: "Lat2-deg", message: msg); return }
        guard let lat2M = Double(lat2m.text!) else { showAlert(title: "Lat2-min", message: msg); return }
        guard let lat2S = Double(lat2s.text!) else { showAlert(title: "Lat2-sec", message: msg); return }
        if lat2D < -90 || lat2D > 90 || lat2M < 0 || lat2M > 59 || lat2S < 0 || lat2S >= 60.0 {
            showAlert(title: "Second point Lat", message: rngmsg); return
        }
        let lat2  = lat2D + (lat2M + lat2S / 60.0) / 60.0

        guard let lng1D = Double(lng1d.text!) else { showAlert(title: "Long1-deg", message: msg); return }
        guard let lng1M = Double(lng1m.text!) else { showAlert(title: "Long1-min", message: msg); return }
        guard let lng1S = Double(lng1s.text!) else { showAlert(title: "Long1-sec", message: msg); return }
        if lng1D <= -180 || lng1D > 180 || lng1M < 0 || lng1M > 59 || lng1S < 0 || lng1S >= 60.0 {
            showAlert(title: "First point Long", message: rngmsg); return
        }
        let lng1  = lng1D + (lng1M + lng1S / 60.0) / 60.0
        
        guard let lng2D = Double(lng2d.text!) else { showAlert(title: "Long2-deg", message: msg); return }
        guard let lng2M = Double(lng2m.text!) else { showAlert(title: "Long2-min", message: msg); return }
        guard let lng2S = Double(lng2s.text!) else { showAlert(title: "Long2-sec", message: msg); return }
        if lng2D <= -180 || lng2D > 180 || lng2M < 0 || lng2M > 59 || lng2S < 0 || lng2S >= 60.0 {
            showAlert(title: "Second point Long", message: rngmsg); return
        }
        let lng2  = lng2D + (lng2M + lng2S / 60.0) / 60.0
        
        let φ1 = lat1*d2r
        let φ2 = lat2*d2r
        let Δφ = φ1 - φ2
        let λ1 = lng1*d2r
        let λ2 = lng2*d2r
        let Δλ = λ2 - λ1
        let sφ = sin(Δφ/2)
        let sλ = sin(Δλ/2)
            
        let cφ1 = cos(φ1)
        let cφ2 = cos(φ2)
        let a = sφ * sφ + cφ1 * cφ2 * sλ * sλ
        let c = 2 * atan2(sqrt(a), sqrt(1-a))
        let d = Req * c / 1000
        distance.text = String(format: "%.03f", d)

        let sφ1 = sin(φ1)
        let sφ2 = sin(φ2)
        let y =                   cφ2 * sin(Δλ)
        let x = cφ1 * sφ2 - sφ1 * cφ2 * cos(Δλ)
        let b = atan2(y, x) / d2r
        bearing.text = String(format: "%.03f", b)
        
        let (D,M,S) = Degrees2DMS(degree: b)
        bearing_dms.text = String(format: "%2d\u{00B0} %2d' %2d\"", D, M, S)
    }
    
    /*
    // MARK: - Navigation
    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
    */

    func showAlert(title: String, message: String, style: UIAlertController.Style = .alert) {
        let alertController = UIAlertController(title: title, message: message, preferredStyle: style)
        let action = UIAlertAction(title: "OK", style: .default) { (action) in
            self.dismiss(animated: true, completion: nil)
        }
        alertController.addAction(action)
        self.present(alertController, animated: true, completion: nil)
    }
    
    func Degrees2DMS(degree: Double)->(Int,Int,Int) {
        var Seconds = (Int)(degree * 3600)
        let Degrees = Seconds / 3600
        Seconds = abs(Seconds % 3600)
        let Minutes = Seconds / 60;
        Seconds %= 60;
        
        return (Degrees, Minutes, Seconds)
    }
}
