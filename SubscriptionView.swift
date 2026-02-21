import SwiftUI
import StoreKit

// MARK: - Subscription Overview (For Settings)

struct SubscriptionOverviewView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var subscription = SubscriptionManager.shared
    @State private var showPaywall = false
    
    private var colors: AppColors {
        AppColors(colorScheme: colorScheme)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Current plan card
            currentPlanCard
            
            // Usage stats
            usageCard
            
            // Upgrade button (if not Pro)
            if subscription.currentTier.baseLevel != .pro {
                upgradeButton
            }
            
            // Manage subscription link
            Button {
                if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                    #if os(iOS)
                    UIApplication.shared.open(url)
                    #elseif os(macOS)
                    NSWorkspace.shared.open(url)
                    #endif
                }
            } label: {
                HStack {
                    Text(L10n.manageSubscription)
                        .font(AppFont.mono(size: 13, weight: .medium))
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12))
                }
                .foregroundStyle(colors.secondaryText)
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }
    
    private var currentPlanCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(subscription.currentTier.displayName.uppercased())
                        .font(AppFont.mono(size: 18, weight: .bold))
                        .foregroundStyle(colors.primaryText)
                    
                    Text(subscription.currentTier.tagline)
                        .font(AppFont.mono(size: 12, weight: .regular))
                        .foregroundStyle(colors.secondaryText)
                }
                
                Spacer()
                
                Text(subscription.currentTier.monthlyPrice)
                    .font(AppFont.mono(size: 16, weight: .bold))
                    .foregroundStyle(colors.primaryText)
            }
            
            // Feature highlights
            HStack(spacing: 16) {
                featurePill(icon: "clock", text: subscription.currentTier.transcriptionLimitLabel)
                featurePill(icon: "doc.text", text: subscription.currentTier.historyLimitLabel)
            }
        }
        .padding(16)
        .glassCard(radius: 12)
    }
    
    private func featurePill(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(text)
                .font(AppFont.mono(size: 10, weight: .medium))
        }
        .foregroundStyle(colors.secondaryText)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(colors.selection)
        .clipShape(Capsule())
    }
    
    private var usageCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if subscription.currentTier == .free {
                // Free tier - show upgrade prompt
                HStack {
                    Text(L10n.transcriptionSection)
                        .font(AppFont.mono(size: 10, weight: .medium))
                        .kerning(1.5)
                        .foregroundStyle(colors.secondaryText)
                    
                    Spacer()
                }
                
                HStack(spacing: 12) {
                    Image(systemName: "waveform")
                        .font(.system(size: 20))
                        .foregroundStyle(colors.mutedText)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.freeMinPerMonth("15"))
                            .font(AppFont.mono(size: 14, weight: .bold))
                            .foregroundStyle(colors.primaryText)
                        
                        Text(L10n.upgradeForAI())
                            .font(AppFont.mono(size: 11, weight: .regular))
                            .foregroundStyle(colors.secondaryText)
                            .lineSpacing(2)
                    }
                }
            } else {
                // Subscribed tier - show usage
                HStack {
                    Text(L10n.thisMonthUsage)
                        .font(AppFont.mono(size: 10, weight: .medium))
                        .kerning(1.5)
                        .foregroundStyle(colors.secondaryText)
                    
                    Spacer()
                    
                    Text(L10n.resets(in: subscription.daysUntilReset))
                        .font(AppFont.mono(size: 10, weight: .regular))
                        .foregroundStyle(colors.mutedText)
                }
                
                // Progress bar
                VStack(alignment: .leading, spacing: 8) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            // Background
                            RoundedRectangle(cornerRadius: 4)
                                .fill(colors.selection)
                                .frame(height: 8)
                            
                            // Progress
                            RoundedRectangle(cornerRadius: 4)
                                .fill(progressColor)
                                .frame(width: geo.size.width * subscription.usagePercentage, height: 8)
                        }
                    }
                    .frame(height: 8)
                    
                    HStack {
                        Text(formatUsedTime(subscription.usage.transcriptionSecondsUsed))
                            .font(AppFont.mono(size: 12, weight: .bold))
                            .foregroundStyle(colors.primaryText)
                        
                        Text(L10n.ofTotal("", formatUsedTime(subscription.currentTier.transcriptionLimitSeconds)))
                            .font(AppFont.mono(size: 12, weight: .regular))
                            .foregroundStyle(colors.secondaryText)
                        
                        Spacer()
                        
                        Text(subscription.remainingTranscriptionLabel)
                            .font(AppFont.mono(size: 11, weight: .medium))
                            .foregroundStyle(progressColor)
                    }
                }
            }
        }
        .padding(16)
        .glassCard(radius: 12)
    }
    
    private var progressColor: Color {
        let percentage = subscription.usagePercentage
        if percentage >= 0.9 {
            return .red
        } else if percentage >= 0.7 {
            return .orange
        } else {
            return colors.primaryText
        }
    }
    
    private func formatUsedTime(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
    
    private var upgradeButton: some View {
        Button {
            showPaywall = true
        } label: {
            HStack {
                Image(systemName: "sparkles")
                    .font(.system(size: 14))
                Text(L10n.upgradePlan)
                    .font(AppFont.mono(size: 12, weight: .bold))
                    .kerning(1.5)
            }
            .foregroundStyle(colors.background)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(colors.primaryText)
            .clipShape(Capsule())
        }
    }
}

// MARK: - Paywall View

struct PaywallView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var subscription = SubscriptionManager.shared
    @State private var selectedTier: SubscriptionTier = .standardMonthly
    @State private var isYearly = false
    @State private var isPurchasing = false
    @State private var errorMessage: String?
    
    private var colors: AppColors {
        AppColors(colorScheme: colorScheme)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Text(L10n.unlockSignal)
                            .font(AppFont.mono(size: 24, weight: .bold))
                            .kerning(3.0)
                            .foregroundStyle(colors.primaryText)
                        
                        Text(L10n.choosePlan)
                            .font(AppFont.mono(size: 14, weight: .regular))
                            .foregroundStyle(colors.secondaryText)
                    }
                    .padding(.top, 20)
                    
                    // Billing period toggle
                    VStack(spacing: 12) {
                        billingPeriodToggle
                        
                        if isYearly {
                            Text(L10n.saveWithAnnual)
                                .font(AppFont.mono(size: 11, weight: .medium))
                                .foregroundStyle(.green)
                        }
                    }
                    .padding(.horizontal)
                    
                    // Tier cards (only show Free, Standard, Pro - period is handled by toggle)
                    GlassEffectContainer(spacing: 12) {
                        VStack(spacing: 12) {
                            TierCard(
                                tier: .free,
                                isSelected: selectedTier == .free,
                                isCurrent: subscription.currentTier == .free,
                                onSelect: { selectedTier = .free }
                            )
                            
                            TierCard(
                                tier: isYearly ? .standardYearly : .standardMonthly,
                                isSelected: selectedTier.baseLevel == .standard,
                                isCurrent: subscription.currentTier.baseLevel == .standard,
                                onSelect: { 
                                    selectedTier = isYearly ? .standardYearly : .standardMonthly
                                }
                            )
                            
                            TierCard(
                                tier: isYearly ? .proYearly : .proMonthly,
                                isSelected: selectedTier.baseLevel == .pro,
                                isCurrent: subscription.currentTier.baseLevel == .pro,
                                onSelect: { 
                                    selectedTier = isYearly ? .proYearly : .proMonthly
                                }
                            )
                        }
                        .padding(.horizontal)
                    }
                    .onChange(of: isYearly) { _, newValue in
                        // Update selected tier when billing period changes
                        switch selectedTier.baseLevel {
                        case .standard:
                            selectedTier = newValue ? .standardYearly : .standardMonthly
                        case .pro:
                            selectedTier = newValue ? .proYearly : .proMonthly
                        case .free:
                            break
                        }
                    }
                    
                    // Privacy Pack (One-time purchase) - only show if not already purchased
                    if !subscription.usage.hasPrivacyPack {
                        privacyPackCard
                            .padding(.horizontal)
                    }
                    
                    // Selected tier features
                    selectedTierFeatures
                        .padding(.horizontal)
                    
                    // Error message
                    if let error = errorMessage {
                        Text(error)
                            .font(AppFont.mono(size: 12, weight: .medium))
                            .foregroundStyle(.red)
                            .padding(.horizontal)
                    }
                    
                    // Purchase button
                    if selectedTier != .free && selectedTier != subscription.currentTier {
                        purchaseButton
                            .padding(.horizontal)
                    }
                    
                    // Restore purchases
                    Button {
                        Task {
                            await subscription.restorePurchases()
                        }
                    } label: {
                        Text(L10n.restorePurchases)
                            .font(AppFont.mono(size: 12, weight: .medium))
                            .foregroundStyle(colors.secondaryText)
                    }
                    .padding(.bottom, 20)
                    
                    // Terms
                    termsText
                        .padding(.horizontal)
                        .padding(.bottom, 40)
                }
            }
            .background(colors.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.close) {
                        dismiss()
                    }
                    .font(AppFont.mono(size: 14, weight: .medium))
                    .foregroundStyle(colors.primaryText)
                }
            }
        }
    }
    
    private var selectedTierFeatures: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.whatsIncluded)
                .font(AppFont.mono(size: 10, weight: .medium))
                .kerning(1.5)
                .foregroundStyle(colors.secondaryText)
            
            VStack(alignment: .leading, spacing: 10) {
                ForEach(selectedTier.features) { feature in
                    HStack(spacing: 12) {
                        Image(systemName: feature.icon)
                            .font(.system(size: 14))
                            .foregroundStyle(colors.primaryText)
                            .frame(width: 24)
                        
                        Text(feature.text)
                            .font(AppFont.mono(size: 13, weight: .regular))
                            .foregroundStyle(colors.primaryText)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(radius: 12)
        }
    }
    
    private var purchaseButton: some View {
        Button {
            purchase()
        } label: {
            HStack {
                if isPurchasing {
                    ProgressView()
                        .tint(colors.background)
                        .scaleEffect(0.8)
                } else {
                    Text(L10n.subscribeTo(selectedTier.displayName.uppercased()))
                        .font(AppFont.mono(size: 13, weight: .bold))
                        .kerning(1.5)
                }
            }
            .foregroundStyle(colors.background)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(colors.primaryText)
            .clipShape(Capsule())
        }
        .disabled(isPurchasing)
    }
    
    private var termsText: some View {
        Text(L10n.appleTerms)
            .font(AppFont.mono(size: 9, weight: .regular))
            .foregroundStyle(colors.mutedText)
            .multilineTextAlignment(.center)
            .lineSpacing(3)
    }
    
    private var billingPeriodToggle: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 4) {
                Button {
                    withAnimation(.smooth(duration: 0.3)) {
                        isYearly = false
                    }
                } label: {
                    Text(L10n.monthly.uppercased())
                        .font(AppFont.mono(size: 11, weight: .bold))
                        .kerning(1.5)
                        .foregroundStyle(isYearly ? colors.mutedText : colors.primaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.glass)
                .opacity(isYearly ? 0.5 : 1.0)
                
                Button {
                    withAnimation(.smooth(duration: 0.3)) {
                        isYearly = true
                    }
                } label: {
                    Text(L10n.yearly.uppercased())
                        .font(AppFont.mono(size: 11, weight: .bold))
                        .kerning(1.5)
                        .foregroundStyle(isYearly ? colors.primaryText : colors.mutedText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.glass)
                .opacity(isYearly ? 1.0 : 0.5)
            }
        }
    }
    
    private var privacyPackCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.oneTimePurchaseSection)
                .font(AppFont.mono(size: 10, weight: .medium))
                .kerning(1.5)
                .foregroundStyle(colors.secondaryText)
            
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "lock.shield.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(.green)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.privacyPack)
                                    .font(AppFont.mono(size: 14, weight: .bold))
                                    .foregroundStyle(colors.primaryText)
                                
                                Text(L10n.transcribeOnPhone)
                                    .font(AppFont.mono(size: 11))
                                    .foregroundStyle(colors.secondaryText)
                            }
                        }
                        
                        // Features
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.green)
                                Text(L10n.twoHoursCloud)
                                    .font(AppFont.mono(size: 12))
                                    .foregroundStyle(colors.primaryText)
                            }
                            
                            // Only show on-device features if device supports it
                            if OnDeviceTranscriptionService.shared.isOnDeviceAvailable {
                                HStack(spacing: 8) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.green)
                                    Text(L10n.unlimitedOnDevice)
                                        .font(AppFont.mono(size: 12))
                                        .foregroundStyle(colors.primaryText)
                                }
                                
                                HStack(spacing: 8) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.green)
                                    Text(L10n.privateAISummaries)
                                        .font(AppFont.mono(size: 12))
                                        .foregroundStyle(colors.primaryText)
                                }
                            }
                        }
                        .padding(.leading, 4)
                    }
                    
                    Spacer()
                    
                    Text(L10n.pricePrivacyPack)
                        .font(AppFont.mono(size: 24, weight: .bold))
                        .foregroundStyle(colors.primaryText)
                }
                
                Button {
                    purchasePrivacyPack()
                } label: {
                    HStack {
                        if isPurchasing {
                            ProgressView()
                                .tint(colors.background)
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "cart.fill")
                                .font(.system(size: 12))
                            Text(L10n.buyPrivacyPack)
                                .font(AppFont.mono(size: 12, weight: .bold))
                                .kerning(1.5)
                        }
                    }
                    .foregroundStyle(colors.background)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.green)
                    .clipShape(Capsule())
                }
                .disabled(isPurchasing)
            }
            .padding(16)
            .glassCard(radius: 12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.green.opacity(0.3), lineWidth: 1)
            )
        }
    }
    
    private func purchase() {
        guard !isPurchasing else { return }
        isPurchasing = true
        errorMessage = nil
        
        Task {
            do {
                let success = try await subscription.purchase(selectedTier)
                if success {
                    dismiss()
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isPurchasing = false
        }
    }
    
    private func purchasePrivacyPack() {
        guard !isPurchasing else { return }
        isPurchasing = true
        errorMessage = nil
        
        Task {
            do {
                let success = try await subscription.purchaseCreditPack(.privacyPack)
                if success {
                    dismiss()
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isPurchasing = false
        }
    }
}

// MARK: - Tier Card

struct TierCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let tier: SubscriptionTier
    let isSelected: Bool
    let isCurrent: Bool
    let onSelect: () -> Void
    
    private var colors: AppColors {
        AppColors(colorScheme: colorScheme)
    }
    
    var body: some View {
        Button(action: {
            withAnimation(.smooth(duration: 0.3)) {
                onSelect()
            }
        }) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(tier.displayName.uppercased())
                            .font(AppFont.mono(size: 14, weight: .bold))
                            .foregroundStyle(colors.primaryText)
                        
                        if isCurrent {
                            Text(L10n.current)
                                .font(AppFont.mono(size: 8, weight: .bold))
                                .kerning(1.0)
                                .foregroundStyle(colors.background)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .glassEffect(.regular.tint(colors.primaryText), in: Capsule())
                        }
                        
                        if tier.baseLevel == .standard && !isCurrent {
                            Text(L10n.popular)
                                .font(AppFont.mono(size: 8, weight: .bold))
                                .kerning(1.0)
                                .foregroundStyle(colors.background)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .glassEffect(.regular.tint(colors.primaryText.opacity(0.8)), in: Capsule())
                        }
                    }
                    
                    Text(tier.tagline)
                        .font(AppFont.mono(size: 11, weight: .regular))
                        .foregroundStyle(colors.secondaryText)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    if tier.isYearly {
                        Text(tier.pricePerMonth)
                            .font(AppFont.mono(size: 16, weight: .bold))
                            .foregroundStyle(colors.primaryText)
                        
                        Text(tier.monthlyPrice)
                            .font(AppFont.mono(size: 9, weight: .medium))
                            .foregroundStyle(colors.secondaryText)
                        
                        Text(L10n.billedYearly)
                            .font(AppFont.mono(size: 8, weight: .regular))
                            .foregroundStyle(colors.mutedText)
                    } else {
                        Text(tier.monthlyPrice)
                            .font(AppFont.mono(size: 16, weight: .bold))
                            .foregroundStyle(colors.primaryText)
                        
                        Text(tier.transcriptionLimitLabel)
                            .font(AppFont.mono(size: 10, weight: .regular))
                            .foregroundStyle(colors.secondaryText)
                    }
                }
                
                // Selection indicator
                Circle()
                    .stroke(isSelected ? colors.primaryText : colors.mutedText, lineWidth: 2)
                    .background(Circle().fill(isSelected ? colors.primaryText : Color.clear))
                    .frame(width: 20, height: 20)
                    .overlay {
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(colors.background)
                        }
                    }
                    .padding(.leading, 12)
            }
            .padding(16)
        }
        .buttonStyle(.plain)
        .glassEffect(
            isSelected ? .regular.tint(colors.selection).interactive() : .regular.interactive(),
            in: RoundedRectangle(cornerRadius: 12)
        )
    }
}

// MARK: - Upgrade Prompt (Inline)

struct UpgradePromptView: View {
    @Environment(\.colorScheme) private var colorScheme
    let reason: UpgradeReason
    let onUpgrade: () -> Void
    
    private var colors: AppColors {
        AppColors(colorScheme: colorScheme)
    }
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: reason.icon)
                .font(.system(size: 32, weight: .thin))
                .foregroundStyle(colors.mutedText)
            
            VStack(spacing: 8) {
                Text(reason.title)
                    .font(AppFont.mono(size: 14, weight: .bold))
                    .foregroundStyle(colors.primaryText)
                
                Text(reason.message)
                    .font(AppFont.mono(size: 12, weight: .regular))
                    .foregroundStyle(colors.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            
            Button(action: onUpgrade) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12))
                    Text(L10n.upgradePlan)
                        .font(AppFont.mono(size: 11, weight: .bold))
                        .kerning(1.5)
                }
                .foregroundStyle(colors.background)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(colors.primaryText)
                .clipShape(Capsule())
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .glassCard(radius: 16)
    }
}

enum UpgradeReason {
    case transcriptionLocked
    case transcriptionLimit
    case historyLimit
    case featureLocked(String)
    
    var icon: String {
        switch self {
        case .transcriptionLocked: return "lock.fill"
        case .transcriptionLimit: return "clock.badge.exclamationmark"
        case .historyLimit: return "doc.badge.clock"
        case .featureLocked: return "lock"
        }
    }
    
    var title: String {
        switch self {
        case .transcriptionLocked: return L10n.transcriptionLocked
        case .transcriptionLimit: return L10n.transcriptionLocked
        case .historyLimit: return L10n.upgradeUnlimitedHistory
        case .featureLocked: return L10n.unlockSignal
        }
    }

    var message: String {
        switch self {
        case .transcriptionLocked:
            return L10n.upgradeToUnlockTranscription
        case .transcriptionLimit:
            return L10n.upgradeToTranscribe
        case .historyLimit:
            return L10n.upgradeUnlimitedHistory
        case .featureLocked:
            return L10n.upgradeForAI()
        }
    }
}

// MARK: - Usage Badge (For Dashboard)

struct UsageBadgeView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var subscription = SubscriptionManager.shared
    
    private var colors: AppColors {
        AppColors(colorScheme: colorScheme)
    }
    
    var body: some View {
        HStack(spacing: 8) {
            if subscription.currentTier == .free {
                // Free tier - show lock icon
                Image(systemName: "lock.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(colors.mutedText)
                    .frame(width: 24, height: 24)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(L10n.free.uppercased())
                        .font(AppFont.mono(size: 9, weight: .bold))
                        .kerning(1.0)
                        .foregroundStyle(colors.primaryText)
                    
                    Text(L10n.upgradeToTranscribe)
                        .font(AppFont.mono(size: 8, weight: .regular))
                        .foregroundStyle(colors.secondaryText)
                }
            } else {
                // Subscribed tier - show progress ring
                ZStack {
                    Circle()
                        .stroke(colors.selection, lineWidth: 3)
                    
                    Circle()
                        .trim(from: 0, to: subscription.usagePercentage)
                        .stroke(progressColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 24, height: 24)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(subscription.currentTier.displayName.uppercased())
                        .font(AppFont.mono(size: 9, weight: .bold))
                        .kerning(1.0)
                        .foregroundStyle(colors.primaryText)
                    
                    Text(subscription.remainingTranscriptionLabel)
                        .font(AppFont.mono(size: 8, weight: .regular))
                        .foregroundStyle(colors.secondaryText)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassCard(radius: 100)
    }
    
    private var progressColor: Color {
        let percentage = subscription.usagePercentage
        if percentage >= 0.9 { return .red }
        if percentage >= 0.7 { return .orange }
        return colors.primaryText
    }
}

#Preview("Paywall") {
    PaywallView()
}

#Preview("Overview") {
    SubscriptionOverviewView()
        .padding()
}
