//
//  WorkerStyle.swift
//  NFCTimeSheets
//
//  THE WORKER'S SHARED VISUAL LANGUAGE - "Blue Hour" (TASK-363 on Android, TASK-365.9 / iOS B1).
//  Ported from android/.../ui/Theme.kt and WorkerVisuals.kt at 60f6886: 18 pt cards, 16 pt
//  inverse-filled primary buttons that are at least 56 pt tall, heavier titles. One file, so the
//  idle screen, the running screen, the receipt and every later worker screen say "surface",
//  "primary action" and "title" the same way instead of each keeping a private helper
//  (ShiftScreen's `card()` was the first of those).
//
//  THE ONE DESIGN DECISION, taken by the owner's proxy and not reopened here: the primary action
//  is INVERSE-FILLED exactly like Android - the inverse surface (near-black in light mode,
//  near-white in dark mode) with the page colour as its label - and it is NOT the system
//  AccentColor. Android's `inverseSurface` / `inverseOnSurface` are the two named colour sets
//  `WorkerInverse` / `WorkerOnInverse`, values copied from Theme.kt (TextPrimary / BgBase).
//
//  WHAT IS DELIBERATELY NOT HERE: no animation (Android has no idle animation either), no
//  hand-drawn glyphs (SF Symbols instead of Android's Canvas icons; the one local mark below is a
//  symbol in a circle and is hidden from VoiceOver), and no replacement of the system TabView or
//  the system List - the surfaces are drawn by the CONTENT, never by new chrome.
//
//  EVERYTHING SCALES WITH DYNAMIC TYPE: fonts are text styles (never fixed point sizes) and the
//  buttons have a MINIMUM height, so the largest accessibility size grows them instead of
//  clipping a label. Dark mode comes from the named colour sets and the semantic system colours;
//  nothing in here reads the colour scheme itself.
//

import SwiftUI

enum WorkerStyle {
    // MARK: Geometry (dp on Android, pt here - the same numbers)

    /// WorkerCard's corner radius (WorkerVisuals.kt `RoundedCornerShape(18.dp)`).
    static let cardRadius: CGFloat = 18
    /// ShiftRow / the settings cards pad their content by 18 dp.
    static let cardPadding: CGFloat = 18
    /// Primary button shape (`RoundedCornerShape(16.dp)`) and minimum height (`heightIn(min = 56.dp)`).
    static let buttonRadius: CGFloat = 16
    static let buttonMinHeight: CGFloat = 56
    /// A quiet text button's minimum height (`heightIn(min = 48.dp)`).
    static let quietButtonMinHeight: CGFloat = 48
    /// The screen's side margin and the gap between two stacked blocks (LazyColumn 20.dp / 16.dp).
    static let screenMargin: CGFloat = 20
    static let blockSpacing: CGFloat = 16

    // MARK: Colour - named sets and semantic system colours, never a literal

    /// Android `inverseSurface` / `inverseOnSurface`: the primary button's fill and its label.
    static let inverse = Color("WorkerInverse")
    static let onInverse = Color("WorkerOnInverse")
    /// The page, and the surface one step above it. The same relation Android keeps in both themes
    /// (Theme.kt: "dark raises by getting lighter, light raises by getting lighter too"), which on
    /// iOS is exactly the grouped-background pair.
    static let page = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    /// A soft fill for the one local mark (Android `surfaceContainerHigh` behind the entrance mark).
    static let soft = Color(uiColor: .tertiarySystemFill)

    // MARK: Typography - Android's overrides, as Dynamic Type text styles

    enum Typeface {
        /// headlineSmall 28 sp SemiBold: the day heading and every screen title.
        static let title = Font.title.weight(.semibold)
        /// titleLarge 22 sp SemiBold: a card's lead line, the start card's question.
        static let lead = Font.title2.weight(.semibold)
        /// titleMedium 16 sp SemiBold: a row's name.
        static let rowName = Font.headline
        /// labelLarge 14 sp SemiBold: a quiet state heading.
        static let label = Font.subheadline.weight(.semibold)
        /// labelMedium 12 sp: a date line, a caption.
        static let caption = Font.caption.weight(.medium)
    }
}

// MARK: - Surfaces

extension View {
    /// A WorkerCard: padded content on the card surface with 18 pt corners, full width.
    ///
    /// Semantic warning colours stay the CALLER's (Android: "semantic warning colours still belong
    /// to callers"), so this draws a surface and nothing else.
    func workerCard(padding: CGFloat = WorkerStyle.cardPadding) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(WorkerStyle.card, in: RoundedRectangle(cornerRadius: WorkerStyle.cardRadius, style: .continuous))
    }

    /// A List row with no chrome of its own: the card (or the bare content) inside it is the
    /// surface. Clear background and no separator, so a row can be swiped away (History) without
    /// the system's grouped container showing behind a card.
    func workerListRow() -> some View {
        self
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: WorkerStyle.blockSpacing / 2, leading: WorkerStyle.screenMargin,
                                      bottom: WorkerStyle.blockSpacing / 2, trailing: WorkerStyle.screenMargin))
    }

    /// The page behind a worker List: the grouped background, with the List's own hidden.
    func workerListPage() -> some View {
        self
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(WorkerStyle.page)
    }
}

// MARK: - Buttons

/// A field a worker control sits on when it is NOT the page: the running screen's fixed dark-blue (or its
/// neutral overdue field) and the ink drawn on it. Set once on that screen's content; the two button
/// styles below read it, so a primary button placed on a field inverts AGAINST that field exactly as
/// Android's does (`containerColor = onContainer, contentColor = container`) without every call site
/// passing colours.
struct WorkerField {
    let field: Color
    let ink: Color
}

extension EnvironmentValues {
    @Entry var workerField: WorkerField? = nil
}

/// The primary action: a full-width, inverse-filled, 16 pt-rounded button at least 56 pt tall.
///
/// On the page it is the inverse pair (`WorkerInverse` fill, `WorkerOnInverse` label). Inside a
/// `workerField` it takes the field's ink as its fill and the field as its label; `fill` / `ink` are an
/// explicit override and are nil for every ordinary call site.
struct WorkerPrimaryButtonStyle: ButtonStyle {
    var fill: Color? = nil
    var ink: Color? = nil

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.workerField) private var onField

    func makeBody(configuration: Configuration) -> some View {
        let fillColor = fill ?? onField?.ink ?? WorkerStyle.inverse
        let labelColor = ink ?? onField?.field ?? WorkerStyle.onInverse
        return configuration.label
            .font(.headline)
            .foregroundStyle(labelColor)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: WorkerStyle.buttonMinHeight)
            .padding(.horizontal, 16)
            .background(fillColor, in: RoundedRectangle(cornerRadius: WorkerStyle.buttonRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: WorkerStyle.buttonRadius, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1) : 0.4)
    }
}

/// The quiet action under a primary one ("Start without a tag", "Finish shift without a tag"): a text
/// button in the surrounding ink (the field's, when there is one), at least 48 pt tall. Still a real
/// button with a real label.
struct WorkerQuietButtonStyle: ButtonStyle {
    var ink: Color? = nil
    /// Centred under a centred block (the idle start card); `.leading` under left-aligned content, where a
    /// centred text button would hang in the middle of nothing (the Materials composer, More).
    var alignment: HorizontalAlignment = .center

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.workerField) private var onField

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body)
            .foregroundStyle(ink ?? onField?.ink ?? Color.secondary)
            .multilineTextAlignment(alignment == .leading ? .leading : .center)
            .frame(maxWidth: .infinity, minHeight: WorkerStyle.quietButtonMinHeight,
                   alignment: alignment == .leading ? .leading : .center)
            .contentShape(Rectangle())
            .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.4)
    }
}

extension ButtonStyle where Self == WorkerPrimaryButtonStyle {
    static var workerPrimary: WorkerPrimaryButtonStyle { WorkerPrimaryButtonStyle() }
}

extension ButtonStyle where Self == WorkerQuietButtonStyle {
    static var workerQuiet: WorkerQuietButtonStyle { WorkerQuietButtonStyle() }
    /// The same quiet text button, left-aligned and in the full ink (Android's TextButton in onSurface): the
    /// action under left-aligned content, where the secondary grey would read as a caption.
    static var workerQuietLeading: WorkerQuietButtonStyle { WorkerQuietButtonStyle(ink: Color.primary, alignment: .leading) }
}

// MARK: - The one local mark

/// A symbol in a soft circle: iOS's stand-in for Android's drawn entrance mark. Decoration only -
/// hidden from VoiceOver, because the words beside it say everything it says. By default the circle
/// scales with Dynamic Type through @ScaledMetric so the glyph never outgrows its disc.
///
/// `size` / `scales: false` is the SMALL, fixed one: Android's 64 dp supplies picture beside the
/// Materials heading is a fixed `Modifier.size(64.dp)` that does not follow the font scale, and a disc
/// that grew with the text would push the heading it sits beside off the line.
struct WorkerGlyph: View {
    let systemName: String
    private let size: CGFloat
    private let scales: Bool

    @ScaledMetric(relativeTo: .largeTitle) private var scaledDiameter: CGFloat = 88

    init(systemName: String, size: CGFloat = 88, scales: Bool = true) {
        self.systemName = systemName
        self.size = size
        self.scales = scales
        _scaledDiameter = ScaledMetric(wrappedValue: size, relativeTo: .largeTitle)
    }

    private var diameter: CGFloat { scales ? scaledDiameter : size }

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: diameter * 0.4, weight: .regular))
            .foregroundStyle(.primary)
            .frame(width: diameter, height: diameter)
            .background(WorkerStyle.soft, in: Circle())
            .accessibilityHidden(true)
    }
}
