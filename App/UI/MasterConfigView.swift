import SwiftUI

struct MasterConfigView: View {
    @ObservedObject var store: AppStore

    var body: some View {
        Form {
            if let cold = store.remoteConfigCold {
                Section {
                    if let pump = cold.pump {
                        valueRow("remote.master_pump", value: pump)
                    }
                    if let version = cold.version {
                        valueRow("remote.master_version", value: version)
                    }
                    if let autosens = store.remoteConfigHot?.usedAutosensOnMainPhone {
                        booleanRow("remote.autosens", value: autosens)
                    }
                }

                let plugins = cold.syncedPrefsSnapshot
                Section {
                    if let aps = plugins.activePluginAps {
                        valueRow("remote.active_aps", value: aps)
                    }
                    if let sensitivity = plugins.activePluginSensitivity {
                        valueRow("remote.active_sensitivity", value: sensitivity)
                    }
                    if let smoothing = plugins.activePluginSmoothing {
                        valueRow("remote.active_smoothing", value: smoothing)
                    }
                }

                if let scene = store.remoteConfigHot?.activeScene {
                    Section {
                        if let name = store.activeRemoteSceneDisplayName {
                            valueRow("remote.active_scene", value: name)
                        }
                        if let sceneId = scene.sceneId {
                            valueRow("remote.active_scene_id", value: sceneId)
                        }
                        if let lifecycle = scene.lifecycle {
                            valueRow("remote.scene_lifecycle", value: lifecycle)
                        }
                    }
                }

                if let capabilities = store.remoteCapabilities {
                    Section {
                        booleanRow("remote.capability.profile", value: capabilities.canRemoteProfileSwitch)
                        booleanRow("remote.capability.loop", value: capabilities.canRemoteRunningMode)
                        booleanRow("remote.capability.target", value: capabilities.canRemoteTempTarget)
                        booleanRow("remote.capability.carbs", value: capabilities.canRemoteCarbs)
                        booleanRow("remote.capability.events", value: capabilities.canRemoteTherapyEvents)
                        booleanRow("remote.capability.client_control", value: capabilities.clientControlEnabled)
                        booleanRow("remote.capability.websocket", value: capabilities.usesWebSockets)
                    }
                }

                if !cold.authorizedClientIds.isEmpty {
                    Section {
                        ForEach(cold.authorizedClientIds, id: \.self) { clientId in
                            Text(clientId)
                        }
                    } header: {
                        Text(String(localized: "remote.authorized_clients"))
                    }
                }

                if !store.remoteQuickWizardEntries.isEmpty {
                    Section {
                        ForEach(store.remoteQuickWizardEntries) { entry in
                            VStack(alignment: .leading) {
                                Text(entry.name)
                                Text(entry.note ?? String(localized: "remote.quickwizard_no_details"))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    } header: {
                        Text(String(localized: "remote.quickwizard"))
                    }
                }

                Section {
                    EmptyView()
                } footer: {
                    Text(String(localized: "remote.master_footer"))
                }
            } else {
                Text(String(localized: "remote.config_unavailable"))
                if let error = store.remoteConfigError {
                    Text(error)
                }
            }
        }
        .navigationTitle(String(localized: "remote.master_title"))
    }

    private func valueRow(_ label: LocalizedStringKey, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func booleanRow(_ label: LocalizedStringKey, value: Bool) -> some View {
        valueRow(label, value: String(localized: value ? "remote.enabled" : "remote.disabled"))
    }
}
