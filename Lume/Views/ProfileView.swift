import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var auth: AuthViewModel
    @ObservedObject private var stats = PlaybackStatsStore.shared
    @State private var displayMonth = Date()
    @State private var displayYear = Date()
    @State private var yearPageEnd = Calendar.current.component(.year, from: Date())
    @State private var range: PlaybackStatsRange = .day

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(hex: "0f1216"), Color(hex: "0b0d10")],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    totalStatsCard
                    statsRangeCard
                    signOutButton
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("个人页")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 54, height: 54)
                .overlay(
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.8))
                )

            VStack(alignment: .leading, spacing: 6) {
                Text(auth.user?.displayName ?? "User")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)

                if let email = auth.user?.email, !email.isEmpty {
                    Text(email)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.6))
                } else {
                    Text("本地账户")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.6))
                }
            }

            Spacer()
        }
    }

    private var totalStatsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("播放总时长")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.6))

            Text(durationText(stats.totalSeconds))
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .background(cardBackground)
    }

    private var statsRangeCard: some View {
        let selectedYear = Calendar.current.component(.year, from: displayYear)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("播放统计")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.6))

                Spacer()
            }

            PlaybackStatsRangePicker(range: $range)

            Group {
                switch range {
                case .day:
                    PlaybackCalendarView(month: $displayMonth, dailySeconds: stats.dailySeconds)
                case .month:
                    PlaybackMonthGridView(year: $displayYear, monthlySeconds: stats.monthlyTotals(for: selectedYear))
                case .year:
                    PlaybackYearGridView(
                        pageEndYear: $yearPageEnd,
                        yearlySeconds: stats.yearlyTotals()
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .background(cardBackground)
    }

    private var signOutButton: some View {
        Button {
            auth.signOut()
        } label: {
            Text("退出登录")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.red.opacity(0.8))
                .clipShape(Capsule())
        }
        .padding(.top, 8)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color.white.opacity(0.04))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }

    private func durationText(_ seconds: Int) -> String {
        guard seconds > 0 else { return "0 分钟" }
        let minutes = seconds / 60
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if hours > 0 {
            if remainingMinutes > 0 {
                return "\(hours) 小时 \(remainingMinutes) 分"
            }
            return "\(hours) 小时"
        }
        return "\(minutes) 分"
    }
}

#Preview {
    ProfileView()
        .environmentObject(AuthViewModel())
}
