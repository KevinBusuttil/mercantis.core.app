import SwiftUI

struct InspectorPane: View {
    let title: String
    let linkedTitle: String

    private let statusSteps: [TimelineStep] = [
        TimelineStep(title: "Draft", date: "Apr 14, 2026", isComplete: true),
        TimelineStep(title: "Submitted", date: "Apr 16, 2026", isComplete: true),
        TimelineStep(title: "Approved", date: "Pending", isComplete: false)
    ]

    private let timelineEvents: [TimelineEvent] = [
        TimelineEvent(author: "John Doe", text: "Validated record metadata and status.", date: "Apr 16"),
        TimelineEvent(author: "Anna Lee", text: "Requested workflow routing confirmation.", date: "Apr 17")
    ]

    private let linkedItems: [LinkedResource] = [
        LinkedResource(title: "WRK-REC-2026-0022", subtitle: "Workspace Record"),
        LinkedResource(title: "RPT-2026-0119", subtitle: "Report")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    ForEach(["person", "list.bullet", "rectangle.split.3x1", "sidebar.right"], id: \.self) { icon in
                        Button {
                        } label: {
                            Image(systemName: icon)
                        }
                        .buttonStyle(.borderless)
                    }
                    Spacer()
                }

                Text("isPresented · ⌘I Toggle")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.quaternary, in: Capsule())

                Text(title)
                    .font(.title3.weight(.bold))

                SectionCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Status History")
                            .font(.headline)
                        ForEach(statusSteps) { step in
                            TimelineStepView(step: step)
                        }
                    }
                }

                SectionCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Timeline")
                            .font(.headline)
                        ForEach(timelineEvents) { event in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(event.author)
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text(event.date)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text(event.text)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                SectionCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Connections")
                            .font(.headline)
                        ForEach(linkedItems) { item in
                            HStack {
                                Label(item.title, systemImage: "doc.text")
                                    .font(.subheadline)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.tertiary)
                            }
                            Text(item.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                SectionCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(linkedTitle)
                            .font(.headline)
                        ForEach(linkedItems) { item in
                            LabeledContent(item.title, value: item.subtitle)
                        }
                        .font(.footnote)
                    }
                }
            }
            .padding(16)
        }
        .background(.ultraThinMaterial)
    }
}

#Preview("Light") {
    InspectorPane(title: "Record Details & Activity", linkedTitle: "Linked Resources")
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    InspectorPane(title: "Component Details & Deployment", linkedTitle: "Linked Code")
        .preferredColorScheme(.dark)
}
