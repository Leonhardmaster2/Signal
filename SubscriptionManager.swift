import Foundation
import StoreKit
import SwiftUI

// MARK: - Subscription Tiers

enum SubscriptionTier: String, Codable, CaseIterable {
    case free = "free"
    case standard = "standard"
    case pro = "pro"
    
    var displayName: String {
        switch self {
        case .free: return "Free"
        case .standard: return "Standard"
        case .pro: return "Pro"
        }
    }
    
    var tagline: String {
        switch self {
        case .free: return "The Hook"
        case .standard: return "The Daily Driver"
        case .pro: return "The Power User"
        }
    }
    
    var monthlyPrice: String {
        switch self {
        case .free: return "Free"
        case .standard: return "$12/mo"
        case .pro: return "$35/mo"
        }
    }
    
    /// Monthly transcription limit in seconds
    var transcriptionLimitSeconds: TimeInterval {
        switch self {
        case .free: return 0             // 0 hours - must upgrade to transcribe
        case .standard: return 12 * 3600 // 12 hours
        case .pro: return 60 * 3600      // 60 hours
        }
    }
    
    /// Human-readable transcription limit
    var transcriptionLimitLabel: String {
        switch self {
        case .free: return "Upgrade to transcribe"
        case .standard: return "12 hours/month"
        case .pro: return "60 hours/month"
        }
    }
    
    /// Maximum number of stored transcripts (nil = unlimited)
    var historyLimit: Int? {
        switch self {
        case .free: return 5
        case .standard: return nil
        case .pro: return nil
        }
    }
    
    var historyLimitLabel: String {
        switch self {
        case .free: return "Last 5 transcripts"
        case .standard: return "Unlimited history"
        case .pro: return "Unlimited history"
        }
    }
    
    /// Summarization quality description
    var summarizationQuality: String {
        switch self {
        case .free: return "Standard bullet points"
        case .standard: return "Deep Dive (takeaways, actions, sentiment)"
        case .pro: return "Deep Dive + Ask Your Audio"
        }
    }
    
    /// Features list for the tier
    var features: [SubscriptionFeature] {
        switch self {
        case .free:
            return [
                SubscriptionFeature(icon: "mic.fill", text: "Unlimited free recording"),
                SubscriptionFeature(icon: "lock.fill", text: "Transcription requires upgrade"),
                SubscriptionFeature(icon: "waveform", text: "Basic audio playback"),
                SubscriptionFeature(icon: "doc.text", text: "Last 5 recordings only")
            ]
        case .standard:
            return [
                SubscriptionFeature(icon: "clock.fill", text: "12 hours transcription/month"),
                SubscriptionFeature(icon: "brain", text: "AI-powered summaries"),
                SubscriptionFeature(icon: "infinity", text: "Unlimited history"),
                SubscriptionFeature(icon: "person.2.fill", text: "Speaker identification"),
                SubscriptionFeature(icon: "doc.richtext", text: "Export to PDF/Markdown"),
                SubscriptionFeature(icon: "star", text: "Priority support")
            ]
        case .pro:
            return [
                SubscriptionFeature(icon: "clock.badge.checkmark", text: "60 hours transcription/month"),
                SubscriptionFeature(icon: "bubble.left.and.bubble.right", text: "Ask Your Audio (chat with transcripts)"),
                SubscriptionFeature(icon: "bolt.fill", text: "Priority processing"),
                SubscriptionFeature(icon: "arrow.up.doc", text: "Upload files up to 2h+"),
                SubscriptionFeature(icon: "magnifyingglass", text: "Audio search"),
                SubscriptionFeature(icon: "checkmark.seal.fill", text: "Everything in Standard")
            ]
        }
    }
    
    /// StoreKit product ID
    var productId: String? {
        switch self {
        case .free: return nil
        case .standard: return "com.proceduralabs.signal.standard.monthly"
        case .pro: return "com.proceduralabs.signal.pro.monthly"
        }
    }
}

struct SubscriptionFeature: Identifiable {
    let id = UUID()
    let icon: String
    let text: String
}

// MARK: - Usage Tracking

struct UsageData: Codable {
    var transcriptionSecondsUsed: TimeInterval
    var periodStartDate: Date
    var transcriptCount: Int
    
    static var empty: UsageData {
        UsageData(transcriptionSecondsUsed: 0, periodStartDate: Date(), transcriptCount: 0)
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
        currentTier == .standard || currentTier == .pro
    }
    
    /// Whether user can transcribe (has a paid subscription)
    var canTranscribeAtAll: Bool {
        isSubscribed
    }
    
    /// Remaining transcription time in seconds
    var remainingTranscriptionSeconds: TimeInterval {
        max(0, currentTier.transcriptionLimitSeconds - usage.transcriptionSecondsUsed)
    }
    
    /// Remaining transcription time as formatted string
    var remainingTranscriptionLabel: String {
        let remaining = remainingTranscriptionSeconds
        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m remaining"
        } else {
            return "\(minutes)m remaining"
        }
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
    
    /// Record transcription usage
    func recordTranscriptionUsage(seconds: TimeInterval) {
        checkAndResetPeriod()
        usage.transcriptionSecondsUsed += seconds
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
                transcriptCount: usage.transcriptCount
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
        
        let productIds = SubscriptionTier.allCases.compactMap { $0.productId }
        
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
        
        // Update tier based on purchased products
        if let proId = SubscriptionTier.pro.productId, purchased.contains(proId) {
            currentTier = .pro
        } else if let standardId = SubscriptionTier.standard.productId, purchased.contains(standardId) {
            currentTier = .standard
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
