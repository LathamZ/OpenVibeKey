# 可由接收者安装的个人代码签名证书

2026-10-30 · 设计稿，尚未签发新的通用证书，也未轮换当前 VibeKey 身份。

## 目标与选定路线

让愿意信任 LathamZ 软件的 macOS 接收者安装公开证书，由同一个长期开发者身份签署多个程序。接收者明确决定是否信任代码签名；开发者独占私钥。此路线不以购买 Apple Developer Program 为前提。

首版推荐固定自签名叶证书（CA:false），而非私有根 CA。多程序可以共享签名身份，不需要为每个 App 签发证书。只有以后确实需要多签名人、离线根密钥和频繁轮换时，再另行评审私有 CA 体系。

## 拟定证书规范

| 字段 | 拟定值或规则 |
|---|---|
| 公开名称 CN | LathamZ Software Signing，签发前确认；不含单个项目名 |
| 发行者 | 与主体相同，自签名；不标成 Apple Developer ID |
| 组织、邮箱、域名 | 未确认前不填，不虚构公司或身份验证 |
| X.509 版本 | v3 |
| 密钥 | RSA 3072 bit |
| 签名摘要 | SHA-256 |
| 序列号 | 密码学随机，至少128bit，保持正数并唯一 |
| 有效期 | 拟定5年；提前90天进入续期／迁移检查，非每次更新重建 |
| Basic Constraints | critical, CA:false，不签发子证书 |
| Key Usage | critical, digitalSignature |
| Extended Key Usage | critical, codeSigning；不用于TLS、邮件或其他身份用途 |
| 密钥标识 | Subject Key Identifier 与 Authority Key Identifier |
| 识别方式 | SHA-256证书指纹，名称只用于显示 |

CA:false 描述证书不能签发其他证书。对自签名叶证书授予 codeSign 信任时，操作系统仍把它作为该用途的信任锚；这不等于创建全用途根CA。接收者信任范围必须明确展示。

## 密钥与文件分工

公开交付包拟包含：

```text
LathamZ-Software-Signing-public-v1/
  LathamZ-Software-Signing.cer   # DER，仅公开证书
  fingerprint-sha256.txt        # 实际签发后填写真实指纹
  manifest.json                # 名称、序列号、有效期、用途、版本及下载来源
  README-zh-CN.md               # 安装、核验、移除和局限
```

这里是结构设计，没有生成可安装证书或伪造指纹。开发者私钥只保存在受保护钥匙串；如需灾备，另做有密码的P12备份，并与公开交付包分开。公开包绝不包含私钥、P12、密码或签名机配置。P12是备份／迁移身份的格式，不是给普通软件使用者安装的文件。

## 接收者安装流程

详见 [接收者指引](RECIPIENT-GUIDE.md)。核心要求：

1. 从开发者提供的可信渠道获取公开包，并用另一个已确认渠道核对SHA-256指纹。
2. 只导入当前用户登录钥匙串。
3. 明确选择仅信任代码签名用途；SSL、邮件等其他用途保留系统默认。
4. 系统若要求密码，由接收者本人输入，安装器不收集密码。
5. 再安装已签好的App；所需辅助功能、输入监控等按App分别授权。

信任含义是“接受持有此私钥的人签署的代码身份”，不是“以后所有签名程序都不需要检查”。名称、manifest或同目录hash文件本身不能证明初次收到的证书来自正确的人。

## Gatekeeper边界与必须验证的路径

证书信任、签名有效性、Gatekeeper／公证和应用隐私权限分别判断。Apple说明，默认下载软件检查包含开发者身份和公证。自签名证书安装后，仍可能需要接收者进行系统允许的逐App首次运行确认，不能承诺“装一次证书，以后所有App都自动放行”。

本轮只读检查：当前 VibeKey 的 `codesign --verify --deep --strict` 通过，`spctl --assess --type execute` 返回rejected。它仍是本机已运行的程序，因此这个检查既不能冒充真实下载安装测试，也明确说明签名校验通过不等于默认Gatekeeper认可。

验收前不修改全局Gatekeeper，不批量删除隔离标记，不发布隐藏信任或申请隐私权限的安装脚本。

## 多App和更新规则

- 一个稳定开发者身份可签多个App；每个App固定自己的Bundle ID，不把一个App的权限当成所有App共享。
- 普通更新复用同一证书与私钥，比较指定要求并从实际应用上下文核对权限。
- 现有 VibeKey 保留原证书，继续使用已验证的更新链路。新证书先用于新项目；若以后迁移VibeKey，单独备份和验收，明确可能需要一次授权。
- 换证书／到期：发布新公开证书、指纹与迁移说明，由接收者明确信任；自签名叶证书不提供Apple式自动撤销或无感换证。
- 私钥丢失或泄漏：停止使用该身份签署新包，通知接收者撤销旧证书信任，再迁移新身份；不承诺所有离线接收者自动得知。

## 验收标准

首条路径限定一个App和一台接收者Mac，先跑通再扩大：

- [ ] 确认公开名称和发布身份，签发新叶证书，记录真实SHA-256指纹。
- [ ] 公开包只有证书和说明，静态检查不包含任何私钥、PKCS#12备份或密码。
- [ ] 在独立Mac或干净测试账户，通过实际下载获取App，保留正常隔离标记。
- [ ] 记录安装证书前后：签名校验、Gatekeeper评估、首次启动各自结果及实际所需步骤。
- [ ] 只增加当前用户、代码签名用途信任；其他信任条目不变。
- [ ] 为App完成首次必要授权，正常升级到第二个不同构建，不改系统授权，验证保留。
- [ ] 测试证书移除／取消信任；不承诺删除证书必然阻止所有已运行或已放行App。
- [ ] 由接收者看懂并确认最终安装说明，再考虑对外发布。

当前状态：设计完成；通用证书签发、独立接收者环境测试及对外发布均待实施。已验证的VibeKey本机build21→22保留授权结果不替代这些验收。

## 官方依据

- [Apple TN2206：签名身份、指定要求和不同子系统信任策略](https://developer.apple.com/library/archive/technotes/tn2206/_index.html)
- [Apple Platform Security：Gatekeeper与运行时保护](https://support.apple.com/guide/security/gatekeeper-and-runtime-protection-sec5599b66df/web)
- [Apple Keychain：导入与导出证书、密钥](https://support.apple.com/guide/keychain-access/import-and-export-keychain-items-kyca35961/mac)

规范中的名称、有效期、包结构和流程为本项目设计决策，不是Apple认证或兼容性保证。
