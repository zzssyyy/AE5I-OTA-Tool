# AE5I 仪表 WiFi OTA 升级工具

适用于春风 AE5I（凌阳 Sunplus Gemini 平台）智能仪表的无线固件升级工具。

## 协议说明

本工具协议逆向自仪表固件 `libapis.so.1.0.0`：

| 参数 | 值 |
|------|-----|
| TCP 端口 | 10086 |
| 仪表 IP | 192.168.0.1 |
| 消息头 | 10 字节 |
| 消息类型 | 0x10000001 ~ 0x10000007 |
| WiFi SSID | ZEEHO-xxxx |
| WiFi 密码 | 00A0400022 |

### 消息头格式

```
字节0-1:  00 00          (magic)
字节2-5:  cmd (大端32位)  消息类型
字节6-9:  length (大端32位) payload长度
```

### 消息类型

| 类型 | 值 | 方向 | 说明 |
|------|-----|------|------|
| VERSION | 0x10000001 | 手机→仪表 | 查询版本 |
| LOG | 0x10000002 | - | 日志 |
| OTA_START | 0x10000003 | 手机→仪表 | 开始OTA（含文件大小+MD5） |
| OTA_PREPARE | 0x10000004 | 仪表→手机 | 准备接收 |
| OTA_PROGRESS | 0x10000005 | 手机→仪表 | 传输数据分片 |
| OTA_VERIFY | 0x10000006 | 仪表→手机 | 校验结果 |
| OTA_END | 0x10000007 | 手机→仪表 | 传输结束 |

### 升级流程

```
连接 192.168.0.1:10086
  → VERSION (查询版本)
  → OTA_START (JSON: size+md5+name)
  ← OTA_PREPARE
  → OTA_PROGRESS (分片4KB，循环)
  → OTA_END
  ← OTA_VERIFY
  → 仪表自动重启升级
```

## 使用方法

1. iPhone 连接仪表 WiFi（SSID: ZEEHO-xxxx，密码: 00A0400022）
2. 打开 App，点击"选择固件文件"，选择 `.bin` 升级包
3. 点击"开始推送"
4. 等待传输完成，仪表自动重启升级

## 构建

### 使用 XcodeGen

```bash
brew install xcodegen
cd AE5I_OTA_Tool
xcodegen generate
open AE5I_OTA_Tool.xcodeproj
```

### 使用 GitHub Actions

推送代码到 GitHub 后，Actions 会自动构建 IPA。

## 项目结构

```
AE5I_OTA_Tool/
├── project.yml              # XcodeGen 配置
├── README.md
├── .github/workflows/
│   └── build.yml            # 自动构建
└── App/
    ├── Info.plist
    └── Sources/
        ├── AppDelegate.swift
        ├── ViewController.swift    # 主界面
        ├── OTAClient.swift         # OTA 客户端 (Network框架)
        └── OTAProtocol.swift       # 协议定义
```

## 免责声明

本工具仅供技术研究和合法售后维护使用。

- 固件升级有风险，操作不当可能导致仪表变砖
- 推送过程中请勿断电或断开 WiFi
- 仅限用于您拥有合法所有权的设备
- 因使用本工具造成的任何损失，开发者不承担责任

## 适用车型

- 春风 8368 U（AE5I，5寸仪表，凌阳 Sunplus Gemini 平台）

不适用 AE3（全志 T507 平台，端口为 10950）。
