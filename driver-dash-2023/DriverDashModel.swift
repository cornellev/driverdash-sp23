//
//  DriverDashModel.swift
//  driver-dash-2023
//
//  Created by Jason Klein on 3/25/23.
//

import SwiftUI
import CoreLocation
import SwiftSocket

// have two UserDefaults keys, one for front-daq and one for back-daq
// each one has the timestamp: { data } format I outlined for Drew
// note that the location comes with a timestamp!

// see this for clearing it https://developer.apple.com/documentation/foundation/userdefaults/1415919-dictionaryrepresentation

class DriverDashModel: NSObject, ObservableObject {
    @Published var speed = 0.0
    @Published var power = 0.0
    
//    private var server: HttpServer!
    private var locationManager: CLLocationManager!
    
    private var location: CLLocation?
    
    private var frontFile: FileHandle!
    private var backFile: FileHandle!
    
    override init() {
        super.init()
        
        // set up phone GPS tracking
        locationManager = CLLocationManager()
        // not sure what I want the accuracy level to be
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestWhenInUseAuthorization()
        locationManager.delegate = self
        
        locationManager.startUpdatingLocation()
        
        // set address to the IP address of *the phone*
        let server = TCPServer(address: "172.20.10.1", port: 8080)
        switch server.listen() {
          case .success:
            print("Server listening!")
            while true {
                if let client = server.accept() {
                    print("Newclient from: \(client.address):\(client.port)")
                    
                    while true {
                        // expect to first get four bytes with the length of the next packet
                        let read = client.read(4)!
                        let data = Data(bytes: read, count: 4)
                        let length = UInt32(littleEndian: data.withUnsafeBytes {
                            // see https://stackoverflow.com/a/32770113
                            (pointer: UnsafeRawBufferPointer) -> UInt32 in return pointer.load(as: UInt32.self)
                        })
                        
                        // all data sent to the server will be valid json
                        if let content = String(bytes: client.read(Int(length))!, encoding: .utf8) {
                            do {
                                let json = try JSONDecoder().decode(BackPacket.self, from: content.data(using: .utf8)!)
                                let encoder = JSONEncoder()
                                encoder.outputFormatting = .prettyPrinted
                                print(try encoder.encode(json))
                                
                            } catch let error {
                                print("Error reading JSON: \(error.localizedDescription)")
                            }
                            
                            print(content)
                        }
                    }
                    // var _ = client.send(string: "g")
                    // client.close()
                    
                } else {
                    print("accept error")
                }
            }
            
          case .failure(let error):
            print(error.localizedDescription)
        }
        
        /*
        // see https://github.com/httpswift/swifter
        self.server = HttpServer()
        
        // make it easy to check whether the server is alive
        server["/ping"] = { request in
            self.locationManager.requestLocation()
            print(self.location ?? "no location yet")
            return .ok(.text("pong"))
        }
        
        //handles back daq
        server["/back-daq"] = websocket(text: { session, text in
            // see https://stackoverflow.com/a/53569348 and also
            // https://www.avanderlee.com/swift/json-parsing-decoding/ for JSON decoding
            var json = try! JSONDecoder().decode(BackPacket.self, from: text.data(using: .utf8)!)
            
            // see https://stackoverflow.com/a/74318451
            DispatchQueue.main.async {
                self.power = json.bms ?? self.power
            }
            
            // save to file with timestamp. requires location
            if let location = self.location {
                // if no RTK, fill with phone location
                // todo don't do this. have another format for the saved stuff
                if json.rtk == nil {
                    json.rtk = BackPacket.RTK(
                        latitude: location.coordinate.latitude,
                        longitude: location.coordinate.longitude)
                }
                
                let timestamp = getTimestampString(from: location.timestamp)
                let encoded = try! JSONEncoder().encode(data)
                let stringified = String(data: encoded, encoding: .utf8)!
                try! self.backFile.write(contentsOf: "\(timestamp) \(stringified)\n".data(using: .utf8)!)
                // todo: save
                //saveToFile(timestamp: "\(timestamp).json", data: json)
            }
        })
        
        //handle front daq
        server["/front-daq"] = websocket(text: { session, text in
            // see https://stackoverflow.com/a/53569348 and also
            // https://www.avanderlee.com/swift/json-parsing-decoding/ for JSON decoding
            let json = try! JSONDecoder().decode(FrontPacket.self, from: text.data(using: .utf8)!)
            
            // todo: save to file with timestamp
        })
        
        func getTimestampString(from date: Date = Date()) -> String {
            let dateFormatter = DateFormatter()
            // can't use colons since it's a filename (for now)
            dateFormatter.dateFormat = "yyyy-MM-dd-HH.mm.ss.SSSSS"
            return dateFormatter.string(from: date)
        }
        
        do {
            try server.start(8080)
            try print("Running on port \(server.port())")
            
        // https://stackoverflow.com/a/30720807
        } catch let error {
            print(error.localizedDescription)
        }
         */
    }
}

extension DriverDashModel: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        //. keep the current location up to date as much as possible
        if let location = locations.last {
            self.location = location
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // todo: is there a better way to handle errors than this?
        print("Whoopsies. Had trouble getting the location.")
    }
}
