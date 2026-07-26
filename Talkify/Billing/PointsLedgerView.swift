import SwiftUI
import Combine
import CoreKit
import DesignKit

extension Notification.Name {
    static let billingPointLedgerDidChange = Notification.Name("billingPointLedgerDidChange")
}

@MainActor
final class PointsLedgerViewModel: ObservableObject {
    enum Filter: String, CaseIterable, Identifiable {
        case all
        case grant
        case expire
        case freeze
        case consume
        case refund

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return "全部"
            case .expire: return "过期"
            case .grant: return "发放"
            case .freeze: return "冻结"
            case .consume: return "消耗"
            case .refund: return "退款"
            }
        }

        var queryValue: String? {
            self == .all ? nil : rawValue
        }
    }

    @Published var selectedFilter: Filter = .all
    @Published var items: [BillingPointLedger] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var total = 0

    private let billingService: BillingService
    private var cancellables = Set<AnyCancellable>()

    init(billingService: BillingService) {
        self.billingService = billingService

        NotificationCenter.default.publisher(for: .billingPointLedgerDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    await self.load()
                }
            }
            .store(in: &cancellables)
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let response = try await billingService.fetchPointLedgers(
                page: 1,
                pageSize: 50,
                changeType: selectedFilter.queryValue
            )
            items = response.items
            total = response.total
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func title(for item: BillingPointLedger) -> String {
        if let displayTitle = item.displayTitle, !displayTitle.isEmpty {
            return displayTitle
        }
        switch item.changeType {
        case "grant":
            return "点数发放"
        case "expire":
            return "点数过期"
        case "freeze":
            return "点数冻结"
        case "consume":
            return "点数消耗"
        case "refund":
            return "点数退款"
        default:
            return item.changeType
        }
    }

    func subtitle(for item: BillingPointLedger) -> String {
        if let displayDescription = item.displayDescription, !displayDescription.isEmpty {
            return displayDescription
        }
        if let remark = item.remark, !remark.isEmpty {
            return remark
        }

        switch item.bizType {
        case "subscription_grant":
            return "订阅账期发放"
        case "point_pack_grant":
            return "点数包到账"
        case "task_freeze":
            return "创建任务时冻结"
        case "task_consume":
            return "任务完成后核销"
        case "task_refund":
            return "任务失败后退款"
        default:
            return item.bizType
        }
    }

    func pointsText(for item: BillingPointLedger) -> String {
        if let displayPointsText = item.displayPointsText, !displayPointsText.isEmpty {
            return displayPointsText
        }
        let prefix = item.direction == "in" ? "+" : "-"
        return "\(prefix)\(item.points)"
    }

    func pointsColor(for item: BillingPointLedger) -> Color {
        switch item.displayCategory {
        case "income":
            return Color(hex: "2E9E5B")
        case "freeze", "consume", "refund", "adjust":
            return Color(hex: "D35454")
        default:
            return item.direction == "in" ? Color(hex: "2E9E5B") : Color(hex: "D35454")
        }
    }

    func createdAtText(for item: BillingPointLedger) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(item.createdAt))
        return DateFormatter.pointLedger.string(from: date)
    }
}

struct PointsLedgerView: View {
    @StateObject var viewModel: PointsLedgerViewModel

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            content
        }
        .background(Color.underPageBackground)
        .navigationTitle("点数明细")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .task {
            await viewModel.load()
        }
        .onChange(of: viewModel.selectedFilter) { _, _ in
            Task {
                await viewModel.load()
            }
        }
    }
}

private extension PointsLedgerView {
    var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(PointsLedgerViewModel.Filter.allCases) { filter in
                    Button {
                        viewModel.selectedFilter = filter
                    } label: {
                        Text(filter.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(viewModel.selectedFilter == filter ? .white : .primary)
                            .padding(.horizontal, 14)
                            .frame(height: 34)
                            .background(
                                Capsule()
                                    .fill(viewModel.selectedFilter == filter ? Color.accentColor : Color.controlBackground)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }

    @ViewBuilder
    var content: some View {
        if viewModel.isLoading && viewModel.items.isEmpty {
            ProgressView("加载点数账本...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = viewModel.errorMessage, viewModel.items.isEmpty {
            VStack(spacing: 10) {
                Text("点数账本加载失败")
                    .font(.system(size: 17, weight: .semibold))
                Text(errorMessage)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.items.isEmpty {
            VStack(spacing: 10) {
                Text("还没有点数记录")
                    .font(.system(size: 17, weight: .semibold))
                Text("后续购买、消耗、冻结和退款记录会显示在这里。")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                Section {
                    ForEach(viewModel.items) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(viewModel.title(for: item))
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(.primary)
                                    Text(viewModel.subtitle(for: item))
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Text(viewModel.pointsText(for: item))
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(viewModel.pointsColor(for: item))
                            }

                            HStack {
                                Text(viewModel.createdAtText(for: item))
                                Spacer()
                                Text("余额 \(item.balanceAfter)")
                                if item.frozenAfter > 0 {
                                    Text("冻结 \(item.frozenAfter)")
                                }
                            }
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 6)
                        .listRowBackground(Color.systemBackground)
                    }
                } header: {
                    Text("共 \(viewModel.total) 条记录")
                }
            }
#if os(macOS)
            .listStyle(.inset(alternatesRowBackgrounds: false))
#else
            .listStyle(.insetGrouped)
#endif
            .scrollContentBackground(.hidden)
            .background(Color.underPageBackground)
        }
    }
}

private extension DateFormatter {
    static let pointLedger: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}
