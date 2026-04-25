import SwiftUI

/// Full emoji browser presented as a sheet. Two-tier nav: a horizontal tab strip
/// of category icons, and a scrollable grid below. The "Custom" tab (if there are
/// any resolved custom emojis) is shown first, followed by the static unicode
/// categories from `EmojiData.categories`.
///
/// Three operating modes via `Mode`:
/// - `.pickForReaction` — selecting an emoji fires `onPick` (used by the post-card heart "+").
/// - `.pickForQuickList` — adds the emoji to the user's quick-reactions list and dismisses.
/// - `.pickForDirectEmojiList` — fires `onPickCustom` only for custom emojis (used for "add
///    to my emojis" flows that need shortcode + URL).
struct EmojiLibrarySheet: View {
    enum Mode {
        case pickForReaction((PickedEmoji) -> Void)
        case pickForQuickList
        case pickForDirectEmojiList((String, String) -> Void)
    }

    let mode: Mode

    @Environment(\.dismiss) private var dismiss
    @State private var emojiRepo = EmojiRepository.shared
    @ObservedObject private var emojiCache = EmojiImageCache.shared
    @State private var selectedTab: String = ""

    private var hasCustom: Bool { !emojiRepo.resolvedCustomMap.isEmpty }

    private var tabs: [(id: String, label: String)] {
        var out: [(String, String)] = []
        if hasCustom { out.append(("custom", "✨")) }
        for c in EmojiData.categories { out.append((c.name, c.icon)) }
        return out
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                tabStrip
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            if hasCustom {
                                customSection
                                    .id("custom")
                            }
                            ForEach(EmojiData.categories, id: \.name) { cat in
                                categorySection(cat)
                                    .id(cat.name)
                            }
                        }
                        .padding(16)
                    }
                    .onChange(of: selectedTab) { _, new in
                        guard !new.isEmpty else { return }
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo(new, anchor: .top)
                        }
                    }
                }
            }
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                if selectedTab.isEmpty { selectedTab = tabs.first?.id ?? "" }
                // Prime image cache for visible custom emojis.
                for url in emojiRepo.resolvedCustomMap.values {
                    emojiCache.ensureLoaded(url)
                }
            }
        }
    }

    private var navTitle: String {
        switch mode {
        case .pickForReaction: return "Add reaction"
        case .pickForQuickList: return "Add to quick reactions"
        case .pickForDirectEmojiList: return "Pick custom emoji"
        }
    }

    // MARK: - Tab strip

    private var tabStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tabs, id: \.id) { tab in
                    Button {
                        selectedTab = tab.id
                    } label: {
                        Text(tab.label)
                            .font(.system(size: 22))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(selectedTab == tab.id
                                          ? Color.primary.opacity(0.10)
                                          : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Custom section

    private var customSection: some View {
        let groupedByPack = packGrouping()
        return VStack(alignment: .leading, spacing: 16) {
            Text("Custom")
                .font(.headline)
            ForEach(groupedByPack, id: \.title) { group in
                VStack(alignment: .leading, spacing: 6) {
                    Text(group.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    customGrid(group.emojis)
                }
            }
        }
    }

    private struct CustomGroup {
        let title: String
        let emojis: [(shortcode: String, url: String)]
    }

    private func packGrouping() -> [CustomGroup] {
        var out: [CustomGroup] = []
        if !emojiRepo.directEmojis.isEmpty {
            out.append(CustomGroup(
                title: "My emojis",
                emojis: emojiRepo.directEmojis.map { ($0.shortcode, $0.url) }
            ))
        }
        for addr in emojiRepo.referencedPackAddrs {
            guard let pack = emojiRepo.resolvedPacks[addr], !pack.emojis.isEmpty else { continue }
            out.append(CustomGroup(
                title: pack.title ?? pack.dTag,
                emojis: pack.emojis.map { ($0.shortcode, $0.url) }
            ))
        }
        return out
    }

    private func customGrid(_ items: [(shortcode: String, url: String)]) -> some View {
        let cell: CGFloat = 44
        let cols = Array(repeating: GridItem(.fixed(cell), spacing: 8), count: 6)
        return LazyVGrid(columns: cols, alignment: .leading, spacing: 8) {
            ForEach(items, id: \.shortcode) { item in
                Button {
                    handleCustomPick(shortcode: item.shortcode, url: item.url)
                } label: {
                    customImageCell(url: item.url, shortcode: item.shortcode, size: cell)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func customImageCell(url: String, shortcode: String, size: CGFloat) -> some View {
        if let img = emojiCache.image(for: url) {
            Image(uiImage: img)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size - 4, height: size - 4)
        } else {
            Color.clear
                .frame(width: size, height: size)
                .overlay(
                    Text(":\(shortcode):")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.horizontal, 2)
                )
                .onAppear { emojiCache.ensureLoaded(url) }
        }
    }

    // MARK: - Category section

    private func categorySection(_ cat: EmojiCategory) -> some View {
        let cell: CGFloat = 40
        let cols = Array(repeating: GridItem(.fixed(cell), spacing: 6), count: 7)
        return VStack(alignment: .leading, spacing: 8) {
            Text(cat.name)
                .font(.headline)
            LazyVGrid(columns: cols, alignment: .leading, spacing: 6) {
                ForEach(cat.emojis, id: \.self) { e in
                    Button {
                        handleUnicodePick(e)
                    } label: {
                        Text(e)
                            .font(.system(size: 28))
                            .frame(width: cell, height: cell)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Pick handlers

    private func handleUnicodePick(_ emoji: String) {
        switch mode {
        case .pickForReaction(let cb):
            cb(.unicode(emoji))
        case .pickForQuickList:
            emojiRepo.addToQuickList(emoji)
            dismiss()
        case .pickForDirectEmojiList:
            // Direct-emoji list only accepts custom shortcodes.
            break
        }
    }

    private func handleCustomPick(shortcode: String, url: String) {
        switch mode {
        case .pickForReaction(let cb):
            cb(.custom(shortcode: shortcode, url: url))
        case .pickForQuickList:
            emojiRepo.addToQuickList(":\(shortcode):")
            dismiss()
        case .pickForDirectEmojiList(let cb):
            cb(shortcode, url)
            dismiss()
        }
    }
}
