import SwiftUI

struct TimelineStepView: View {
    let step: TimelineStep

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 0) {
                Circle()
                    .fill(step.isComplete ? Color.green : Color.gray)
                    .frame(width: 10, height: 10)
                Rectangle()
                    .fill(Color.separator)
                    .frame(width: 1)
                    .opacity(0.5)
            }
            .frame(width: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(step.title)
                    .font(.subheadline.weight(.semibold))
                Text(step.date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

#Preview("Light") {
    TimelineStepView(step: TimelineStep(title: "Submitted", date: "Apr 18, 2026", isComplete: true))
        .padding()
        .background(DesignSystemPalette.windowBackground)
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    TimelineStepView(step: TimelineStep(title: "Draft", date: "Apr 16, 2026", isComplete: false))
        .padding()
        .background(DesignSystemPalette.windowBackground)
        .preferredColorScheme(.dark)
}
