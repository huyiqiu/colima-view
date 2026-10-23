import SwiftUI
import ColimaCore

struct BuildImageView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @State private var context: URL?
    @State private var dockerfile: URL?
    @State private var tag = ""
    @State private var buildArgs = ""
    @State private var noCache = false
    @State private var pull = false
    @State private var platform = ""
    private var effectiveFile: URL? { dockerfile ?? context?.appendingPathComponent("Dockerfile") }
    private var arguments: [String] { buildArgs.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
    private var valid: Bool {
        guard context != nil, let file = effectiveFile, FileManager.default.fileExists(atPath: file.path) else { return false }
        return InputValidation.imageReference(tag) && arguments.allSatisfy(InputValidation.environment)
    }
    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: L("构建镜像"), subtitle: L("从本机文件夹中的 Dockerfile 构建，无需打开终端。"))
            Form {
                Section(L("构建来源")) {
                    LabeledContent(L("上下文文件夹")) { HStack { Text(context?.path ?? L("尚未选择")).font(.caption).lineLimit(1).truncationMode(.middle); Button(L("选择…")) { if let url = chooseFile(directories: true) { context = url; dockerfile = nil } } } }
                    LabeledContent("Dockerfile") { HStack { Text(effectiveFile?.lastPathComponent ?? "Dockerfile").font(.caption); Button(L("选择…")) { dockerfile = chooseFile() } } }
                    TextField(L("镜像标签"), text: $tag, prompt: Text("my-app:latest"))
                }
                Section(L("构建选项")) {
                    Picker(L("平台"), selection: $platform) { Text(L("自动选择")).tag(""); Text("Linux / ARM64").tag("linux/arm64"); Text("Linux / AMD64").tag("linux/amd64") }
                    Toggle(L("跳过构建缓存"), isOn: $noCache)
                    Toggle(L("检查基础镜像更新"), isOn: $pull)
                    TextField(L("构建参数：KEY=value，每行一个"), text: $buildArgs, axis: .vertical).lineLimit(2...5)
                    Text(L("会遵循文件夹中的 .dockerignore。构建进度可在活动记录中查看。")).font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped)
            Divider()
            HStack { Button(L("取消")) { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button(L("开始构建"), systemImage: "hammer") { build() }.buttonStyle(.deskPrimary).keyboardShortcut(.defaultAction).disabled(!valid || store.isBusy) }.padding(20)
        }.frame(width: 620, height: 560)
    }
    private func build() {
        guard let context, let file = effectiveFile else { return }
        var args = ["build", "--tag", tag, "--file", file.path, "--progress", "plain"]
        if noCache { args.append("--no-cache") }
        if pull { args.append("--pull") }
        if !platform.isEmpty { args += ["--platform", platform] }
        args += arguments.flatMap { ["--build-arg", $0] }
        args += ["--", context.path]
        dismiss(); store.dockerAction(L("构建 \(tag)"), args: args, timeout: 3600)
    }
}
