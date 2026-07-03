//
//  SpellcheckedTextView.swift
//  PromptGrid
//
//  A text editor wrapping NSTextView / UITextView directly (Specification §13,
//  decision #6). SwiftUI's TextEditor silently reverts continuous spellchecking
//  to off on macOS, so we control the underlying view explicitly: spellcheck on,
//  autocorrection off (a squiggle hints; silent autocorrection of a stylized
//  prompt term is usually unwanted).
//
//  Reused in three places: the detail editor's prompt and negative-prompt fields
//  (spellcheck on), and the JSON configuration editor (spellcheck off, monospaced).
//

import SwiftUI

struct SpellcheckedTextView: View {
    @Binding var text: String
    var isSpellCheckingEnabled: Bool = true
    var isMonospaced: Bool = false

    var body: some View {
        _SpellcheckedTextView(
            text: $text,
            isSpellCheckingEnabled: isSpellCheckingEnabled,
            isMonospaced: isMonospaced
        )
        .frame(minHeight: 80)
        .overlay(
            RoundedRectangle(cornerRadius: 6).strokeBorder(.separator)
        )
    }
}

#if os(macOS)
import AppKit

private struct _SpellcheckedTextView: NSViewRepresentable {
    @Binding var text: String
    var isSpellCheckingEnabled: Bool
    var isMonospaced: Bool

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isContinuousSpellCheckingEnabled = isSpellCheckingEnabled
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false      // autocorrection off
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.font = Self.font(isMonospaced)
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.drawsBackground = false
        textView.string = text

        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text { textView.string = text }
        // Re-assert spellchecking — this is the setting that gets reverted.
        if textView.isContinuousSpellCheckingEnabled != isSpellCheckingEnabled {
            textView.isContinuousSpellCheckingEnabled = isSpellCheckingEnabled
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    static func font(_ monospaced: Bool) -> NSFont {
        monospaced
            ? .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            : .systemFont(ofSize: NSFont.systemFontSize)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let parent: _SpellcheckedTextView
        init(_ parent: _SpellcheckedTextView) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}

#else
import UIKit

private struct _SpellcheckedTextView: UIViewRepresentable {
    @Binding var text: String
    var isSpellCheckingEnabled: Bool
    var isMonospaced: Bool

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.spellCheckingType = isSpellCheckingEnabled ? .yes : .no
        textView.autocorrectionType = .no                          // autocorrection off
        textView.autocapitalizationType = .none
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.smartInsertDeleteType = .no
        textView.font = Self.font(isMonospaced)
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 6, left: 4, bottom: 6, right: 4)
        textView.text = text
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        if textView.text != text { textView.text = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    static func font(_ monospaced: Bool) -> UIFont {
        monospaced
            ? .monospacedSystemFont(ofSize: UIFont.systemFontSize, weight: .regular)
            : .preferredFont(forTextStyle: .body)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        let parent: _SpellcheckedTextView
        init(_ parent: _SpellcheckedTextView) { self.parent = parent }
        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }
    }
}
#endif
