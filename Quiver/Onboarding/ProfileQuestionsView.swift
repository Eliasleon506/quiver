import SwiftUI

struct ProfileQuestionsView: View {
    @Binding var heightFeet: Int
    @Binding var heightInches: Int
    @Binding var weightLb: Int
    @Binding var age: Int
    @Binding var gender: Gender
    var onContinue: () -> Void

    var body: some View {
        Form {
            Section("Body") {
                HeightStepper(feet: $heightFeet, inches: $heightInches)
                Stepper("Weight: \(weightLb) lb", value: $weightLb, in: 80...350, step: 1)
                Stepper("Age: \(age)", value: $age, in: 10...90)
            }
            Section("Gender") {
                Picker("Gender", selection: $gender) {
                    ForEach(Gender.allCases) { g in
                        Text(g.displayName).tag(g)
                    }
                }
                .pickerStyle(.menu)
            }
            Section {
                Button {
                    onContinue()
                } label: {
                    Text("Continue to skill quiz")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .navigationTitle("About you")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Shared feet + inches height control (combines the old split steppers into one clean unit).
/// `feet` 4–7, `inches` 0–11 — used by onboarding and the profile editor.
struct HeightStepper: View {
    @Binding var feet: Int
    @Binding var inches: Int

    var body: some View {
        Stepper("Height: \(feet)' \(inches)\"", value: $feet, in: 4...7)
        Stepper(value: $inches, in: 0...11) {
            HStack {
                Text("Inches")
                Spacer()
                Text("\(inches)\"").foregroundStyle(.secondary)
            }
        }
    }
}

/// Post-onboarding profile editor (Phase 3) — body metrics + skill + owned-wetsuit toggles, reachable
/// from the gear in the root toolbar. Edits the single live `UserProfile`.
struct ProfileEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let profile: UserProfile

    @State private var heightFeet: Int
    @State private var heightInches: Int
    @State private var weightLb: Int
    @State private var age: Int
    @State private var gender: Gender
    @State private var skill: SkillLevel
    @State private var hasSpringSuit: Bool
    @State private var has32: Bool
    @State private var has43: Bool
    @State private var hasHoodBooties: Bool
    @State private var geminiKey: String

    init(profile: UserProfile) {
        self.profile = profile
        _heightFeet = State(initialValue: Int(profile.heightIn) / 12)
        _heightInches = State(initialValue: Int(profile.heightIn) % 12)
        _weightLb = State(initialValue: Int(profile.weightLb))
        _age = State(initialValue: profile.age)
        _gender = State(initialValue: profile.gender)
        _skill = State(initialValue: profile.skillLevel)
        _hasSpringSuit = State(initialValue: profile.hasSpringSuit)
        _has32 = State(initialValue: profile.has32)
        _has43 = State(initialValue: profile.has43)
        _hasHoodBooties = State(initialValue: profile.hasHoodBooties)
        _geminiKey = State(initialValue: KeychainStore.geminiKey ?? "")
    }

    var body: some View {
        Form {
            Section("Body") {
                HeightStepper(feet: $heightFeet, inches: $heightInches)
                Stepper("Weight: \(weightLb) lb", value: $weightLb, in: 80...350, step: 1)
                Stepper("Age: \(age)", value: $age, in: 10...90)
                Picker("Gender", selection: $gender) {
                    ForEach(Gender.allCases) { g in Text(g.displayName).tag(g) }
                }
            }
            Section("Skill") {
                Picker("Skill level", selection: $skill) {
                    ForEach(SkillLevel.allCases) { s in Text(s.displayName).tag(s) }
                }
            }
            Section {
                Toggle("Spring suit", isOn: $hasSpringSuit)
                Toggle("3/2 full suit", isOn: $has32)
                Toggle("4/3 full suit", isOn: $has43)
                Toggle("Hood + booties", isOn: $hasHoodBooties)
            } header: {
                Text("Owned wetsuits")
            } footer: {
                Text("We size for the suit the water calls for, matched against what you own.")
            }

            Section {
                SecureField("Paste your Gemini API key", text: $geminiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !geminiKey.isEmpty {
                    Button("Clear key", role: .destructive) { geminiKey = "" }
                }
            } header: {
                Text("Gemini AI (optional)")
            } footer: {
                Text("Without a key the app uses its built-in rule engine. Add your own key to enable AI-refined picks — get a free one at aistudio.google.com. Stored securely in your device Keychain; never uploaded or shared.")
            }
        }
        .navigationTitle("Your profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { save() }.fontWeight(.semibold)
            }
        }
    }

    private func save() {
        profile.heightIn = Double(heightFeet * 12 + heightInches)
        profile.weightLb = Double(weightLb)
        profile.age = age
        profile.gender = gender
        profile.skillLevel = skill
        profile.hasSpringSuit = hasSpringSuit
        profile.has32 = has32
        profile.has43 = has43
        profile.hasHoodBooties = hasHoodBooties
        profile.updatedAt = Date()
        try? modelContext.save()
        KeychainStore.geminiKey = geminiKey   // blank ⇒ deletes the stored key
        dismiss()
    }
}
