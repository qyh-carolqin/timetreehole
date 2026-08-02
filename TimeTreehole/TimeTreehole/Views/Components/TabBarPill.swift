import SwiftUI

// MARK: - 魔法森林胶囊 Tab 栏

struct TabBarPill: View {
    @Binding var selectedTab: Tab
    let unreadCount: Int

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    TabButton(
                        tab: tab,
                        isSelected: selectedTab == tab,
                        badgeCount: tab == .messages ? unreadCount : nil
                    ) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                            selectedTab = tab
                        }
                    }
                }
            }
            .padding(4)
            .background(TreeholeColors.bgSurface)
            .clipShape(RoundedRectangle(cornerRadius: 36))
            .overlay(
                RoundedRectangle(cornerRadius: 36)
                    .stroke(TreeholeColors.borderSubtle, lineWidth: 1)
            )
        }
        .padding(.horizontal, 21)
        .padding(.top, 12)
        .padding(.bottom, 21)
    }
}

// MARK: - 单个 Tab 按钮

private struct TabButton: View {
    let tab: Tab
    let isSelected: Bool
    var badgeCount: Int?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    if isSelected {
                        Image(systemName: tab.iconName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(TreeholeColors.bgPrimary)
                    } else {
                        Image(systemName: tab.iconName)
                            .font(.system(size: 15))
                            .foregroundColor(TreeholeColors.textSecondary)
                    }
                }

                // 小红点
                ZStack {
                    if let count = badgeCount, count > 0, !isSelected {
                        Text("\(count)")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 14, height: 14)
                            .background(TreeholeColors.danger)
                            .clipShape(Circle())
                    } else {
                        Text(tab.rawValue)
                            .font(.system(size: 10, weight: isSelected ? .bold : .semibold))
                            .foregroundColor(isSelected ? TreeholeColors.bgPrimary : TreeholeColors.textSecondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                isSelected
                    ? TreeholeColors.accentPrimary
                    : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: 26))
        }
    }
}
