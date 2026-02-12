import SwiftUI

// MARK: - Onboarding View

struct OnboardingView: View {
    @Binding var isPresented: Bool
    @State private var currentPage = 0
    @State private var showPaywall = false
    
    private let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "mic.fill",
            iconColor: .white,
            title: "Unlimited Free Recording",
            subtitle: "Capture every meeting, lecture, or conversation with crystal-clear audio. Record as much as you want, completely free.",
            highlight: "No limits on recording time"
        ),
        OnboardingPage(
            icon: "waveform.badge.magnifyingglass",
            iconColor: .white,
            title: "AI-Powered Transcription",
            subtitle: "Transform your recordings into searchable, shareable text. Our AI accurately transcribes speech and identifies speakers.",
            highlight: "Upgrade to unlock transcription"
        ),
        OnboardingPage(
            icon: "brain",
            iconColor: .white,
            title: "Smart Summaries",
            subtitle: "Get instant meeting summaries, action items, and key takeaways. Never miss an important detail again.",
            highlight: "Available with Standard & Pro"
        )
    ]
    
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
                        Text("Skip")
                            .font(AppFont.mono(size: 14, weight: .medium))
                            .foregroundStyle(.gray)
                    }
                    .padding()
                }
                
                Spacer()
                
                // Page content
                TabView(selection: $currentPage) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                        OnboardingPageView(page: page)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                
                Spacer()
                
                // Page indicator
                HStack(spacing: 8) {
                    ForEach(0..<pages.count, id: \.self) { index in
                        Circle()
                            .fill(index == currentPage ? Color.white : Color.white.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }
                .padding(.bottom, 32)
                
                // Action button
                Button {
                    if currentPage < pages.count - 1 {
                        withAnimation {
                            currentPage += 1
                        }
                    } else {
                        completeOnboarding()
                    }
                } label: {
                    Text(currentPage < pages.count - 1 ? "CONTINUE" : "GET STARTED")
                        .font(AppFont.mono(size: 14, weight: .bold))
                        .kerning(2.0)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Color.white)
                        .clipShape(Capsule())
                }
                .padding(.horizontal, 32)
                
                // Upgrade prompt on last page
                if currentPage == pages.count - 1 {
                    Button {
                        showPaywall = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 12))
                            Text("View Premium Plans")
                                .font(AppFont.mono(size: 12, weight: .medium))
                        }
                        .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(.top, 16)
                }
                
                Spacer()
                    .frame(height: 50)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }
    
    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        isPresented = false
    }
}

// MARK: - Onboarding Page Model

struct OnboardingPage {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let highlight: String
}

// MARK: - Onboarding Page View

struct OnboardingPageView: View {
    let page: OnboardingPage
    
    var body: some View {
        VStack(spacing: 32) {
            // Icon with glow effect
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 120, height: 120)
                
                Circle()
                    .fill(Color.white.opacity(0.05))
                    .frame(width: 160, height: 160)
                
                Image(systemName: page.icon)
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(page.iconColor)
            }
            
            VStack(spacing: 16) {
                Text(page.title)
                    .font(AppFont.mono(size: 24, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                
                Text(page.subtitle)
                    .font(AppFont.mono(size: 14, weight: .regular))
                    .foregroundStyle(.gray)
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
                    .padding(.horizontal, 24)
            }
            
            // Highlight pill
            Text(page.highlight)
                .font(AppFont.mono(size: 11, weight: .bold))
                .kerning(1.0)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.15))
                .clipShape(Capsule())
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

#Preview {
    OnboardingView(isPresented: .constant(true))
}
