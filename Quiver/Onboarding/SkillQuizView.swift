import SwiftUI

struct SkillQuizView: View {
    @Binding var answers: SkillQuiz.Answers
    var onComplete: () -> Void

    @State private var pageIndex: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            ProgressView(value: Double(answers.completedCount), total: Double(SkillQuiz.Q.allCases.count))
                .padding(.horizontal)
                .padding(.top, 8)

            TabView(selection: $pageIndex) {
                ForEach(Array(SkillQuiz.Q.allCases.enumerated()), id: \.element) { idx, q in
                    QuestionPage(question: q, selectedIndex: bindingFor(q: q), pageIndex: idx, total: SkillQuiz.Q.allCases.count)
                        .tag(idx)
                        .padding(.horizontal)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .indexViewStyle(.page(backgroundDisplayMode: .never))

            HStack {
                Button("Back") { pageIndex = max(0, pageIndex - 1) }
                    .disabled(pageIndex == 0)
                Spacer()
                if pageIndex < SkillQuiz.Q.allCases.count - 1 {
                    Button("Next") { pageIndex = min(SkillQuiz.Q.allCases.count - 1, pageIndex + 1) }
                        .buttonStyle(.borderedProminent)
                        .disabled(currentAnswerMissing)
                } else {
                    Button("Done") { onComplete() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!answers.isComplete)
                }
            }
            .padding()
        }
        .navigationTitle("Skill quiz")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var currentAnswerMissing: Bool {
        guard pageIndex < SkillQuiz.Q.allCases.count else { return true }
        let q = SkillQuiz.Q.allCases[pageIndex]
        return answers.values[q.rawValue] == nil
    }

    private func bindingFor(q: SkillQuiz.Q) -> Binding<Int?> {
        Binding(
            get: { answers.values[q.rawValue] },
            set: { newValue in
                if let v = newValue {
                    answers.values[q.rawValue] = v
                } else {
                    answers.values.removeValue(forKey: q.rawValue)
                }
            }
        )
    }
}

private struct QuestionPage: View {
    let question: SkillQuiz.Q
    @Binding var selectedIndex: Int?
    let pageIndex: Int
    let total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("\(pageIndex + 1) of \(total)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(question.prompt)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 10) {
                ForEach(Array(question.options.enumerated()), id: \.offset) { idx, opt in
                    Button {
                        selectedIndex = idx
                    } label: {
                        HStack {
                            Text(opt.0)
                            Spacer()
                            if selectedIndex == idx {
                                Image(systemName: "checkmark.circle.fill")
                            }
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(selectedIndex == idx ? Color.accentColor.opacity(0.15) : Color(.secondarySystemBackground))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer()
        }
        .padding(.vertical, 12)
    }
}
