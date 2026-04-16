import Observation
import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: AppStore

    var body: some View {
        NavigationStack {
            Form {
                Section("仓库状态") {
                    LabeledContent("当前仓库", value: store.repositoryStatusTitle)
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
            .sheet(item: $store.sharingControllerItem) { item in
                CloudSharingControllerContainer(controller: item.controller)
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
