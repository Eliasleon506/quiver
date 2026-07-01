import SwiftUI
import SwiftData

struct OnboardingFlow: View {
    @Environment(\.modelContext) private var modelContext

    @State private var step: Step = .intro
    @State private var heightFeet: Int = 5
    @State private var heightInches: Int = 10
    @State private var weightLb: Int = 170
    @State private var age: Int = 30
    @State private var gender: Gender = .preferNotToSay
    @State private var answers: SkillQuiz.Answers = .init()
    @State private var resultLevel: SkillLevel = .intermediate

    enum Step {
        case intro
        case profile
        case quiz
        case result
    }

    var body: some View {
        NavigationStack {
            switch step {
            case .intro:
                introView
            case .profile:
                ProfileQuestionsView(
                    heightFeet: $heightFeet,
                    heightInches: $heightInches,
                    weightLb: $weightLb,
                    age: $age,
                    gender: $gender,
                    onContinue: { step = .quiz }
                )
            case .quiz:
                SkillQuizView(answers: $answers) {
                    resultLevel = SkillScorer.score(answers).level
                    step = .result
                }
            case .result:
                resultView
            }
        }
    }

    private var introView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "figure.surfing")
                .font(.system(size: 72))
                .foregroundStyle(.tint)
            Text("Quiver")
                .font(.largeTitle.bold())
            Text("What board should you ride today — from the Central Coast to Costa Rica.")
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            Spacer()
            Button {
                step = .profile
            } label: {
                Text("Get started")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
    }

    private var resultView: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text("You're set up.")
                .font(.title.bold())
            Text("Skill level: \(resultLevel.displayName)")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("This drives volume sizing. You can retake the quiz from settings.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            Spacer()
            Button {
                save()
            } label: {
                Text("Continue")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
        .navigationBarBackButtonHidden(true)
    }

    private func save() {
        let totalInches = Double(heightFeet * 12 + heightInches)
        let encoder = JSONEncoder()
        let data = try? encoder.encode(answers)
        let profile = UserProfile(
            heightIn: totalInches,
            weightLb: Double(weightLb),
            age: age,
            gender: gender,
            skillLevel: resultLevel,
            quizAnswers: data
        )
        modelContext.insert(profile)
        try? modelContext.save()
    }
}
