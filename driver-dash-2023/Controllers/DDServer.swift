//
//  DDServer.swift
//  driver-dash-2023
//
//  Created by Jason Klein on 3/27/23.
//

import Foundation
import SwiftSocket

class DDServer: NSObject {
    let address: String
    let port: Int32
    
    let model: DDModel
    let packetType: Coder.Packet
    
    init(address: String, port: Int, for packetType: Coder.Packet, with model: DDModel) {
        self.address = address
        self.port = Int32(port)
        self.packetType = packetType
        self.model = model
        
        super.init()
        
        let serverThread = ServerThread(controller: self)
        serverThread.start()
    }
    
    private class ServerThread: Thread {
        let controller: DDServer!
        let serializer: Serializer!
        
        // string form
        let packetType: Coder.Packet
        
        init(controller: DDServer) {
            self.packetType = controller.packetType
            self.serializer = Serializer(for: self.packetType)
            // reference needed so we can update state
            self.controller = controller
            
            super.init()
        }
        
        override func main() {
            let server = TCPServer(
                address: self.controller.address,
                port: self.controller.port)
            
            defer {
                print("Closing down the \(self.packetType) server.")
                server.close()
            }
            
            switch server.listen() {
              case .success:
                let side = self.packetType.rawValue.capitalized
                print("\(side) server listening at \(self.controller.address):\(self.controller.port)!")
                
                while true {
                    // accept() stalls until something connects
                    if let client = server.accept() {
                        // we connected!
                        print("\(self.packetType.rawValue.capitalized) has a new connection!")
                        updateStatus(connected: true)
                        
                        handle(client)
                        
                        // if we're here then we disconnected
                        print("A client disconnected from the \(self.packetType.rawValue) server")
                        updateStatus(connected: false)
                    } else {
                        print("accept error")
                    }
                }
                
              case .failure(let error):
                print(error.localizedDescription)
                print("You probably have the wrong phone IP address")
            }
        }
        
        private func updateStatus(connected: Bool) {
            let model = self.controller.model
            
            DispatchQueue.main.async {
                switch (self.packetType) {
                    case .back:
                        model.backSocketConnected = connected
                    case .lord:
                        model.lordSocketConnected = connected
                    case .phone: ()
                }
            }
        }
        
        private func handle(_ client: TCPClient) {
            print("New client from: \(client.address):\(client.port)")
            
            // receive length of packet in 4 bytes
            // read() waits until we have all 4 bytes
            while let length_b = client.read(4) {
                let data = Data(bytes: length_b, count: 4)
                let length = UInt32(littleEndian: data.withUnsafeBytes {
                    // see https://stackoverflow.com/a/32770113
                    pointer in return pointer.load(as: UInt32.self)
                })
                
                // wait until we have the next length packets
                if let content_b = client.read(Int(length)) {
                    switch self.controller.packetType {
                        case .back:
                            let json = Coder().decode(
                                from: Data(content_b),
                                ofType: Coder.BackPacket.self)
                            // preview parsed data
                            print(Coder().encode(from: json))
                            
                            // since changing the model updates the UI, we have to make updates on the main thread.
                            // this will update as soon as the main thread is able.
                            DispatchQueue.main.async {
                                if let power = json.voltage {
                                    self.controller.model.power = power
                                }
                                
                                if let rpm = json.rpm {
                                    let diameter = 0.605 // meters
                                    let speed = Double(rpm) * diameter * Double.pi * 60 / 1000 // km/h
                                    self.controller.model.speed = speed
                                }
                            }
                            
                            // defer file-writing to be async
                            DispatchQueue.global().async {
                                self.serializer.serialize(data: json)
                            }
                        
                        case .lord:
                            let json = Coder().decode(
                                from: Data(content_b),
                                ofType: Coder.LordPacket.self)
                            // preview parsed data
                            print(Coder().encode(from: json))
                        
                            // save to file
                            DispatchQueue.global().async {
                                self.serializer.serialize(data: json)
                            }
                        
                    // should never happen
                    case .phone: ()
                    }
                }
            }
        }
    }
}
