//
//  ViewController.swift
//  fingerSampleApp
//
//  Created by  Hisanori Ando on 2020/09/13.
//  Copyright © 2020  Hisanori Ando. All rights reserved.
//
import UIKit
import CoreBluetooth
import CoreML
import Vision

//データ型にHexString変換メソッドを拡張する
extension Data {
  /// A hexadecimal string representation of the bytes.
  func hexEncodedString() -> String {
    let hexDigits = Array("0123456789abcdef".utf16)
    var hexChars = [UTF16.CodeUnit]()
    hexChars.reserveCapacity(count * 2)

    for byte in self {
      let (index1, index2) = Int(byte).quotientAndRemainder(dividingBy: 16)
      hexChars.append(hexDigits[index1])
      hexChars.append(hexDigits[index2])
    }
    return String(utf16CodeUnits: hexChars, count: hexChars.count)
  }
}

fileprivate func convertHex(_ s: String.UnicodeScalarView, i: String.UnicodeScalarIndex, appendTo d: [UInt8]) -> [UInt8] {

    let skipChars = CharacterSet.whitespacesAndNewlines

    guard i != s.endIndex else { return d }

    let next1 = s.index(after: i)

    if skipChars.contains(s[i]) {
        return convertHex(s, i: next1, appendTo: d)
    } else {
        guard next1 != s.endIndex else { return d }
        let next2 = s.index(after: next1)

        let sub = String(s[i..<next2])

        guard let v = UInt8(sub, radix: 16) else { return d }

        return convertHex(s, i: next2, appendTo: d + [ v ])
    }
}

extension String {

    /// Convert Hexadecimal String to Array<UInt>
    ///     "0123".hex                // [1, 35]
    ///     "aabbccdd 00112233".hex   // 170, 187, 204, 221, 0, 17, 34, 51]
    var hex : [UInt8] {
        return convertHex(self.unicodeScalars, i: self.unicodeScalars.startIndex, appendTo: [])
    }

    /// Convert Hexadecimal String to Data
    ///     "0123".hexData                    /// 0123
    ///     "aa bb cc dd 00 11 22 33".hexData /// aabbccdd 00112233
    var hexData : Data {
        return Data(convertHex(self.unicodeScalars, i: self.unicodeScalars.startIndex, appendTo: []))
    }
}


class ViewController: UIViewController, CBCentralManagerDelegate, CBPeripheralDelegate {

    @IBOutlet weak var lblBLEStat: UILabel!
    @IBOutlet weak var lblClassfierDate: UILabel!
    
    @IBOutlet weak var lblClassfierResult: UILabel!
    
    var centralManager: CBCentralManager!
    var targetDevice: CBPeripheral!
    
    static let BLE_UUID_PREFIX: String = "F000"
    static let BLE_UUID_SUFFIX: String = "-0451-4000-B000-000000000000"
        
    //指紋認証サービス
    var STRING_SERVICE_FINGERPRINT: String = BLE_UUID_PREFIX + "1130" + BLE_UUID_SUFFIX
    var UUID_SERVICE_FINGERPRINT: CBUUID!
    
    //指紋認証情報キャラクタリスティック
    var STRING_CHARACTERISTIC_FINGERPRINT_DATA1: String = BLE_UUID_PREFIX + "1131" + BLE_UUID_SUFFIX
    var STRING_CHARACTERISTIC_FINGERPRINT_DATA2: String = BLE_UUID_PREFIX + "1132" + BLE_UUID_SUFFIX
    var STRING_CHARACTERISTIC_FINGERPRINT_DATA3: String = BLE_UUID_PREFIX + "1133" + BLE_UUID_SUFFIX
    var STRING_CHARACTERISTIC_FINGERPRINT_EVTDETECT: String = BLE_UUID_PREFIX + "1134" + BLE_UUID_SUFFIX
    
    //ドアロック開錠サービス
    var STRING_SERVICE_DOORLOCK: String = BLE_UUID_PREFIX + "1140" + BLE_UUID_SUFFIX
    var UUID_SERVICE_DOORLOCK: CBUUID!
    //ロック状態キャラクタリスティック
    var STRING_CHARACTERISTIC_FDORRLOCK_STATE: String = BLE_UUID_PREFIX + "1141" + BLE_UUID_SUFFIX
    
    var bWriteRequesting : Bool = false
    
    
    @IBAction func btnScan(_ sender: Any) {
        var nStat = 90
        lblBLEStat.text = "Scanning...."
        DispatchQueue.global().async {
            nStat = self.startScan(timeOut:5000)
            print("End of Scan (code:\(nStat))")
            DispatchQueue.main.async {
                if(nStat == 0){
                    self.lblBLEStat.text = "Found!!"
                } else {
                    self.lblBLEStat.text = "(No Connector)"
                }
            }
        }
    }
    
    @IBAction func btnConnect(_ sender: Any) {
        if(bFoundDevice == true){
            connectBle()
        }
    }
    @IBAction func btnDisConnect(_ sender: Any) {
        disconnectBle()
    }
    
    @IBAction func btnLockForceOpen(_ sender: Any) {
        let value: [UInt8] = [0x01]
        targetDevice.writeValue(Data(value), for: DOORLOCK_CHARA_STATE!, type: CBCharacteristicWriteType.withResponse)
    }
    
    @IBAction func btnLockForceClose(_ sender: Any) {
        let value: [UInt8] = [0x02]
        targetDevice.writeValue(Data(value), for: DOORLOCK_CHARA_STATE!, type: CBCharacteristicWriteType.withResponse)
    }
    
    
    private var bScaning:Bool = false
    private var bFoundDevice:Bool = false
    private var isConnected : Bool = false

    //すきゃん開始
    public func startScan(timeOut:Int)->Int{
        var nStat :Int = 99
        print("begin to scan ...")
        //isConnected = false
        targetDevice = nil
        //他のスキャンもキャンセルさせる
        bScaning = false
        //スキャン停止
        centralManager?.stopScan()
        //スキャン開始
        centralManager.scanForPeripherals(withServices: nil)
        var cntTimeOut = 0
        //スキャン中
        bScaning =  true
        while true {
            cntTimeOut = cntTimeOut + 100
            //一定時間待つ
            Thread.sleep(forTimeInterval: 0.1)
            if(cntTimeOut > timeOut){
                nStat = 90
                break
            } else if(bScaning == false){
                nStat = 10//スキャンキャンセル
                break
            } else if(self.bFoundDevice == true){
                    nStat = 0
                    break
            }
            //スキャン停止
            centralManager?.stopScan()
        }
        bScaning = false
        return nStat
    }
    
    public func connectBle(){
            centralManager.stopScan()
            if(targetDevice != nil){
                print("Try Connect")
                if(isConnected == false){
                    //targetDevice
                    centralManager.connect(targetDevice, options: nil)
                }
            }
        }
    
    public func disconnectBle(){
        if(targetDevice != nil){
            centralManager.cancelPeripheralConnection(targetDevice)
        }
    }

    
    
    // BT2コネクタ探索結果を受信ハンドラ(scanStartでのコールバック)
    public func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        print("pheripheral.name: \(String(describing: peripheral.name))")
        print("advertisementData:\(advertisementData)")
        print("RSSI: \(RSSI)")
        print("peripheral.identifier.uuidString: \(peripheral.identifier.uuidString)\n")
        var name : String ;
        name = String(describing: peripheral.name)
        if name.contains("Project Zero R2") { // -> true
            print("Found!!")
            targetDevice = peripheral
            bFoundDevice = true
        }
    }
    
    
    //BT2接続失敗時ハンドラ
    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
            print("Connect failed...")
    }
    // BT2コネクタ接続済みハンドラ(connectBt後にコールバックする）
    public func centralManager(_ central: CBCentralManager,
                        didConnect peripheral: CBPeripheral) {
         print("connected")
        
        isConnected = true
        
        //接続成功したら利用するサービスUUIDを検索する
        peripheral.delegate = self
        //peripheral.discoverServices(nil) //全てのサービス検索する
        peripheral.discoverServices(
            [UUID_SERVICE_FINGERPRINT,UUID_SERVICE_DOORLOCK])//指定したサービスのみ検索する
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
            guard let services = peripheral.services else{
                print("error")
                return
            }
            print("\(services.count)個のサービスを発見。\(services)")
        if(services.count > 0){
            services.forEach {
                //発見したサービスに属するキャラクタリスティックを探す
                peripheral.discoverCharacteristics(nil, for:$0)
            }
        }
    }
    
    var FINGERPRT_CHARA_DATA1:CBCharacteristic? = nil
    var FINGERPRT_CHARA_DATA2:CBCharacteristic? = nil
    var FINGERPRT_CHARA_DATA3:CBCharacteristic? = nil
    var FINGERPRT_CHARA_EVTDETECT:CBCharacteristic? = nil
    var DOORLOCK_CHARA_STATE:CBCharacteristic? = nil

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let characteristics = service.characteristics {
            print("\(characteristics.count)個のキャラクタリスティックを発見。\(characteristics)")
            
            if(characteristics.count > 0){
                //「セッティングサービス」のキャラクタリスティックを保持する
                if(service.uuid.uuidString == STRING_SERVICE_FINGERPRINT){
                    characteristics.forEach {
                        if($0.uuid.uuidString == STRING_CHARACTERISTIC_FINGERPRINT_DATA1){
                            FINGERPRT_CHARA_DATA1 = $0
                        } else if($0.uuid.uuidString == STRING_CHARACTERISTIC_FINGERPRINT_DATA2){
                            FINGERPRT_CHARA_DATA2 = $0
                        } else if($0.uuid.uuidString == STRING_CHARACTERISTIC_FINGERPRINT_DATA3){
                            FINGERPRT_CHARA_DATA3 = $0
                        } else if($0.uuid.uuidString == STRING_CHARACTERISTIC_FINGERPRINT_EVTDETECT){
                            targetDevice.setNotifyValue(true,for:$0)
                            FINGERPRT_CHARA_EVTDETECT = $0
                        }
                    }
                }
                else if(service.uuid.uuidString == STRING_SERVICE_DOORLOCK){//ドア開錠サービス
                    characteristics.forEach {
                        if($0.uuid.uuidString == STRING_CHARACTERISTIC_FDORRLOCK_STATE){
                            DOORLOCK_CHARA_STATE = $0
                        }
                   }
                }
            }
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral,
                           didWriteValueFor characteristic: CBCharacteristic,error: Error?)
    {
        if let error = error {
            print("Failed... error: \(error)")
            return
        }
        print("ドア状態セット完了")
        //
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: {
            print("通知再度有効化")
            self.bWriteRequesting = false
        })
    }
    

    var strFingerCharData1 :String = ""
    var strFingerCharData2 :String = ""
    var strFingerCharData3 :String = ""
    //キャラクタリスティック読み込み完了コールバックイベント
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic,error: Error?)
    {
        if let error = error {
            print("Failed... error: \(error)")
            return
        }
        
        if(bWriteRequesting == true){
            return
        }
        //指紋認証サービスの値取得ブロック
        if(characteristic.service.uuid.uuidString == STRING_SERVICE_FINGERPRINT){
            if(characteristic.uuid.uuidString == STRING_CHARACTERISTIC_FINGERPRINT_EVTDETECT){
                print("指紋認証イベント検知")
                //DATA1〜DATA3の情報を取得する
                strFingerCharData1 = ""
                strFingerCharData2 = ""
                strFingerCharData3 = ""
                targetDevice.readValue(for:FINGERPRT_CHARA_DATA1!)
                targetDevice.readValue(for:FINGERPRT_CHARA_DATA2!)
                targetDevice.readValue(for:FINGERPRT_CHARA_DATA3!)
            } else {
                let strData :String = Data(characteristic.value!).hexEncodedString()
                if(characteristic.uuid.uuidString == STRING_CHARACTERISTIC_FINGERPRINT_DATA1){
                    strFingerCharData1 = strData
                }
                else if(characteristic.uuid.uuidString == STRING_CHARACTERISTIC_FINGERPRINT_DATA2){
                    strFingerCharData2 = strData
                }
                else if(characteristic.uuid.uuidString == STRING_CHARACTERISTIC_FINGERPRINT_DATA3){
                    strFingerCharData3 = strData
                }
                //すべてのデータ取得が完了したら結合して認証を行う
                if(strFingerCharData1 != ""
                    && strFingerCharData2 != ""
                    && strFingerCharData3 != ""){
                    
                    let strTotalData:String = strFingerCharData1 + strFingerCharData2 + strFingerCharData3
                    let int8TotalData = strTotalData.hex
//                    print(strTotalData)
//                    print(byteTotalData)
                    
                    var numIntegers: [Double] = []
                    for val8 in int8TotalData {
                        numIntegers.append(Double(val8)/255.0)
                    }
                    
                    let mlInputData = convertToMLArray(numIntegers)
                    
                    print("COnverted")
                    print(mlInputData)
                                 
                    var resultFinger :Int = 0
                    do {
                        let output = try converted().prediction(input: mlInputData)
                        print("FingerIndex=")
                        print(output.classLabel)
                        resultFinger = Int(output.classLabel)
                        
                        //
                        var doorVal: [UInt8] = [0x01]
                        if(output.classLabel == 2 ){
                            doorVal[0] = 1  //２の場合はNGにする
                            
                        } else{
                            doorVal[0] = 2//それ以外はOK
                        }
                        if(DOORLOCK_CHARA_STATE != nil){
                            //書き込み後はしばらく変化値をみないようにする
                            bWriteRequesting = true
                            let data = NSData(bytes: doorVal, length: 1)
                            targetDevice.writeValue(data as Data, for: DOORLOCK_CHARA_STATE!,
                            type: CBCharacteristicWriteType.withResponse)
                        }

                        //画面に状態検知＆変化を表示する
                        DispatchQueue.main.async {
                            let dt = Date()
                            let dateFormatter = DateFormatter()
                            dateFormatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "yyyy/MM/dd H:m:s", options: 0, locale: Locale(identifier: "ja_JP"))
                            print(dateFormatter.string(from: dt))
                            
                            self.lblClassfierDate.text  = dateFormatter.string(from: dt)
                            let strResult :String = doorVal[0] == 1 ? "NG":"OK"
                            self.lblClassfierResult.text = String(format: "%@ (Finger %d)", strResult, resultFinger )
                        }

                    } catch {
                        // エラー処理
                    }
                }
            }
        }
    }

    //デバイスと切断したときに呼ばれるコールバック
    public func centralManager(_ central: CBCentralManager,
    didDisconnectPeripheral peripheral: CBPeripheral,
    error: Error?){
        //targetDevice = nil
        print("切断しました")
        bFoundDevice = false
        isConnected = false
    }
    
        
    // stop scan
    public func stopScan() {
        if(centralManager != nil){
            //スキャンキャンセルさせる
            bScaning = false
            centralManager.stopScan()
            print("Stop Scan")
        } else {
            print("Not initialized yet")
        }
    }
    

    
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch (central.state) {
        case .unknown:
            print(".unknown")
            break
        case .resetting:
            print(".resetting")
            break
        case .unsupported:
            print(".unsupported")
            break
        case .unauthorized:
            print(".unauthorized")
            break
        case .poweredOff:
            print(".poweredOff")
            break
        case .poweredOn:
            print(".poweredOn")
            break
        @unknown default:
            print("A previously unknown central manager state occurred")
            break
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        
         centralManager = CBCentralManager(delegate: self, queue: nil, options: nil)
        //UUIDを生成する
        UUID_SERVICE_FINGERPRINT = CBUUID(string: STRING_SERVICE_FINGERPRINT)
        UUID_SERVICE_DOORLOCK = CBUUID(string: STRING_SERVICE_DOORLOCK)
        
        

        
    }

    
    func convertToMLArray(_ input: [Double]) -> MLMultiArray {
        let mlArray = try? MLMultiArray(shape: [256], dataType: MLMultiArrayDataType.double)


        for i in 0..<input.count {
            mlArray?[i] = NSNumber(value: input[i])
        }
        return mlArray!
    }

}

