//
//  SubscriptionPlanComparisonView.swift
//  Dreamlog
//
//  Created by xiaoyuan on 2026/4/16.
//


import SwiftUI
import CoreKit
import DesignKit

struct SubscriptionPlanComparisonView: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let products: [BillingProduct]
    let rows: [PlanComparisonRow]
    let priceTextProvider: (BillingProduct) -> String

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                headerCard

                comparisonTable
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
        }
        .background(Color.underPageBackground)
        .navigationTitle("Talkify Pro")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }

    var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
//            Text(title)
//                .font(.system(size: 24, weight: .bold))

            Text("对比不同订阅档位的权益差异，选择最适合你的 Pro 方案。")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        .padding(20)
        .subscriptionSurface()
    }

    var comparisonTable: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    comparisonCell("权益", width: 150, emphasized: true)

                    ForEach(products) { product in
                        VStack(spacing: 4) {
                            comparisonCell(product.displayName, width: 140, emphasized: true)
                            Text(priceTextProvider(product))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        .frame(width: 140, height: 68)
                        .background(Color.systemBackground)
                    }
                }

                ForEach(rows) { row in
                    HStack(spacing: 0) {
                        comparisonCell(row.featureTitle, width: 150, emphasized: false)

                        ForEach(Array(row.values.enumerated()), id: \.offset) { _, value in
                            comparisonCell(value, width: 140, emphasized: false)
                        }
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.systemBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
        }
    }

    func comparisonCell(_ text: String, width: CGFloat, emphasized: Bool) -> some View {
        Text(text)
            .font(.system(size: emphasized ? 15 : 13, weight: emphasized ? .bold : .medium))
            .foregroundColor(.primary)
            .multilineTextAlignment(.center)
            .frame(width: width)
            .frame(minHeight: 56)
            .padding(.horizontal, 8)
            .overlay(alignment: .bottom) {
                Divider()
            }
            .overlay(alignment: .trailing) {
                Divider()
            }
    }
}

extension View {
    func subscriptionSurface() -> some View {
        background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.systemBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.black.opacity(0.04), lineWidth: 1)
        )
    }
}
