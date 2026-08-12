import SwiftUI

struct WatchHomeView: View {
    @ObservedObject var model: WatchGlucoseViewModel

    var body: some View {
        Group {
            if let payload = model.payload {
                VStack(spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(payload.formattedValue())
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(WatchGlucoseStyle.color(for: payload))
                            .minimumScaleFactor(0.65)
                        Text(payload.trendSymbol)
                            .font(.title2).bold()
                    }
                    HStack {
                        Text(payload.formattedDelta()).font(.headline)
                        Spacer()
                        Text(payload.readingDate, style: .time).font(.caption)
                    }
                    .foregroundStyle(.secondary)
                    WatchGlucoseChart(payload: payload, hours: 3)
                        .frame(minHeight: 58)
                    HStack {
                        if let iob = payload.iob { Text(String(format: "IOB %.1f", iob)) }
                        Spacer()
                        Text(WatchGlucoseStyle.unit(for: payload))
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
            } else {
                ContentUnavailableView("No glucose data", systemImage: "drop")
            }
        }
        .onAppear { model.refresh() }
    }
}
