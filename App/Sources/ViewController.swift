//
//  ViewController.swift
//  AE5I OTA Tool
//
//  AE5I 仪表 WiFi OTA 推送工具主界面
//

import UIKit
import UniformTypeIdentifiers

class ViewController: UIViewController, OTAClientDelegate, UIDocumentPickerDelegate {

    // MARK: - UI 元素

    private let scrollView = UIScrollView()
    private let stackView = UIStackView()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "AE5I 仪表 WiFi 升级"
        label.font = .systemFont(ofSize: 22, weight: .bold)
        label.textAlignment = .center
        return label
    }()

    private let statusLabel: UILabel = {
        let label = UILabel()
        label.text = "未连接"
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        return label
    }()

    private let wifiInfoLabel: UILabel = {
        let label = UILabel()
        label.text = "请先连接仪表 WiFi\nSSID: ZEEHO-xxxx  密码: 00A0400022 / 12345678"
        label.font = .systemFont(ofSize: 13)
        label.textColor = .systemOrange
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    private let fileButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("选择固件文件", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        button.backgroundColor = .systemBlue
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 10
        button.contentEdgeInsets = UIEdgeInsets(top: 14, left: 20, bottom: 14, right: 20)
        return button
    }()

    private let fileInfoLabel: UILabel = {
        let label = UILabel()
        label.text = "未选择文件"
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    private let pushButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("开始推送", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 18, weight: .bold)
        button.backgroundColor = .systemGreen
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 12
        button.contentEdgeInsets = UIEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
        button.isEnabled = false
        button.alpha = 0.5
        return button
    }()

    private let cancelButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("取消", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        button.backgroundColor = .systemRed
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 10
        button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 30, bottom: 10, right: 30)
        button.isHidden = true
        return button
    }()

    private let progressView: UIProgressView = {
        let pv = UIProgressView(progressViewStyle: .default)
        pv.progress = 0
        pv.trackTintColor = .systemGray5
        pv.progressTintColor = .systemGreen
        return pv
    }()

    private let progressLabel: UILabel = {
        let label = UILabel()
        label.text = "0%"
        label.font = .monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        label.textAlignment = .center
        return label
    }()

    private let logTextView: UITextView = {
        let tv = UITextView()
        tv.font = .systemFont(ofSize: 11)
        tv.backgroundColor = .systemGray6
        tv.layer.cornerRadius = 8
        tv.isEditable = false
        tv.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        return tv
    }()

    private let disclaimerButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("免责声明", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 12)
        return button
    }()

    // MARK: - 属性

    private var selectedFileURL: URL?
    private var otaClient: OTAClient?
    private var isPushing = false

    // MARK: - 生命周期

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupActions()
        showDisclaimerIfNeeded()
    }

    // MARK: - UI 搭建

    private func setupUI() {
        view.backgroundColor = .systemBackground

        // ScrollView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        // StackView
        stackView.axis = .vertical
        stackView.spacing = 16
        stackView.alignment = .fill
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stackView)

        // 添加子视图到 stackView
        let sections: [UIView] = [
            titleLabel,
            statusLabel,
            wifiInfoLabel,
            fileButton,
            fileInfoLabel,
            pushButton,
            cancelButton,
            progressView,
            progressLabel,
            logTextView,
            disclaimerButton
        ]

        for section in sections {
            let wrapper = UIView()
            wrapper.translatesAutoresizingMaskIntoConstraints = false
            section.translatesAutoresizingMaskIntoConstraints = false
            wrapper.addSubview(section)

            NSLayoutConstraint.activate([
                section.topAnchor.constraint(equalTo: wrapper.topAnchor),
                section.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 16),
                section.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -16),
                section.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
            ])

            // 按钮和取消按钮居中
            if section == fileButton || section == pushButton || section == cancelButton {
                section.leadingAnchor.constraint(greaterThanOrEqualTo: wrapper.leadingAnchor, constant: 40).isActive = true
                section.trailingAnchor.constraint(lessThanOrEqualTo: wrapper.trailingAnchor, constant: -40).isActive = true
                section.centerXAnchor.constraint(equalTo: wrapper.centerXAnchor).isActive = true
            }

            stackView.addArrangedSubview(wrapper)
        }

        // logTextView 固定高度
        logTextView.heightAnchor.constraint(equalToConstant: 200).isActive = true

        // 约束
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 20),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -20),
            stackView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
        ])
    }

    private func setupActions() {
        fileButton.addTarget(self, action: #selector(selectFile), for: .touchUpInside)
        pushButton.addTarget(self, action: #selector(startPush), for: .touchUpInside)
        cancelButton.addTarget(self, action: #selector(cancelPush), for: .touchUpInside)
        disclaimerButton.addTarget(self, action: #selector(showDisclaimer), for: .touchUpInside)
    }

    // MARK: - 文件选择

    @objc private func selectFile() {
        // 支持所有文件类型
        let types: [UTType] = [.item]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        picker.modalPresentationStyle = .formSheet
        present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        selectedFileURL = url

        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let fileSize = attributes[.size] as? UInt64 ?? 0
            let sizeMB = Double(fileSize) / 1024.0 / 1024.0
            fileInfoLabel.text = String(format: "%@\n%.1f MB", url.lastPathComponent, sizeMB)
            fileInfoLabel.textColor = .label

            pushButton.isEnabled = !isPushing
            pushButton.alpha = isPushing ? 0.5 : 1.0
            pushButton.setTitle("开始推送", for: .normal)
            pushButton.backgroundColor = .systemGreen
        } catch {
            fileInfoLabel.text = "读取文件失败: \(error.localizedDescription)"
        }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        // 用户取消，不做处理
    }

    // MARK: - 推送

    @objc private func startPush() {
        guard let fileURL = selectedFileURL else {
            showAlert(title: "提示", message: "请先选择固件文件")
            return
        }

        isPushing = true
        pushButton.isEnabled = false
        pushButton.alpha = 0.5
        cancelButton.isHidden = false
        fileButton.isEnabled = false
        fileButton.alpha = 0.5
        progressView.progress = 0
        progressLabel.text = "0%"
        logTextView.text = ""

        appendLog("开始推送固件: \(fileURL.lastPathComponent)")

        otaClient = OTAClient()
        otaClient?.delegate = self

        Task {
            await otaClient?.pushFirmware(fileURL: fileURL)
        }
    }

    @objc private func cancelPush() {
        otaClient?.cancel()
        isPushing = false
        cancelButton.isHidden = true
        pushButton.isEnabled = selectedFileURL != nil
        pushButton.alpha = selectedFileURL != nil ? 1.0 : 0.5
        fileButton.isEnabled = true
        fileButton.alpha = 1.0
        appendLog("用户取消推送")
    }

    // MARK: - OTAClientDelegate

    func otaClient(_ client: OTAClient, didChangeState state: OTAState) {
        statusLabel.text = state.description

        switch state {
        case .success:
            pushButton.backgroundColor = .systemGreen
            pushButton.setTitle("推送成功", for: .normal)
            cancelButton.isHidden = true
            fileButton.isEnabled = true
            fileButton.alpha = 1.0
            isPushing = false
            showAlert(title: "成功", message: "固件推送成功！\n仪表将自动重启并升级，请勿断电。")
        case .failed(let msg):
            pushButton.backgroundColor = .systemRed
            pushButton.setTitle("推送失败", for: .normal)
            cancelButton.isHidden = true
            fileButton.isEnabled = true
            fileButton.alpha = 1.0
            isPushing = false
            showAlert(title: "失败", message: msg)
        case .cancelled:
            statusLabel.text = "已取消"
        default:
            break
        }
    }

    func otaClient(_ client: OTAClient, didLog message: String) {
        appendLog(message)
    }

    func otaClient(_ client: OTAClient, didUpdateProgress progress: Int, sent: UInt64, total: UInt64) {
        progressView.progress = Float(progress) / 100.0
        let sentMB = Double(sent) / 1024.0 / 1024.0
        let totalMB = Double(total) / 1024.0 / 1024.0
        progressLabel.text = String(format: "%d%%  (%.1f / %.1f MB)", progress, sentMB, totalMB)
    }

    private func appendLog(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        logTextView.text += "[\(timestamp)] \(message)\n"
        let bottom = NSRange(location: max(0, logTextView.text.count - 1), length: 1)
        logTextView.scrollRangeToVisible(bottom)
    }

    // MARK: - 免责声明

    private func showDisclaimerIfNeeded() {
        let hasShown = UserDefaults.standard.bool(forKey: "disclaimerShown")
        if !hasShown {
            showDisclaimer()
        }
    }

    @objc private func showDisclaimer() {
        let alert = UIAlertController(
            title: "免责声明",
            message: """
            本工具仅供技术研究和合法售后维护使用。

            • 固件升级有风险，操作不当可能导致仪表变砖
            • 推送过程中请勿断电或断开WiFi
            • 仅限用于您拥有合法所有权的设备
            • 因使用本工具造成的任何损失，开发者不承担责任

            继续使用即表示您已阅读并同意以上条款。
            """,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "我已阅读并同意", style: .default) { _ in
            UserDefaults.standard.set(true, forKey: "disclaimerShown")
        })
        alert.addAction(UIAlertAction(title: "退出", style: .cancel) { _ in
            exit(0)
        })
        present(alert, animated: true)
    }

    // MARK: - 工具

    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }
}
