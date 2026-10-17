//
//  OTAProtocol.swift
//  AE5I OTA Tool
//
//  AE5I 仪表 WiFi OTA 协议定义
//  逆向自 libapis.so.1.0.0 (凌阳 Sunplus Gemini 平台)
//

import Foundation

// MARK: - 协议常量

enum OTAConfig {
    static let defaultHost = "192.168.0.1"
    static let defaultPort = 10086
    static let headerSize = 10
    static let chunkSize = 4096
    static let wifiSSIDPrefix = "ZEEHO-"
    static let wifiPassword = "00A0400022"
}

// MARK: - 消息类型

enum OTACmd: UInt32 {
    case version      = 0x10000001  // 查询版本
    case log          = 0x10000002  // 日志
    case otaStart     = 0x10000003  // 开始OTA（手机→仪表）
    case otaPrepare   = 0x10000004  // 准备传输（仪表→手机）
    case otaProgress  = 0x10000005  // 传输数据（手机→仪表）
    case otaVerify    = 0x10000006  // 校验（仪表→手机）
    case otaEnd       = 0x10000007  // 结束（手机→仪表）
    case otaCancel    = 0x10000043  // 取消

    var name: String {
        switch self {
        case .version:     return "VERSION"
        case .log:         return "LOG"
        case .otaStart:    return "OTA_START"
        case .otaPrepare:  return "OTA_PREPARE"
        case .otaProgress: return "OTA_PROGRESS"
        case .otaVerify:   return "OTA_VERIFY"
        case .otaEnd:      return "OTA_END"
        case .otaCancel:   return "OTA_CANCEL"
        }
    }
}

// MARK: - 消息头

/// 10字节消息头: magic(2) + cmd(4,大端) + length(4,大端)
struct OTAMessageHeader {
    let magic0: UInt8 = 0x00
    let magic1: UInt8 = 0x00
    let cmd: OTACmd
    let payloadLength: UInt32

    func encode() -> Data {
        var data = Data()
        data.append(magic0)
        data.append(magic1)
        withUnsafeBytes(of: cmd.rawValue.bigEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: payloadLength.bigEndian) { data.append(contentsOf: $0) }
        return data
    }

    static func decode(from data: Data) -> OTAMessageHeader? {
        guard data.count >= OTAConfig.headerSize else { return nil }
        let cmdRaw = data.subdata(in: 2..<6).withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian
        let length = data.subdata(in: 6..<10).withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian
        guard let cmd = OTACmd(rawValue: cmdRaw) else { return nil }
        return OTAMessageHeader(cmd: cmd, payloadLength: length)
    }
}

// MARK: - 完整消息

struct OTAMessage {
    let header: OTAMessageHeader
    let payload: Data

    init(cmd: OTACmd, payload: Data = Data()) {
        self.header = OTAMessageHeader(cmd: cmd, payloadLength: UInt32(payload.count))
        self.payload = payload
    }

    func encode() -> Data {
        return header.encode() + payload
    }
}

// MARK: - OTA Start Payload

struct OTAStartInfo: Codable {
    let size: UInt64
    let md5: String
    let name: String
    let type: String  // "gemini" for AE5I

    func encode() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try? encoder.encode(self)
    }
}

// MARK: - OTA 状态

enum OTAState: Equatable {
    case idle
    case connecting
    case connected
    case queryingVersion
    case startingOTA
    case waitingPrepare
    case transferring(progress: Int)
    case endingOTA
    case verifying
    case success
    case failed(String)
    case cancelled

    var description: String {
        switch self {
        case .idle:              return "空闲"
        case .connecting:        return "正在连接仪表..."
        case .connected:         return "已连接"
        case .queryingVersion:   return "查询版本..."
        case .startingOTA:       return "发送OTA开始..."
        case .waitingPrepare:    return "等待仪表准备..."
        case .transferring(let p): return "传输中 \(p)%"
        case .endingOTA:         return "结束传输..."
        case .verifying:         return "仪表校验中..."
        case .success:           return "推送成功"
        case .failed(let msg):   return "失败: \(msg)"
        case .cancelled:         return "已取消"
        }
    }
}
