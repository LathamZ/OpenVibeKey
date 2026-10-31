#!/usr/bin/env python3
"""Package a verified app with public material only. Never install, trust, or change security policy."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--app', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--public-certificate-dir', type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
app = args.app.resolve()
output = args.output.resolve()
if output.exists():
    raise SystemExit('Output already exists; preserve or choose a new release directory')
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
with (app/'Contents/Info.plist').open('rb') as stream:
    info = plistlib.load(stream)
if info['CFBundleDisplayName'] != 'The Vibekey':
    raise SystemExit('Unexpected application identity')
output.mkdir(parents=True)
staging = output/'The Vibekey'
staging.mkdir()
shutil.copytree(app, staging/app.name, symlinks=True)
(staging/'Applications').symlink_to('/Applications')
shutil.copy2(root/'LICENSE', staging/'LICENSE.txt')
shutil.copy2(root/'THE-VIBEKEY.md', staging/'RELEASE-NOTES.md')
shutil.copy2(root/'DESKTOP-ADAPTERS.md', staging/'DESKTOP-ADAPTERS.md')
if args.public_certificate_dir:
    public = args.public_certificate_dir.resolve()
    dest = staging/'公开签名证书'
    dest.mkdir()
    allowed = ['LathamZ-Software-Signing.cer', 'fingerprint-sha256.txt', 'manifest.json', 'README-zh-CN.md']
    for filename in allowed:
        path = public/filename
        if not path.is_file() or path.is_symlink():
            raise SystemExit('Expected regular public certificate file missing: '+filename)
        shutil.copy2(path, dest/filename)
(staging/'安装说明.txt').write_text('''The Vibekey · ''' + info['CFBundleShortVersionString'] + '''

1. 将 The Vibekey.app 拖到 Applications（应用程序）。支持 Apple Silicon 和 Intel，最低 macOS 13。
2. 退出旧 Open VibeKey、Open VibeKey Dev 或其他同设备控制软件，再打开新版本。
3. 这是 LathamZ Software Signing 自签名的个人预览包，未通过 Apple 公证。公钥证书在“公开签名证书”文件夹；请先通过可信渠道核对指纹。它不含私钥，不需要 P12。导入证书或设置信任不会自动通过 Gatekeeper，也不会自动授予隐私权限。若系统阻止运行，请核对来源后使用系统“隐私与安全性”提供的针对本 App 的“仍要打开”流程；不要关闭全局安全检查。无法放行时保留提示截图联系开发者。
4. 首次启动按“连接与权限”页面完成辅助功能和输入监控。麦克风电平、通知为可选；另一台电脑的权限不能从本机迁移。连接 AU05 并唤醒后自动准备导航，无需手动勾选监听。
5. 要使用 Codex 会话，需要该 Mac 安装并登录 Codex 桌面版；在其快捷键设置中将 focusMainChat／聚焦主聊天输入框绑定为 Control+Option+Command+F12。
6. 双击旋钮仅预选目标App并改变菜单栏外围点颜色，不会前置目标App；长按旋钮并松开呼出该目标的轨道，旋转选择、短按确认后才打开／前置会话；麦克风键上一页、勾键下一页、叉键取消。详细操作在设置“高效使用”；灵敏度、玻璃浓度与底色透明度在“设备设置”。后两项 App 不需要 CLI 或终端连接器。

已知范围：Codex、DeepSeek Harness 和 Claude App 中 Code 页面已接入会话选择与主输入框定位。后两者仅列出已展开侧栏中的会话；请先打开对应 App 并展开侧栏。微信本轮暂不适配。新建会话、模型导航、统一停止／继续仍在方案评审中。

包内没有个人聊天、设备序列号、用户配置或签名私钥。本机完成了构建和包校验；接收者 Mac 首次安装和实机手感需要单独验收。
''')
# Reject accidental secrets/artifacts before building either shareable file.
for path in staging.rglob('*'):
    if path.is_symlink():
        if path != staging/'Applications':
            raise SystemExit('Unexpected symlink: '+str(path))
        continue
    if path.is_file() and (path.suffix.lower() in {'.p12','.pfx','.key','.keychain','.keychain-db','.plist.bak'} or path.name.startswith('preferences-')):
        raise SystemExit('Private artifact in staging: '+str(path))
    if path.is_file() and path.suffix.lower() in {'.pem','.txt','.json'} and b'PRIVATE KEY' in path.read_bytes():
        raise SystemExit('Private key material in staging')
version = info['CFBundleShortVersionString']
architectures = subprocess.check_output(['lipo', '-archs', str(app/'Contents/MacOS/VibeKitApp')], text=True).split()
architecture_label = 'universal' if set(architectures) == {'arm64', 'x86_64'} else '-'.join(architectures)
zip_path = output/f'The-Vibekey-{version}-{architecture_label}.zip'
dmg_path = output/f'The-Vibekey-{version}-{architecture_label}.dmg'
subprocess.run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(staging), str(zip_path)], check=True)
subprocess.run(['hdiutil', 'create', '-volname', 'The Vibekey', '-srcfolder', str(staging), '-format', 'UDZO', '-fs', 'HFS+', str(dmg_path)], check=True)
manifest = {'name':info['CFBundleDisplayName'],'version':version,'build':info['CFBundleVersion'],
            'architectures':architectures,'minimum_macos':info['LSMinimumSystemVersion'],
            'notarized':False,'recipient_installation_verified':False,
            'files':{p.name:{'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in [zip_path,dmg_path]}}
(output/'manifest.json').write_text(json.dumps(manifest,indent=2,ensure_ascii=False)+'\n')
(output/'SHA256SUMS.txt').write_text(''.join(meta['sha256']+'  '+name+'\n' for name,meta in manifest['files'].items()))
print(json.dumps(manifest,ensure_ascii=False,indent=2))
