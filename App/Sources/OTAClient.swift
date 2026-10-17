//
//  OTAClient.swift
//  AE5I OTA Tool
//
//  AE5I 仪表 WiFi OTA 客户端
//  使用 Network 框架 (NWConnection) 实现 TCP 通信
//

import Foundation
import Network

protocol OTAClientDelegate: AnyObject {
    func otaClient(_ client: OTAClient, didChangeState state: OTAState)
    func otaClient(_ client: OTAClient, didLog message: String)
    func otaClient(_ client: OTAClient, didUpdateProgress progress: Int, sent: UInt64, total: UInt64)
}

class OTAClient {
    weak var delegate: OTAClientDelegate?

    private var connection: NWConnection?
    private var host: String
    private var port: UInt16
    private var isCancelled = false

    // 接收缓冲区
    private var recvBuffer = Data()
    private let recvQueue = DispatchQueue(label: "com.ae5i.ota.recv")

    init(host: String = OTAConfig.defaultHost, port: UInt16 = UInt16(OTAConfig.defaultPort)) {
        self.host = host
        self.port = port
    }

    // MARK: - 连接

    func connect(timeout: TimeInterval = 5.0) {
        isCancelled = false
        setState(.connecting)
        log("正在连接 \(host):\(port) ...")

        let host = NWEndpoint.Host(self.host)
        let port = NWEndpoint.Port(rawValue: self.port)!
        connection = NWConnection(host: host, port: port, using: .tcp)

        connection?.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                self.setState(.connected)
                self.log("已连接到仪表")
                self.receiveLoop()
            case .failed(let error):
                self.setState(.failed("连接失败: \(error.localizedDescription)"))
                self.log("连接失败: \(error)")
            case .cancelled:
                self.log("连接已取消")
            default:
                break
            }
        }

        connection?.start(queue: recvQueue)

        // 超时处理
        recvQueue.asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self = self else { return }
            if case .connecting = self.currentState {
                self.cancel()
                self.setState(.failed("连接超时，请确认已连接仪表WiFi"))
            }
        }
    }

    func cancel() {
        isCancelled = true
        connection?.cancel()
        connection = nil
        setState(.cancelled)
    }

    private var currentState: OTAState = .idle

    private func setState(_ state: OTAState) {
        currentState = state
        DispatchQueue.main.async {
            self.delegate?.otaClient(self, didChangeState: state)
        }
    }

    private func log(_ message: String) {
        DispatchQueue.main.async {
            self.delegate?.otaClient(self, didLog: message)
        }
    }

    // MARK: - 发送消息

    private func send(_ message: OTAMessage, completion: ((Error?) -> Void)? = nil) {
        let data = message.encode()
        connection?.send(content: data, completion: .contentProcessed { error in
            completion?(error)
        })
    }

    // MARK: - 接收消息

    private func receiveLoop() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            if let error = error {
                self.log("接收错误: \(error)")
                return
            }

            if let data = data, !data.isEmpty {
                self.recvBuffer.append(data)
                self.processReceivedData()
            }

            if isComplete {
                self.log("连接已关闭")
                return
            }

            self.receiveLoop()
        }
    }

    private func processReceivedData() {
        // 尝试解析完整消息
        while recvBuffer.count >= OTAConfig.headerSize {
            guard let header = OTAMessageHeader.decode(from: recvBuffer) else {
                // 无法解析消息头，丢弃一个字节继续尝试
                recvBuffer.removeFirst()
                continue
            }

            let totalLength = OTAConfig.headerSize + Int(header.payloadLength)
            guard recvBuffer.count >= totalLength else {
                break  // 数据不完整，等待更多
            }

            let payload = recvBuffer.subdata(in: OTAConfig.headerSize..<totalLength)
            recvBuffer.removeFirst(totalLength)

            let message = OTAMessage(cmd: header.cmd, payload: payload)
            handleMessage(message)
        }
    }

    // 消息处理（由子类或外部设置）
    var messageHandler: ((OTAMessage) -> Void)?

    private func handleMessage(_ message: OTAMessage) {
        log("收到 [\(message.header.cmd.name)] (\(message.payload.count)字节)")
        messageHandler?(message)
    }

    // MARK: - 带响应的发送

    private func sendAndWait(_ cmd: OTACmd, payload: Data = Data(),
                             timeout: TimeInterval = 10.0,
                             expectedCmd: OTACmd? = nil) async throws -> OTAMessage {
        return try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false

            let timeoutWorkItem = DispatchWorkItem {
                if !hasResumed {
                    hasResumed = true
                    continuation.resume(throwing: NSError(domain: "OTAClient", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "等待响应超时"]))
                }
            }

            messageHandler = { message in
                if !hasResumed {
                    if let expected = expectedCmd, message.header.cmd != expected {
                        return  // 不是期望的响应，继续等
                    }
                    hasResumed = true
                    timeoutWorkItem.cancel()
                    self.messageHandler = nil
                    continuation.resume(returning: message)
                }
            }

            send(OTAMessage(cmd: cmd, payload: payload)) { error in
                if let error = error, !hasResumed {
                    hasResumed = true
                    timeoutWorkItem.cancel()
                    self.messageHandler = nil
                    continuation.resume(throwing: error)
                }
            }

            recvQueue.asyncAfter(deadline: .now() + timeout, execute: timeoutWorkItem)
        }
    }

    // MARK: - 完整 OTA 流程

    func pushFirmware(fileURL: URL) async {
        isCancelled = false

        do {
            // 1. 读取文件
            let fileData = try Data(contentsOf: fileURL)
            let fileSize = UInt64(fileData.count)
            let md5 = fileData.md5Hex()
            let fileName = fileURL.lastPathComponent

            log("固件: \(fileName), 大小: \(fileSize) 字节, MD5: \(md5)")

            // 2. 连接
            connect()
            try await waitForConnected()

            if isCancelled { return }

            // 3. 查询版本（可选）
            setState(.queryingVersion)
            do {
                let versionResp = try await sendAndWait(.version, timeout: 5.0, expectedCmd: .version)
                if let versionStr = String(data: versionResp.payload, encoding: .utf8) {
                    log("仪表版本: \(versionStr)")
                }
            } catch {
                log("版本查询失败（不影响升级）: \(error.localizedDescription)")
            }

            if isCancelled { return }

            // 4. 发送 OTA_START
            setState(.startingOTA)
            let startInfo = OTAStartInfo(size: fileSize, md5: md5, name: fileName, type: "gemini")
            guard let startPayload = startInfo.encode() else {
                throw NSError(domain: "OTAClient", code: -2, userInfo: [NSLocalizedDescriptionKey: "OTA_START编码失败"])
            }

            log("发送 OTA_START...")
            let prepareResp = try await sendAndWait(.otaStart, payload: startPayload,
                                                     timeout: 15.0, expectedCmd: .otaPrepare)
            log("仪表已准备好接收数据")

            if isCancelled { return }

            // 5. 分片传输
            setState(.waitingPrepare)
            setState(.transferring(progress: 0))
            var sent: UInt64 = 0
            let chunkSize = OTAConfig.chunkSize

            for offset in stride(from: 0, to: Int(fileSize), by: chunkSize) {
                if isCancelled {
                    send(OTAMessage(cmd: .otaCancel))
                    return
                }

                let end = min(offset + chunkSize, Int(fileSize))
                let chunk = fileData.subdata(in: offset..<end)

                try await sendChunk(chunk)
                sent = UInt64(end)

                let progress = Int(sent * 100 / fileSize)
                DispatchQueue.main.async {
                    self.delegate?.otaClient(self, didUpdateProgress: progress, sent: sent, total: fileSize)
                }
                setState(.transferring(progress: progress))
            }

            log("文件传输完成")

            if isCancelled { return }

            // 6. 发送 OTA_END
            setState(.endingOTA)
            log("发送 OTA_END...")
            let verifyResp = try await sendAndWait(.otaEnd, timeout: 60.0, expectedCmd: .otaVerify)

            // 7. 解析校验结果
            setState(.verifying)
            if let verifyStr = String(data: verifyResp.payload, encoding: .utf8) {
                log("校验响应: \(verifyStr)")
            }

            setState(.success)
            log("推送成功！仪表将自动重启并升级")

        } catch {
            if !isCancelled {
                setState(.failed(error.localizedDescription))
                log("错误: \(error.localizedDescription)")
            }
        }
    }

    private func waitForConnected() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var hasResumed = false
            let checkWorkItem = DispatchWorkItem {
                if !hasResumed {
                    if case .connected = self.currentState {
                        hasResumed = true
                        continuation.resume()
                    } else if case .failed(let msg) = self.currentState {
                        hasResumed = true
                        continuation.resume(throwing: NSError(domain: "OTAClient", code: -3,
                            userInfo: [NSLocalizedDescriptionKey: msg]))
                    } else {
                        self.recvQueue.asyncAfter(deadline: .now() + 0.1, execute: checkWorkItem)
                    }
                }
            }
            recvQueue.asyncAfter(deadline: .now() + 0.1, execute: checkWorkItem)
        }
    }

    private func sendChunk(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            send(OTAMessage(cmd: .otaProgress, payload: data)) { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}

// MARK: - Data MD5 扩展

import CryptoKit

extension Data {
    func md5Hex() -> String {
        let digest = Insecure.MD5.hash(data: self)
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }
}
