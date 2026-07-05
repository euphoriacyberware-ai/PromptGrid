//
//  SeedPickerPopover.swift
//  PromptGrid
//
//  "+ New run" popover (Specification §7): a Random/Fixed seed toggle. Random
//  shows a freshly-rolled, visible number (so it's recorded even in random
//  mode); Fixed lets you type a value or re-roll with the dice button. The
//  client always owns the seed (§2.3).
//

import SwiftUI
import PromptGridCore

struct SeedPickerPopover: View {
    @Binding var isPresented: Bool
    /// (seed, seedWasRandom)
    let onCreate: (Int, Bool) -> Void

    @State private var isRandom = true
    @State private var randomSeed = SeedGenerator.random()
    @State private var fixedSeedText = ""

    private var parsedFixedSeed: Int? {
        guard let value = Int(fixedSeedText), SeedGenerator.range.contains(value) else { return nil }
        return value
    }

    private var canCreate: Bool { isRandom || parsedFixedSeed != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Run").font(.headline)

            Picker("Seed", selection: $isRandom) {
                Text("Random").tag(true)
                Text("Fixed").tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack {
                if isRandom {
                    Text("\(randomSeed)")
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                    Spacer()
                    Button { randomSeed = SeedGenerator.random() } label: {
                        Image(systemName: "die.face.5")
                    }
                    .buttonStyle(.borderless)
                    .help("Roll a new seed")
                    .accessibilityLabel("Roll a new seed")
                } else {
                    TextField("Seed", text: $fixedSeedText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
#if os(iOS)
                        .keyboardType(.numberPad)
#endif
                    Button { fixedSeedText = String(SeedGenerator.random()) } label: {
                        Image(systemName: "die.face.5")
                    }
                    .buttonStyle(.borderless)
                    .help("Roll a new seed")
                    .accessibilityLabel("Roll a new seed")
                }
            }

            if !isRandom {
                Text("0 – \(SeedGenerator.range.upperBound)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button("Create Run") { create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canCreate)
            }
        }
        .padding()
        .frame(width: 300)
    }

    private func create() {
        let seed = isRandom ? randomSeed : (parsedFixedSeed ?? randomSeed)
        onCreate(seed, isRandom)
        isPresented = false
    }
}
