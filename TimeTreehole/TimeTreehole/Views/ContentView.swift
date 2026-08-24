import SwiftUI

// MARK: - 主容器（含灵叶商店弹窗）

struct ContentView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        ZStack {
            switch store.selectedTab {
            case .home:
                HomeView()
            case .treehole:
                TreeholeView()
            case .messages:
                NotificationsView()
            case .garden:
                GardenView()
            }
        }
        .preferredColorScheme(.dark)
        // 首次启动引导
        .fullScreenCover(isPresented: $store.showOnboarding) {
            OnboardingView()
                .environmentObject(store)
        }
        // 设备恢复
        .sheet(isPresented: $store.showRecovery) {
            RecoveryView()
                .environmentObject(store)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        // 灵叶商店
        .sheet(isPresented: $store.showStore) {
            StoreView()
                .environmentObject(store)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        // 个人资料 / 设置
        .sheet(isPresented: $store.showProfile) {
            ProfileView()
                .environmentObject(store)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        // 种子详情（含评论列表）
        .sheet(item: $store.seedDetailSeed, onDismiss: {
            store.stopPlayback()
            store.dismissSeedDetail()
        }) { seed in
            SeedDetailView(seed: seed)
                .environmentObject(store)
        }
    }
}
