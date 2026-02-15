import SwiftUI

// MARK: - Onboarding View

struct OnboardingView: View {
    @Binding var isPresented: Bool
    @State private var currentPage = 0
    @State private var showPaywall = false
    @State private var showCreditOffer = false
    @State private var creditOfferPrice: Double = 3.00
    @State private var hasShownCreditOffer = false

    /// Total pages: language picker (0) + 3 content pages (1,2,3)
    private let totalPages = 4

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Skip button
                HStack {
                    Spacer()
                    Button {
                        completeOnboarding()
                    } label: {
                        Text(L10n.skip)
                            .font(AppFont.mono(size: 14, weight: .medium))
                            .foregroundStyle(.gray)
                    }
                    .padding()
                }

                Spacer()

                // Page content
                TabView(selection: $currentPage) {
                    // Page 0: Language selection
                    LanguageSelectionPage()
                        .tag(0)

                    // Page 1-3: Feature pages
                    OnboardingPageView(
                        icon: "mic.fill",
                        iconColor: .white,
                        title: L10n.onboardingTitle1,
                        subtitle: L10n.onboardingSubtitle1,
                        highlight: L10n.onboardingHighlight1
                    ).tag(1)

                    OnboardingPageView(
                        icon: "waveform.badge.magnifyingglass",
                        iconColor: .white,
                        title: L10n.onboardingTitle2,
                        subtitle: L10n.onboardingSubtitle2,
                        highlight: L10n.onboardingHighlight2
                    ).tag(2)

                    OnboardingPageView(
                        icon: "brain",
                        iconColor: .white,
                        title: L10n.onboardingTitle3,
                        subtitle: L10n.onboardingSubtitle3,
                        highlight: L10n.onboardingHighlight3
                    ).tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                Spacer()

                // Page indicator
                HStack(spacing: 8) {
                    ForEach(0..<totalPages, id: \.self) { index in
                        Circle()
                            .fill(index == currentPage ? Color.white : Color.white.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }
                .padding(.bottom, 32)

                // Button container with fixed height to prevent jumping
                VStack(spacing: 20) {
                    // Upgrade prompt (always shown on last page, above main button)
                    if currentPage == totalPages - 1 {
                        Button {
                            showPaywall = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 12))
                                Text(L10n.viewPremiumPlans)
                                    .font(AppFont.mono(size: 12, weight: .medium))
                            }
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                        }
                    } else {
                        // Invisible spacer to maintain consistent height
                        Color.clear
                            .frame(height: 44)
                    }

                    // Main action button
                    Button {
                        if currentPage < totalPages - 1 {
                            withAnimation {
                                currentPage += 1
                            }
                        } else {
                            completeOnboarding()
                        }
                    } label: {
                        Text(currentPage < totalPages - 1 ? L10n.continueButton : L10n.getStarted)
                            .font(AppFont.mono(size: 14, weight: .bold))
                            .kerning(2.0)
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(Color.white)
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 32)
                .frame(height: 96) // Fixed height to prevent jumping

                Spacer()
                    .frame(height: 50)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .sheet(isPresented: $showCreditOffer) {
            CreditPackOfferView(
                price: creditOfferPrice,
                onPurchase: {
                    // User purchased - don't show the second offer
                    UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                    isPresented = false
                },
                onDismiss: {
                    // User dismissed without purchasing
                    // Only show the lower price offer if they haven't purchased
                    if creditOfferPrice == 3.00 && SubscriptionManager.shared.remainingCreditSeconds == 0 {
                        // First dismissal - show lower price
                        creditOfferPrice = 1.50
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showCreditOffer = true
                        }
                    } else {
                        // Second dismissal or already has credits - let them proceed
                        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                        isPresented = false
                    }
                }
            )
        }
    }
    
    private func completeOnboarding() {
        // Check if user should see credit offer
        if !hasShownCreditOffer && !SubscriptionManager.shared.isSubscribed {
            hasShownCreditOffer = true
            showCreditOffer = true
        } else {
            UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
            isPresented = false
        }
    }
}

// MARK: - Language Selection Page

struct LanguageSelectionPage: View {
    var body: some View {
        VStack(spacing: 24) {
            // Globe icon
            ZStack {
                Image(systemName: "globe")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(.white)
                    .padding(36)
            }
            .glassEffect(.regular, in: Circle())

            Text(L10n.chooseLanguage)
                .font(AppFont.mono(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            // Language grid
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(AppLanguage.allCases) { lang in
                        LanguageCell(language: lang)
                    }
                }
                .padding(.horizontal, 16)
            }
            .frame(maxHeight: 300)
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - Language Cell

private struct LanguageCell: View {
    let language: AppLanguage
    @State private var locManager = LocalizationManager.shared

    var isSelected: Bool { locManager.currentLanguage == language }

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) {
                locManager.currentLanguage = language
            }
        } label: {
            HStack(spacing: 8) {
                Text(language.flag)
                    .font(.system(size: 18))

                Text(language.nativeName)
                    .font(AppFont.mono(size: 12, weight: isSelected ? .bold : .regular))
                    .foregroundStyle(isSelected ? .white : .gray)
                    .lineLimit(1)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isSelected ? Color.white.opacity(0.12) : Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.white.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
    }
}

// MARK: - Onboarding Page View

struct OnboardingPageView: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let highlight: String

    var body: some View {
        VStack(spacing: 32) {
            // Icon with glass effect
            ZStack {
                Image(systemName: icon)
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(iconColor)
                    .padding(36)
            }
            .glassEffect(.regular, in: Circle())

            VStack(spacing: 20) {
                Text(title)
                    .font(AppFont.mono(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)

                Text(subtitle)
                    .font(AppFont.mono(size: 13, weight: .regular))
                    .foregroundStyle(.gray)
                    .multilineTextAlignment(.center)
                    .lineSpacing(8)
                    .padding(.horizontal, 32)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Highlight pill with glass effect
            Text(highlight)
                .font(AppFont.mono(size: 11, weight: .bold))
                .kerning(1.0)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .glassEffect(.regular.tint(.white.opacity(0.1)), in: Capsule())
        }
        .padding(.horizontal, 32)
    }
}

// MARK: - Onboarding Manager

struct OnboardingManager {
    static var hasCompletedOnboarding: Bool {
        UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
    }
    
    static func resetOnboarding() {
        UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
    }
}

// MARK: - Credit Pack Offer View

struct CreditPackOfferView: View {
    let price: Double
    let onPurchase: () -> Void
    let onDismiss: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var isPurchasing = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Close button
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.gray)
                            .padding(12)
                    }
                    .disabled(isPurchasing)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                
                Spacer()
                
                VStack(spacing: 24) {
                    // Badge
                    if price == 3.00 {
                        Text(L10n.oneTimeOffer)
                            .font(AppFont.mono(size: 10, weight: .bold))
                            .foregroundStyle(.black)
                            .kerning(1.2)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.white)
                            .clipShape(Capsule())
                    } else {
                        Text(L10n.finalOffer)
                            .font(AppFont.mono(size: 10, weight: .bold))
                            .foregroundStyle(.black)
                            .kerning(1.2)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.red)
                            .clipShape(Capsule())
                    }

                    // Title
                    Text(L10n.tryBeforeSubscribe)
                        .font(AppFont.mono(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    
                    // Price
                    VStack(spacing: 6) {
                        if price == 1.50 {
                            Text("$3.00")
                                .font(AppFont.mono(size: 18, weight: .bold))
                                .foregroundStyle(.gray.opacity(0.5))
                                .strikethrough(color: .red)
                        }
                        
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text("$")
                                .font(AppFont.mono(size: 24, weight: .bold))
                                .foregroundStyle(.white)
                            Text(String(format: "%.2f", price))
                                .font(AppFont.mono(size: 56, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    
                    // Features
                    VStack(spacing: 10) {
                        OfferFeature(icon: "clock.fill", text: L10n.twoHoursTranscription)
                        OfferFeature(icon: "infinity", text: L10n.creditsNeverExpire)
                        OfferFeature(icon: "xmark.circle.fill", text: L10n.noSubscriptionRequired)
                    }
                }
                
                Spacer()
                
                // Purchase button
                VStack(spacing: 10) {
                    Button {
                        Task {
                            await purchaseCreditPack()
                        }
                    } label: {
                        if isPurchasing {
                            ProgressView()
                                .tint(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                        } else {
                            Text(L10n.get2Hours)
                                .font(AppFont.mono(size: 13, weight: .bold))
                                .kerning(1.5)
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                        }
                    }
                    .background(price == 1.50 ? Color.yellow : Color.white)
                    .clipShape(Capsule())
                    .disabled(isPurchasing)
                    
                    Text(L10n.oneTimePurchase)
                        .font(AppFont.mono(size: 9, weight: .regular))
                        .foregroundStyle(.gray)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 40)
            }
        }
        .preferredColorScheme(.dark)
        .alert(L10n.purchaseError, isPresented: $showError) {
            Button(L10n.ok, role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }
    
    private func purchaseCreditPack() async {
        isPurchasing = true
        
        do {
            let success = try await SubscriptionManager.shared.purchaseCreditPack(.privacyPack)
            
            if success {
                dismiss()
                onPurchase()
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        
        isPurchasing = false
    }
}

// MARK: - Offer Feature Row

struct OfferFeature: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 16)
            
            Text(text)
                .font(AppFont.mono(size: 12, weight: .regular))
                .foregroundStyle(.white.opacity(0.8))
            
            Spacer()
        }
        .padding(.horizontal, 32)
    }
}

#Preview {
    OnboardingView(isPresented: .constant(true))
}
