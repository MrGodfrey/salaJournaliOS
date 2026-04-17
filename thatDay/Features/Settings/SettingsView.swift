import Observation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: AppStore

    @State private var isShowingFileImporter = false
    @State private var isShowingClearRepositoryConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Section("仓库状态") {
                    LabeledContent("当前仓库", value: store.currentRepositoryName)
                    LabeledContent("当前权限", value: store.repositoryStatusTitle)
                    Text(store.repositorySummary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if store.canEditRepository {
                    Section("CloudKit 共享") {
                        Picker("邀请权限", selection: $store.shareAccessOption) {
                            ForEach(ShareAccessOption.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text(store.shareAccessOption.description)
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        Button {
                            Task {
                                await store.presentSharingController()
                            }
                        } label: {
                            Label("生成邀请链接", systemImage: "person.badge.plus")
                        }
                        .accessibilityIdentifier("presentShareControllerButton")
                    }
                }

                Section("打开共享仓库") {
                    TextField("https://www.icloud.com/share/...", text: $store.incomingShareLink, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .accessibilityIdentifier("shareLinkTextField")

                    Button {
                        Task {
                            await store.acceptIncomingShareLink()
                        }
                    } label: {
                        Label("打开共享仓库", systemImage: "link")
                    }
                    .accessibilityIdentifier("acceptShareLinkButton")
                }

                Section("通知") {
                    Toggle("共享仓库更新提醒", isOn: Binding(
                        get: { store.isSharedUpdateNotificationEnabled },
                        set: { isEnabled in
                            Task {
                                await store.updateSharedUpdateNotificationEnabled(isEnabled)
                            }
                        }
                    ))

                    Text("当你参与的共享仓库有文章新增或修改时，会发送可点击的系统通知。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("安全") {
                    Toggle("生物识别解锁", isOn: Binding(
                        get: { store.isBiometricLockEnabled },
                        set: { isEnabled in
                            Task {
                                await store.updateBiometricLockEnabled(isEnabled)
                            }
                        }
                    ))

                    Text("开启后，每次打开应用或回到前台都需要先验证。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("导入导出") {
                    Button {
                        Task {
                            await store.exportCurrentRepository()
                        }
                    } label: {
                        Label("导出当前仓库 ZIP", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        isShowingFileImporter = true
                    } label: {
                        Label("导入 ZIP 到当前仓库", systemImage: "square.and.arrow.down")
                    }

                    Text("导入会覆盖当前仓库内容；导出会生成一个 ZIP 文件，可在后台继续处理。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if let transferProgress = store.transferProgress {
                        VStack(alignment: .leading, spacing: 8) {
                            ProgressView(value: transferProgress.fractionCompleted)
                            Text(transferProgress.statusText)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("高级管理") {
                    Picker(
                        "当前使用仓库",
                        selection: Binding(
                            get: { store.currentRepositoryID },
                            set: { repositoryID in
                                Task {
                                    await store.switchRepository(to: repositoryID)
                                }
                            }
                        )
                    ) {
                        ForEach(store.sortedRepositories) { repository in
                            Text(repository.displayName).tag(repository.id)
                        }
                    }

                    Picker(
                        "启动时默认打开",
                        selection: Binding(
                            get: { store.defaultRepositoryID },
                            set: { repositoryID in
                                store.setDefaultRepository(repositoryID)
                            }
                        )
                    ) {
                        ForEach(store.sortedRepositories) { repository in
                            Text(repository.displayName).tag(repository.id)
                        }
                    }

                    Button("清空当前仓库内容", role: .destructive) {
                        isShowingClearRepositoryConfirmation = true
                    }
                    .disabled(!store.canEditRepository)
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
            .alert(
                "清空当前仓库？",
                isPresented: $isShowingClearRepositoryConfirmation
            ) {
                Button("清空", role: .destructive) {
                    Task {
                        await store.clearCurrentRepository()
                    }
                }

                Button("取消", role: .cancel) {}
            } message: {
                Text("当前仓库里的所有文章和图片都会被删除，这个操作无法撤销。")
            }
            .fileImporter(
                isPresented: $isShowingFileImporter,
                allowedContentTypes: [.zip],
                allowsMultipleSelection: false
            ) { result in
                guard case .success(let urls) = result,
                      let url = urls.first else {
                    return
                }

                Task {
                    await store.importRepositoryArchive(from: url)
                }
            }
            .sheet(item: $store.sharingControllerItem) { item in
                CloudSharingControllerContainer(controller: item.controller)
            }
            .sheet(item: $store.exportedArchiveItem) { item in
                ActivityViewController(activityItems: [item.url])
            }
        }
    }
}

private struct CloudSharingControllerContainer: UIViewControllerRepresentable {
    let controller: UICloudSharingController

    func makeUIViewController(context: Context) -> UICloudSharingController {
        controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}
}

private struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
