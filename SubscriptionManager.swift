import Foundation
import StoreKit
import SwiftUI

// MARK: - Subscription Tiers

enum SubscriptionTier: String, Codable, CaseIterable {
    case free = "free"
    case standardMonthly = "standard_monthly"
    case standardYearly = "standard_yearly"
    case proMonthly = "pro_monthly"
    case proYearly = "pro_yearly"
    
    var displayName: String {
        switch self {
        case .free: return L10n.tierFree
        case .standardMonthly, .standardYearly: return L10n.tierStandard
        case .proMonthly, .proYearly: return L10n.tierPro
        }
    }

    var tagline: String {
        switch self {
        case .free: return L10n.taglineFree
        case .standardMonthly, .standardYearly: return L10n.taglineStandard
        case .proMonthly, .proYearly: return L10n.taglinePro
        }
    }

    var monthlyPrice: String {
        switch self {
        case .free: return L10n.priceFree
        case .standardMonthly: return L10n.priceStandardMonthly + L10n.perMonth
        case .standardYearly: return L10n.priceStandardYearly + L10n.perYear
        case .proMonthly: return L10n.priceProMonthly + L10n.perMonth
        case .proYearly: return L10n.priceProYearly + L10n.perYear
        }
    }

    var pricePerMonth: String {
        switch self {
        case .free: return L10n.priceFree
        case .standardMonthly: return L10n.priceStandardMonthly + L10n.perMonth
        case .standardYearly: return L10n.priceStandardPerMonthYearly + L10n.perMonth
        case .proMonthly: return L10n.priceProMonthly + L10n.perMonth
        case .proYearly: return L10n.priceProPerMonthYearly + L10n.perMonth
        }
    }

    var billingPeriod: String {
        switch self {
        case .free: return ""
        case .standardMonthly, .proMonthly: return L10n.monthly
        case .standardYearly, .proYearly: return L10n.yearly
        }
    }
    
    var isYearly: Bool {
        switch self {
        case .standardYearly, .proYearly: return true
        default: return false
        }
    }
    
    var baseLevel: TierLevel {
        switch self {
        case .free: return .free
        case .standardMonthly, .standardYearly: return .standard
        case .proMonthly, .proYearly: return .pro
        }
    }
    
    enum TierLevel {
        case free, standard, pro
    }
    
    /// Monthly transcription limit in seconds
    var transcriptionLimitSeconds: TimeInterval {
        switch baseLevel {
        case .free: return 15 * 60       // 15 minutes
        case .standard: return 12 * 3600 // 12 hours
        case .pro: return 36 * 3600      // 36 hours
        }
    }
    
    /// Human-readable transcription limit
    var transcriptionLimitLabel: String {
        switch baseLevel {
        case .free: return L10n.transcriptionLimit15m
        case .standard: return L10n.transcriptionLimit12h
        case .pro: return L10n.transcriptionLimit36h
        }
    }
    
    /// Maximum upload duration in seconds (for audio file imports)
    var maxUploadDurationSeconds: TimeInterval {
        switch baseLevel {
        case .free: return 0              // Cannot upload/transcribe
        case .standard: return 2 * 3600   // 2 hours max
        case .pro: return .infinity       // Unlimited
        }
    }
    
    var maxUploadDurationLabel: String {
        switch baseLevel {
        case .free: return L10n.uploadLocked
        case .standard: return L10n.upload2hMax
        case .pro: return L10n.uploadUnlimited
        }
    }
    
    /// Maximum number of stored transcripts (nil = unlimited)
    var historyLimit: Int? {
        switch baseLevel {
        case .free: return nil  // Unlimited recordings, just can't transcribe
        case .standard: return nil
        case .pro: return nil
        }
    }
    
    var historyLimitLabel: String {
        return L10n.unlimitedRecordings
    }
    
    /// Summarization quality description
    var summarizationQuality: String {
        switch baseLevel {
        case .free: return "Transcription only (no AI analysis)"
        case .standard: return "Deep Dive (takeaways, actions, sentiment)"
        case .pro: return "Deep Dive + Priority Processing"
        }
    }
    
    /// Features list for the tier
    var features: [SubscriptionFeature] {
        switch baseLevel {
        case .free:
            return [
                SubscriptionFeature(icon: "mic.fill", text: L10n.featureUnlimitedRecordings),
                SubscriptionFeature(icon: "waveform", text: L10n.feature44khz),
                SubscriptionFeature(icon: "clock.fill", text: L10n.feature15minTranscription),
                SubscriptionFeature(icon: "infinity", text: L10n.featureUnlimitedStorage),
                SubscriptionFeature(icon: "lock.fill", text: L10n.featureNoAI)
            ]
        case .standard:
            return [
                SubscriptionFeature(icon: "clock.fill", text: L10n.feature12hTranscription),
                SubscriptionFeature(icon: "cpu", text: L10n.featureOnDeviceSpeech),
                SubscriptionFeature(icon: "brain", text: L10n.featureOnDeviceSummaries),
                SubscriptionFeature(icon: "person.2.fill", text: L10n.featureSpeakerID),
                SubscriptionFeature(icon: "arrow.up.doc", text: L10n.featureUpload2h),
                SubscriptionFeature(icon: "doc.richtext", text: L10n.featureExportPDF)
            ]
        case .pro:
            return [
                SubscriptionFeature(icon: "clock.badge.checkmark", text: L10n.feature36hTranscription),
                SubscriptionFeature(icon: "bolt.fill", text: L10n.featurePriority),
                SubscriptionFeature(icon: "arrow.up.doc", text: L10n.featureUnlimitedUpload),
                SubscriptionFeature(icon: "magnifyingglass", text: L10n.featureAudioSearch),
                SubscriptionFeature(icon: "checkmark.seal.fill", text: L10n.featureEverythingStandard)
            ]
        }
    }
    
    /// StoreKit product ID
    var productId: String? {
        switch self {
        case .free: return nil
        case .standardMonthly: return "com.proceduralabs.signal.standard.monthly"
        case .standardYearly: return "com.proceduralabs.signal.standard.yearly"
        case .proMonthly: return "com.proceduralabs.signal.pro.monthly"
        case .proYearly: return "com.proceduralabs.signal.pro.yearly"
        }
    }
}

struct SubscriptionFeature: Identifiable {
    let id = UUID()
    let icon: String
    let text: String
}

// MARK: - Credit Packs

enum CreditPack: String, CaseIterable {
    case privacyPack = "privacy_pack"  // $3 - 2 hours + on-device features
    
    var displayName: String {
        switch self {
        case .privacyPack: return L10n.privacyPack
        }
    }

    var tagline: String {
        switch self {
        case .privacyPack: return L10n.transcribeOnPhone
        }
    }
    
    var creditSeconds: TimeInterval {
        switch self {
        case .privacyPack: return 2 * 3600 // 2 hours
        }
    }
    
    var price: String {
        switch self {
        case .privacyPack: return "$3"
        }
    }
    
    var productId: String {
        "com.proceduralabs.signal.privacy.pack"
    }
    
    /// Whether this pack grants on-device features
    var grantsOnDeviceFeatures: Bool {
        switch self {
        case .privacyPack: return true
        }
    }
}

// MARK: - Usage Tracking

struct UsageData: Codable {
    var transcriptionSecondsUsed: TimeInterval
    var periodStartDate: Date
    var transcriptCount: Int
    var creditSeconds: TimeInterval // One-time purchased credits
    var hasPrivacyPack: Bool // Whether user has purchased the privacy pack (grants on-device features)
    
    static var empty: UsageData {
        UsageData(transcriptionSecondsUsed: 0, periodStartDate: Date(), transcriptCount: 0, creditSeconds: 0, hasPrivacyPack: false)
    }
    
    /// Check if the period has reset (new month)
    var needsReset: Bool {
        let calendar = Calendar.current
        let now = Date()
        return !calendar.isDate(periodStartDate, equalTo: now, toGranularity: .month)
    }
}

// MARK: - Subscription Manager

@Observable
final class SubscriptionManager {
    static let shared = SubscriptionManager()
    
    // Current subscription state
    private(set) var currentTier: SubscriptionTier = .free
    private(set) var usage: UsageData = .empty
    private(set) var isLoading = false
    
    // StoreKit
    private var products: [Product] = []
    private var purchasedProductIDs: Set<String> = []
    private var updates: Task<Void, Never>? = nil
    
    private let userDefaults = UserDefaults.standard
    private let usageKey = "subscription_usage"
    private let tierKey = "subscription_tier"
    
    private init() {
        loadLocalData()
        checkAndResetPeriod()
        
        // Start listening for transaction updates
        updates = observeTransactionUpdates()
        
        // Load products and check entitlements
        Task {
            await loadProducts()
            await updatePurchasedProducts()
        }
    }
    
    deinit {
        updates?.cancel()
    }
    
    // MARK: - Usage Tracking
    
    /// Whether user has an active paid subscription (Standard or Pro)
    var isSubscribed: Bool {
        currentTier.baseLevel != .free
    }
    
    /// Whether user can transcribe (always true - free tier has 15min, paid has more)
    var canTranscribeAtAll: Bool {
        true  // Everyone can transcribe now (free tier has 15 min/month)
    }
    
    /// Whether user has access to on-device features (privacy pack or Standard+)
    var hasOnDeviceAccess: Bool {
        usage.hasPrivacyPack || currentTier.baseLevel == .standard || currentTier.baseLevel == .pro
    }
    
    /// Check if user can upload/import audio of given duration
    func canUpload(duration: TimeInterval) -> Bool {
        guard isSubscribed else { return false }
        return duration <= currentTier.maxUploadDurationSeconds
    }
    
    /// Remaining transcription time in seconds (including credits)
    var remainingTranscriptionSeconds: TimeInterval {
        let subscriptionRemaining = max(0, currentTier.transcriptionLimitSeconds - usage.transcriptionSecondsUsed)
        return subscriptionRemaining + usage.creditSeconds
    }
    
    /// Remaining credit seconds (one-time purchases only)
    var remainingCreditSeconds: TimeInterval {
        usage.creditSeconds
    }
    
    /// Remaining transcription time as formatted string
    var remainingTranscriptionLabel: String {
        let remaining = remainingTranscriptionSeconds
        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        
        let timeString: String
        if hours > 0 {
            timeString = "\(hours)h \(minutes)m"
        } else {
            timeString = "\(minutes)m"
        }
        
        // Add credit indicator if user has credits
        if usage.creditSeconds > 0 {
            let creditHours = Int(usage.creditSeconds) / 3600
            let creditMinutes = (Int(usage.creditSeconds) % 3600) / 60
            let creditString = creditHours > 0 ? "\(creditHours)h \(creditMinutes)m" : "\(creditMinutes)m"
            return "\(timeString) (+\(creditString))"
        }

        return "\(timeString)"
    }
    
    /// Usage percentage (0.0 - 1.0)
    var usagePercentage: Double {
        let limit = currentTier.transcriptionLimitSeconds
        guard limit > 0 else { return 0 }
        return min(1.0, usage.transcriptionSecondsUsed / limit)
    }
    
    /// Check if user can transcribe a recording of given duration
    func canTranscribe(duration: TimeInterval) -> Bool {
        return remainingTranscriptionSeconds >= duration
    }
    
    /// Record transcription usage (uses credits first, then subscription time)
    func recordTranscriptionUsage(seconds: TimeInterval) {
        checkAndResetPeriod()
        
        // Use credits first
        if usage.creditSeconds > 0 {
            let creditsToUse = min(seconds, usage.creditSeconds)
            usage.creditSeconds -= creditsToUse
            let remainingSeconds = seconds - creditsToUse
            
            // If there's still time left after using credits, use subscription time
            if remainingSeconds > 0 {
                usage.transcriptionSecondsUsed += remainingSeconds
            }
        } else {
            // No credits, use subscription time
            usage.transcriptionSecondsUsed += seconds
        }
        
        usage.transcriptCount += 1
        saveLocalData()
    }
    
    /// Check if history limit is exceeded
    func isHistoryLimitExceeded(currentCount: Int) -> Bool {
        guard let limit = currentTier.historyLimit else { return false }
        return currentCount > limit
    }
    
    /// Number of transcripts that should be visible
    func visibleTranscriptCount(from totalCount: Int) -> Int {
        guard let limit = currentTier.historyLimit else { return totalCount }
        return min(limit, totalCount)
    }
    
    // MARK: - Period Management
    
    private func checkAndResetPeriod() {
        if usage.needsReset {
            usage = UsageData(
                transcriptionSecondsUsed: 0,
                periodStartDate: Date(),
                transcriptCount: usage.transcriptCount,
                creditSeconds: usage.creditSeconds, // Preserve credits across resets
                hasPrivacyPack: usage.hasPrivacyPack // Preserve privacy pack access
            )
            saveLocalData()
        }
    }
    
    /// Days until period resets
    var daysUntilReset: Int {
        let calendar = Calendar.current
        guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: calendar.startOfDay(for: usage.periodStartDate)),
              let startOfNextMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: nextMonth)) else {
            return 0
        }
        return calendar.dateComponents([.day], from: Date(), to: startOfNextMonth).day ?? 0
    }
    
    // MARK: - StoreKit
    
    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }
        
        var productIds = SubscriptionTier.allCases.compactMap { $0.productId }
        productIds.append(contentsOf: CreditPack.allCases.map { $0.productId })
        
        do {
            products = try await Product.products(for: productIds)
        } catch {
            print("Failed to load products: \(error)")
        }
    }
    
    func product(for tier: SubscriptionTier) -> Product? {
        guard let productId = tier.productId else { return nil }
        return products.first { $0.id == productId }
    }
    
    func product(for pack: CreditPack) -> Product? {
        return products.first { $0.id == pack.productId }
    }
    
    func purchase(_ tier: SubscriptionTier) async throws -> Bool {
        guard let product = product(for: tier) else {
            throw SubscriptionError.productNotFound
        }
        
        let result = try await product.purchase()
        
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await transaction.finish()
            await updatePurchasedProducts()
            return true
            
        case .userCancelled:
            return false
            
        case .pending:
            return false
            
        @unknown default:
            return false
        }
    }
    
    func purchaseCreditPack(_ pack: CreditPack) async throws -> Bool {
        guard let product = product(for: pack) else {
            throw SubscriptionError.productNotFound
        }
        
        let result = try await product.purchase()
        
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            
            // Add credits to user's account
            usage.creditSeconds += pack.creditSeconds
            
            // Grant on-device features if this pack includes them
            if pack.grantsOnDeviceFeatures {
                usage.hasPrivacyPack = true
            }
            
            saveLocalData()
            
            await transaction.finish()
            return true
            
        case .userCancelled:
            return false
            
        case .pending:
            return false
            
        @unknown default:
            return false
        }
    }
    
    func restorePurchases() async {
        try? await AppStore.sync()
        await updatePurchasedProducts()
    }
    
    private func updatePurchasedProducts() async {
        var purchased: Set<String> = []
        
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                purchased.insert(transaction.productID)
            }
        }
        
        purchasedProductIDs = purchased
        
        // Update tier based on purchased products (prioritize yearly, then monthly, then highest tier)
        if let proYearlyId = SubscriptionTier.proYearly.productId, purchased.contains(proYearlyId) {
            currentTier = .proYearly
        } else if let proMonthlyId = SubscriptionTier.proMonthly.productId, purchased.contains(proMonthlyId) {
            currentTier = .proMonthly
        } else if let standardYearlyId = SubscriptionTier.standardYearly.productId, purchased.contains(standardYearlyId) {
            currentTier = .standardYearly
        } else if let standardMonthlyId = SubscriptionTier.standardMonthly.productId, purchased.contains(standardMonthlyId) {
            currentTier = .standardMonthly
        } else {
            currentTier = .free
        }
        
        saveLocalData()
    }
    
    private func observeTransactionUpdates() -> Task<Void, Never> {
        Task(priority: .background) {
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    await updatePurchasedProducts()
                }
            }
        }
    }
    
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw SubscriptionError.verificationFailed
        case .verified(let safe):
            return safe
        }
    }
    
    // MARK: - Persistence
    
    private func loadLocalData() {
        if let data = userDefaults.data(forKey: usageKey),
           let usage = try? JSONDecoder().decode(UsageData.self, from: data) {
            self.usage = usage
        }
        
        if let tierString = userDefaults.string(forKey: tierKey),
           let tier = SubscriptionTier(rawValue: tierString) {
            self.currentTier = tier
        }
    }
    
    private func saveLocalData() {
        if let data = try? JSONEncoder().encode(usage) {
            userDefaults.set(data, forKey: usageKey)
        }
        userDefaults.set(currentTier.rawValue, forKey: tierKey)
    }
    
    // MARK: - Debug (Remove in production)
    
    #if DEBUG
    func setTierForTesting(_ tier: SubscriptionTier) {
        currentTier = tier
        saveLocalData()
    }
    
    func resetUsageForTesting() {
        usage = .empty
        saveLocalData()
    }
    
    func addUsageForTesting(seconds: TimeInterval) {
        usage.transcriptionSecondsUsed += seconds
        saveLocalData()
    }
    #endif
}

// MARK: - Errors

enum SubscriptionError: LocalizedError {
    case productNotFound
    case verificationFailed
    case purchaseFailed
    
    var errorDescription: String? {
        switch self {
        case .productNotFound:
            return "Subscription product not found"
        case .verificationFailed:
            return "Purchase verification failed"
        case .purchaseFailed:
            return "Purchase could not be completed"
        }
    }
}
