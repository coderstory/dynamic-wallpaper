import SwiftUI
import AppKit

/// ffmpeg 安装途径说明（App 不内置、不下载 —— 安装是用户自己的动作）。
/// 每条途径都要带可复制的命令与它的真实坑：漏了 xattr 或 macOS 27 警示，用户照抄会失败。
struct InstallPathwaysView: View {

    /// 装好后回窗口点它重查（新鲜化出口之一）。
    let onRecheck: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("安装 ffmpeg")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.pTitle)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.pMuted)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.pChipBg))
                }
                .buttonStyle(.plain)
                .accessibilityElement()
                .accessibilityLabel(Text("关闭"))
                .accessibilityIdentifier("pathways-close")
            }
            Text("动态壁纸不内置、也不联网下载 ffmpeg —— 安装是你自己的动作，装好后回到本窗口点重新检测即可。")
                .font(.system(size: 11.5))
                .foregroundStyle(Color.pMuted)
                .fixedSize(horizontal: false, vertical: true)

            pathway(
                id: "pathway:brew",
                title: "① Homebrew",
                detail: "最省事的一条。",
                command: "brew install ffmpeg",
                caveat: "macOS 27 上会因 lame / dav1d 没有 bottle 而失败。变通：brew install --build-from-source ffmpeg（慢，全程本地编译）。"
            )
            pathway(
                id: "pathway:static",
                title: "② 静态二进制（evermeet.cx）",
                detail: "本机当前就是这条路线。",
                command: "xattr -dr com.apple.quarantine <二进制路径>",
                caveat: "解压后必须先执行上面这条去掉隔离标记，否则 Gatekeeper 会直接拦死。站点只出 Intel x86_64 构建，Apple Silicon 上经 Rosetta 运行。"
            )
            pathway(
                id: "pathway:source",
                title: "③ 源码编译",
                detail: "前两条都不顺时的兜底。",
                command: "./configure && make",
                caveat: "也可以用 MacPorts：sudo port install ffmpeg（macOS 27 上的可用性未验证）。"
            )

            HStack {
                Spacer()
                Button("关闭") { dismiss() }
                    .buttonStyle(GlowButton())
                    .accessibilityIdentifier("pathways-close-bottom")
                    .keyboardShortcut(.cancelAction)
                Button("重新检测") { onRecheck() }
                    .buttonStyle(GlowButton(primary: true))
                    .accessibilityIdentifier("pathways-recheck")
            }
        }
        .padding(14)
        .frame(width: 560, alignment: .leading)
        .background(Color.pBg)
    }

    private func pathway(id: String, title: String, detail: String,
                         command: String, caveat: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Color.pAccent)
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(Color.pMuted)
            // 命令块保留等宽：用户要照抄，字形对齐才读得准。
            Text(command)
                .font(mono(10.5))
                .foregroundStyle(Color.pFg)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.pChipBg))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.pEdge, lineWidth: 1))
            Text(caveat)
                .font(.system(size: 10.5))
                .foregroundStyle(Color.pWarnFg)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.pCard))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.pSep, lineWidth: 1))
        .accessibilityIdentifier(id)
    }
}