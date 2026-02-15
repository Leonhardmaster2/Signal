// LocalizationManager.swift
// Manages app-wide localization with runtime language switching

import Foundation
import Observation

// MARK: - AppLanguage

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case german = "de"
    case french = "fr"
    case spanish = "es"
    case italian = "it"
    case portuguese = "pt"
    case dutch = "nl"
    case polish = "pl"
    case swedish = "sv"
    case danish = "da"
    case norwegian = "no"
    case finnish = "fi"
    case czech = "cs"
    case russian = "ru"
    case turkish = "tr"
    case chinese = "zh"
    case japanese = "ja"
    case korean = "ko"
    case hindi = "hi"
    case arabic = "ar"

    var id: String { rawValue }

    var flag: String {
        switch self {
        case .english: return "\u{1F1FA}\u{1F1F8}"
        case .german: return "\u{1F1E9}\u{1F1EA}"
        case .french: return "\u{1F1EB}\u{1F1F7}"
        case .spanish: return "\u{1F1EA}\u{1F1F8}"
        case .italian: return "\u{1F1EE}\u{1F1F9}"
        case .portuguese: return "\u{1F1E7}\u{1F1F7}"
        case .dutch: return "\u{1F1F3}\u{1F1F1}"
        case .polish: return "\u{1F1F5}\u{1F1F1}"
        case .swedish: return "\u{1F1F8}\u{1F1EA}"
        case .danish: return "\u{1F1E9}\u{1F1F0}"
        case .norwegian: return "\u{1F1F3}\u{1F1F4}"
        case .finnish: return "\u{1F1EB}\u{1F1EE}"
        case .czech: return "\u{1F1E8}\u{1F1FF}"
        case .russian: return "\u{1F1F7}\u{1F1FA}"
        case .turkish: return "\u{1F1F9}\u{1F1F7}"
        case .chinese: return "\u{1F1E8}\u{1F1F3}"
        case .japanese: return "\u{1F1EF}\u{1F1F5}"
        case .korean: return "\u{1F1F0}\u{1F1F7}"
        case .hindi: return "\u{1F1EE}\u{1F1F3}"
        case .arabic: return "\u{1F1F8}\u{1F1E6}"
        }
    }

    var nativeName: String {
        switch self {
        case .english: return "English"
        case .german: return "Deutsch"
        case .french: return "Fran\u{00E7}ais"
        case .spanish: return "Espa\u{00F1}ol"
        case .italian: return "Italiano"
        case .portuguese: return "Portugu\u{00EA}s"
        case .dutch: return "Nederlands"
        case .polish: return "Polski"
        case .swedish: return "Svenska"
        case .danish: return "Dansk"
        case .norwegian: return "Norsk"
        case .finnish: return "Suomi"
        case .czech: return "\u{010C}e\u{0161}tina"
        case .russian: return "\u{0420}\u{0443}\u{0441}\u{0441}\u{043A}\u{0438}\u{0439}"
        case .turkish: return "T\u{00FC}rk\u{00E7}e"
        case .chinese: return "\u{4E2D}\u{6587}"
        case .japanese: return "\u{65E5}\u{672C}\u{8A9E}"
        case .korean: return "\u{D55C}\u{AD6D}\u{C5B4}"
        case .hindi: return "\u{0939}\u{093F}\u{0928}\u{094D}\u{0926}\u{0940}"
        case .arabic: return "\u{0627}\u{0644}\u{0639}\u{0631}\u{0628}\u{064A}\u{0629}"
        }
    }

    var englishName: String {
        switch self {
        case .english: return "English"
        case .german: return "German"
        case .french: return "French"
        case .spanish: return "Spanish"
        case .italian: return "Italian"
        case .portuguese: return "Portuguese"
        case .dutch: return "Dutch"
        case .polish: return "Polish"
        case .swedish: return "Swedish"
        case .danish: return "Danish"
        case .norwegian: return "Norwegian"
        case .finnish: return "Finnish"
        case .czech: return "Czech"
        case .russian: return "Russian"
        case .turkish: return "Turkish"
        case .chinese: return "Chinese"
        case .japanese: return "Japanese"
        case .korean: return "Korean"
        case .hindi: return "Hindi"
        case .arabic: return "Arabic"
        }
    }

    /// Returns the translation dictionary for this language
    var strings: [String: String] {
        switch self {
        case .english: return L10n.englishStrings
        case .german: return L10n.germanStrings
        case .french: return L10n.frenchStrings
        case .spanish: return L10n.spanishStrings
        case .italian: return L10n.italianStrings
        case .portuguese: return L10n.portugueseStrings
        case .dutch: return L10n.dutchStrings
        case .polish: return L10n.polishStrings
        case .swedish: return L10n.swedishStrings
        case .danish: return L10n.danishStrings
        case .norwegian: return L10n.norwegianStrings
        case .finnish: return L10n.finnishStrings
        case .czech: return L10n.czechStrings
        case .russian: return L10n.russianStrings
        case .turkish: return L10n.turkishStrings
        case .chinese: return L10n.chineseStrings
        case .japanese: return L10n.japaneseStrings
        case .korean: return L10n.koreanStrings
        case .hindi: return L10n.hindiStrings
        case .arabic: return L10n.arabicStrings
        }
    }
}

// MARK: - LocalizationManager

@Observable
final class LocalizationManager {
    static let shared = LocalizationManager()

    var currentLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(currentLanguage.rawValue, forKey: "appLanguage")
        }
    }

    private init() {
        if let saved = UserDefaults.standard.string(forKey: "appLanguage"),
           let lang = AppLanguage(rawValue: saved) {
            self.currentLanguage = lang
        } else {
            // Auto-detect from system locale
            let systemCode = Locale.current.language.languageCode?.identifier ?? "en"
            self.currentLanguage = AppLanguage(rawValue: systemCode) ?? .english
        }
    }
}

// MARK: - L10n (Localization Accessors)

enum L10n {
    /// Core translation function — looks up key in current language, falls back to English
    static func t(_ key: String) -> String {
        let lang = LocalizationManager.shared.currentLanguage
        return lang.strings[key] ?? L10n.englishStrings[key] ?? key
    }

    // MARK: - Common
    static var skip: String { t("skip") }
    static var cancel: String { t("cancel") }
    static var delete: String { t("delete") }
    static var done: String { t("done") }
    static var ok: String { t("ok") }
    static var save: String { t("save") }
    static var close: String { t("close") }
    static var confirm: String { t("confirm") }
    static var error: String { t("error") }
    static var loading: String { t("loading") }
    static var search: String { t("search") }
    static var settings: String { t("settings") }
    static var copied: String { t("copied") }
    static var of: String { t("of") }

    // MARK: - Onboarding
    static var onboardingTitle1: String { t("onboarding_title_1") }
    static var onboardingSubtitle1: String { t("onboarding_subtitle_1") }
    static var onboardingHighlight1: String { t("onboarding_highlight_1") }
    static var onboardingTitle2: String { t("onboarding_title_2") }
    static var onboardingSubtitle2: String { t("onboarding_subtitle_2") }
    static var onboardingHighlight2: String { t("onboarding_highlight_2") }
    static var onboardingTitle3: String { t("onboarding_title_3") }
    static var onboardingSubtitle3: String { t("onboarding_subtitle_3") }
    static var onboardingHighlight3: String { t("onboarding_highlight_3") }
    static var continueButton: String { t("continue") }
    static var getStarted: String { t("get_started") }
    static var viewPremiumPlans: String { t("view_premium_plans") }
    static var chooseLanguage: String { t("choose_language") }
    static var selectYourLanguage: String { t("select_your_language") }

    // MARK: - Credit Offer
    static var oneTimeOffer: String { t("one_time_offer") }
    static var finalOffer: String { t("final_offer") }
    static var tryBeforeSubscribe: String { t("try_before_subscribe") }
    static var get2Hours: String { t("get_2_hours") }
    static var oneTimePurchase: String { t("one_time_purchase") }
    static var twoHoursTranscription: String { t("2_hours_transcription") }
    static var creditsNeverExpire: String { t("credits_never_expire") }
    static var noSubscriptionRequired: String { t("no_subscription_required") }
    static var purchaseError: String { t("purchase_error") }

    // MARK: - Dashboard / Content
    static var trace: String { t("trace") }
    static var searchRecordings: String { t("search_recordings") }
    static var noRecordings: String { t("no_recordings") }
    static var tapToRecord: String { t("tap_to_record") }
    static var signals: String { t("signals") }
    static var captured: String { t("captured") }
    static var decoded: String { t("decoded") }
    static var record: String { t("record") }
    static var today: String { t("today") }
    static var yesterday: String { t("yesterday") }
    static var selectRecording: String { t("select_recording") }
    static var deleteRecording: String { t("delete_recording") }
    static var deleteRecordingMessage: String { t("delete_recording_message") }
    static var renameRecording: String { t("rename_recording") }
    static var enterNewName: String { t("enter_new_name") }
    static var rename: String { t("rename") }
    static var upgradeUnlimitedHistory: String { t("upgrade_unlimited_history") }

    // MARK: - Recorder
    static var paused: String { t("paused") }
    static var recording: String { t("recording") }
    static var mark: String { t("mark") }
    static var notes: String { t("notes") }
    static var pause: String { t("pause") }
    static var resume: String { t("resume") }
    static var cut: String { t("cut") }
    static var marks: String { t("marks") }
    static var discardRecording: String { t("discard_recording") }
    static var discardMessage: String { t("discard_message") }
    static var discard: String { t("discard") }
    static var microphoneAccess: String { t("microphone_access") }
    static var keepRecording: String { t("keep_recording") }

    // MARK: - Decoded View
    static var decodedTitle: String { t("decoded_title") }
    static var pickDateTime: String { t("pick_date_time") }
    static var transcribing: String { t("transcribing") }
    static var summarizing: String { t("summarizing") }
    static var theOneLiner: String { t("the_one_liner") }
    static var context: String { t("context") }
    static var actions: String { t("actions") }
    static var emails: String { t("emails") }
    static var reminders: String { t("reminders") }
    static var calendarEvents: String { t("calendar_events") }
    static var transcript: String { t("transcript") }
    static var transcriptionChoose: String { t("transcription_choose") }
    static var cloudTranscription: String { t("cloud_transcription") }
    static var onDeviceTranscription: String { t("on_device_transcription") }
    static var retranscribe: String { t("retranscribe") }
    static var resummarize: String { t("resummarize") }
    static var shareAudio: String { t("share_audio") }
    static var shareTranscript: String { t("share_transcript") }

    // MARK: - Ask Audio
    static var askYourAudio: String { t("ask_your_audio") }
    static var askAnything: String { t("ask_anything") }
    static var askAudioHelp: String { t("ask_audio_help") }
    static var suggestedKeyDecisions: String { t("suggested_key_decisions") }
    static var suggestedMainTopics: String { t("suggested_main_topics") }
    static var suggestedWhoSaid: String { t("suggested_who_said") }

    // MARK: - Settings
    static var subscription: String { t("subscription") }
    static var recordingSection: String { t("recording_section") }
    static var autoTranscribe: String { t("auto_transcribe") }
    static var quality: String { t("quality") }
    static var standardQuality: String { t("standard_quality") }
    static var highQuality: String { t("high_quality") }
    static var onDeviceIntelligence: String { t("on_device_intelligence") }
    static var appleTranscription: String { t("apple_transcription") }
    static var usesOnDeviceSpeech: String { t("uses_on_device_speech") }
    static var appleIntelligence: String { t("apple_intelligence") }
    static var summarizeOnDevice: String { t("summarize_on_device") }
    static var autoDetectLanguage: String { t("auto_detect_language") }
    static var autoDetectsSpoken: String { t("auto_detects_spoken") }
    static var fallbackLanguage: String { t("fallback_language") }
    static var usedIfDetectionFails: String { t("used_if_detection_fails") }
    static var transcriptionLanguage: String { t("transcription_language") }
    static var languageForTranscription: String { t("language_for_transcription") }
    static var onDevicePrivacy: String { t("on_device_privacy") }
    static var general: String { t("general") }
    static var hapticFeedback: String { t("haptic_feedback") }
    static var storage: String { t("storage") }
    static var recordings: String { t("recordings") }
    static var diskUsage: String { t("disk_usage") }
    static var deleteAllRecordings: String { t("delete_all_recordings") }
    static var deleteAllMessage: String { t("delete_all_message") }
    static var deleteAll: String { t("delete_all") }
    static var about: String { t("about") }
    static var version: String { t("version") }
    static var builtBy: String { t("built_by") }
    static var language: String { t("language") }
    static var appLanguage: String { t("app_language") }
    static var loadingLanguages: String { t("loading_languages") }
    static var onDevice: String { t("on_device") }
    static var requiresNetwork: String { t("requires_network") }

    // MARK: - Subscription / Paywall
    static var manageSubscription: String { t("manage_subscription") }
    static var transcriptionSection: String { t("transcription_section") }
    static var thisMonthUsage: String { t("this_month_usage") }
    static var upgradePlan: String { t("upgrade_plan") }
    static var unlockSignal: String { t("unlock_signal") }
    static var choosePlan: String { t("choose_plan") }
    static var monthly: String { t("monthly") }
    static var yearly: String { t("yearly") }
    static var saveWithAnnual: String { t("save_with_annual") }
    static var whatsIncluded: String { t("whats_included") }
    static var restorePurchases: String { t("restore_purchases") }
    static var current: String { t("current") }
    static var popular: String { t("popular") }
    static var billedYearly: String { t("billed_yearly") }
    static var free: String { t("free") }
    static var upgradeToTranscribe: String { t("upgrade_to_transcribe") }
    static var privacyPack: String { t("privacy_pack") }
    static var transcribeOnPhone: String { t("transcribe_on_phone") }
    static var twoHoursCloud: String { t("2_hours_cloud") }
    static var unlimitedOnDevice: String { t("unlimited_on_device") }
    static var privateAISummaries: String { t("private_ai_summaries") }
    static var buyPrivacyPack: String { t("buy_privacy_pack") }
    static var oneTimePurchaseSection: String { t("one_time_purchase_section") }

    // MARK: - Live Activity
    static var recordingLive: String { t("recording_live") }
    static var pausedLive: String { t("paused_live") }

    // MARK: - Badges
    static var onDeviceBadge: String { t("on_device_badge") }
    static var appleAIBadge: String { t("apple_ai_badge") }
    static var demoBadge: String { t("demo_badge") }

    // MARK: - Status
    static var statusTranscribing: String { t("status_transcribing") }
    static var statusSummarizing: String { t("status_summarizing") }
    static var statusDecoded: String { t("status_decoded") }
    static var statusTranscribed: String { t("status_transcribed") }
    static var statusRaw: String { t("status_raw") }

    // MARK: - Errors
    static var noAPIKey: String { t("no_api_key") }
    static var noTranscript: String { t("no_transcript") }
    static var transcriptionFailed: String { t("transcription_failed") }

    // MARK: - DecodedView Sections
    static var playback: String { t("playback") }
    static var distillation: String { t("distillation") }
    static var actionVectors: String { t("action_vectors") }
    static var meetingNotes: String { t("meeting_notes") }
    static var attachments: String { t("attachments") }
    static var details: String { t("details") }
    static var exportCompressed: String { t("export_compressed") }
    static var extractedText: String { t("extracted_text") }
    static var transcriptText: String { t("transcript_text") }

    // MARK: - DecodedView Actions
    static var cancelTranscription: String { t("cancel_transcription") }
    static var transcribe: String { t("transcribe") }
    static var summarize: String { t("summarize") }
    static var deleteTranscript: String { t("delete_transcript") }
    static var shareTracePackage: String { t("share_trace_package") }
    static var copyTranscript: String { t("copy_transcript") }
    static var exportAsMarkdown: String { t("export_as_markdown") }
    static var exportAsPDF: String { t("export_as_pdf") }
    static var shareAsText: String { t("share_as_text") }
    static var exportTranscript: String { t("export_transcript") }
    static var unlockTranscription: String { t("unlock_transcription") }
    static var addToNotes: String { t("add_to_notes") }
    static var extractText: String { t("extract_text") }
    static var saveChanges: String { t("save_changes") }
    static var editSegment: String { t("edit_segment") }
    static var retry: String { t("retry") }
    static var image: String { t("image") }
    static var audio: String { t("audio") }
    static var distill: String { t("distill") }

    // MARK: - DecodedView Messages
    static var noTranscriptYet: String { t("no_transcript_yet") }
    static var readyToSummarize: String { t("ready_to_summarize") }
    static var transcribeFirstToUnlock: String { t("transcribe_first_to_unlock") }
    static var deleteTranscriptMessage: String { t("delete_transcript_message") }
    static var reencodeDescription: String { t("reencode_description") }
    static var compressing: String { t("compressing") }
    static var extractingText: String { t("extracting_text") }
    static var processingImage: String { t("processing_image") }
    static var tapToAddNotes: String { t("tap_to_add_notes") }
    static var addPhotosDescription: String { t("add_photos_description") }
    static var notYetDecoded: String { t("not_yet_decoded") }
    static var transcriptionLocked: String { t("transcription_locked") }
    static var transcribeToExtract: String { t("transcribe_to_extract") }
    static var upgradeToUnlockAI: String { t("upgrade_to_unlock_ai") }
    static var noTranscriptTitle: String { t("no_transcript_title") }
    static var transcribeFirst: String { t("transcribe_first") }
    static var upgradeToUnlockTranscription: String { t("upgrade_to_unlock_transcription") }
    static var processingRecording: String { t("processing_recording") }
    static var statusTranscribingTitle: String { t("status_transcribing_title") }

    // MARK: - Speaker Renaming
    static var renameSpeaker: String { t("rename_speaker") }
    static var name: String { t("name") }
    static var enterSpeakerName: String { t("enter_speaker_name") }

    // MARK: - Transcription Method Chooser
    static var chooseTranscriptionMethod: String { t("choose_transcription_method") }
    static var selectTranscriptionMethod: String { t("select_transcription_method") }
    static var appleOnDevice: String { t("apple_on_device") }
    static var privateAndUnlimited: String { t("private_and_unlimited") }
    static var included: String { t("included") }
    static var unlimited: String { t("unlimited") }
    static var elevenlabsAPI: String { t("elevenlabs_api") }
    static var higherAccuracy: String { t("higher_accuracy") }
    static var notEnoughUsage: String { t("not_enough_usage") }
    static var monthlyAPIUsage: String { t("monthly_api_usage") }

    // MARK: - RecordingOverviewSheet
    static var review: String { t("review") }
    static var waveform: String { t("waveform") }
    static var recordingInfo: String { t("recording_info") }
    static var titleLabel: String { t("title") }
    static var trimmed: String { t("trimmed") }
    static var saveAndTranscribe: String { t("save_and_transcribe") }
    static var saveWithoutTranscribing: String { t("save_without_transcribing") }
    static var shareAudioFile: String { t("share_audio_file") }
    static var archive: String { t("archive") }

    // MARK: - ContentView (iPad)
    static var selectRecordingHelp: String { t("select_recording_help") }
    static var olderRecordingsHidden: String { t("older_recordings_hidden") }

    // MARK: - ShareSheet (macOS)
    static var share: String { t("share") }
    static var showInFinder: String { t("show_in_finder") }
    static var copyToClipboard: String { t("copy_to_clipboard") }

    // MARK: - Star / Misc UI
    static var star: String { t("star") }
    static var unstar: String { t("unstar") }
    static var speakers: String { t("speakers") }
    static var segments: String { t("segments") }
    static var plan: String { t("plan") }
    static var askAboutRecording: String { t("ask_about_recording") }

    // MARK: - Subscription Tier Names & Taglines
    static var tierFree: String { t("tier_free") }
    static var tierStandard: String { t("tier_standard") }
    static var tierPro: String { t("tier_pro") }
    static var taglineFree: String { t("tagline_free") }
    static var taglineStandard: String { t("tagline_standard") }
    static var taglinePro: String { t("tagline_pro") }

    // MARK: - Subscription Labels
    static var perMonth: String { t("per_month") }
    static var perYear: String { t("per_year") }
    static var unlimitedRecordings: String { t("unlimited_recordings") }
    static var transcriptionLimit15m: String { t("transcription_limit_15m") }
    static var transcriptionLimit12h: String { t("transcription_limit_12h") }
    static var transcriptionLimit36h: String { t("transcription_limit_36h") }
    static var uploadLocked: String { t("upload_locked") }
    static var upload2hMax: String { t("upload_2h_max") }
    static var uploadUnlimited: String { t("upload_unlimited") }

    // MARK: - Free Tier Features
    static var featureUnlimitedRecordings: String { t("feature_unlimited_recordings") }
    static var feature44khz: String { t("feature_44khz") }
    static var feature15minTranscription: String { t("feature_15min_transcription") }
    static var featureUnlimitedStorage: String { t("feature_unlimited_storage") }
    static var featureNoAI: String { t("feature_no_ai") }

    // MARK: - Standard Tier Features
    static var feature12hTranscription: String { t("feature_12h_transcription") }
    static var featureOnDeviceSpeech: String { t("feature_on_device_speech") }
    static var featureOnDeviceSummaries: String { t("feature_on_device_summaries") }
    static var featureSpeakerID: String { t("feature_speaker_id") }
    static var featureUpload2h: String { t("feature_upload_2h") }
    static var featureExportPDF: String { t("feature_export_pdf") }

    // MARK: - Pro Tier Features
    static var feature36hTranscription: String { t("feature_36h_transcription") }
    static var featurePriority: String { t("feature_priority") }
    static var featureUnlimitedUpload: String { t("feature_unlimited_upload") }
    static var featureAudioSearch: String { t("feature_audio_search") }
    static var featureEverythingStandard: String { t("feature_everything_standard") }

    // MARK: - Apple Terms
    static var appleTerms: String { t("apple_terms") }

    // MARK: - Pricing
    static var priceFree: String { t("price_free") }
    static var priceStandardMonthly: String { t("price_standard_monthly") }
    static var priceStandardYearly: String { t("price_standard_yearly") }
    static var priceStandardPerMonthYearly: String { t("price_standard_per_month_yearly") }
    static var priceProMonthly: String { t("price_pro_monthly") }
    static var priceProYearly: String { t("price_pro_yearly") }
    static var priceProPerMonthYearly: String { t("price_pro_per_month_yearly") }
    static var pricePrivacyPack: String { t("price_privacy_pack") }

    // MARK: - iCloud Backup
    static var icloudBackup: String { t("icloud_backup") }
    static var signInToBackup: String { t("sign_in_to_backup") }
    static var signInWithApple: String { t("sign_in_with_apple") }
    static var signOut: String { t("sign_out") }
    static var lastBackup: String { t("last_backup") }
    static var backupNow: String { t("backup_now") }
    static var backingUp: String { t("backing_up") }
    static var restore: String { t("restore") }
    static var restoreFromiCloud: String { t("restore_from_icloud") }
    static var restoring: String { t("restoring") }
    static var restoreWarning: String { t("restore_warning") }
    static var icloudNotAvailable: String { t("icloud_not_available") }
    static var signedIn: String { t("signed_in") }
    static var never: String { t("never") }
    static var backupComplete: String { t("backup_complete") }
    static var restoreComplete: String { t("restore_complete") }

    static func signedInAs(_ name: String) -> String {
        t("signed_in_as").replacingOccurrences(of: "{name}", with: name)
    }

    // MARK: - Dynamic Strings (with parameters)

    static func subscribeTo(_ name: String) -> String {
        t("subscribe_to").replacingOccurrences(of: "{name}", with: name)
    }

    static func resets(in days: Int) -> String {
        t("resets_in").replacingOccurrences(of: "{days}", with: "\(days)")
    }

    static func freeMinPerMonth(_ mins: String) -> String {
        t("free_min_per_month").replacingOccurrences(of: "{mins}", with: mins)
    }

    static func upgradeForAI() -> String {
        t("upgrade_for_ai")
    }

    static func ofTotal(_ used: String, _ total: String) -> String {
        "\(used) \(L10n.of) \(total)"
    }
}
