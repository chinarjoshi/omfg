import WidgetKit
import SwiftUI

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        completion(SimpleEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        let entry = SimpleEntry(date: Date())
        let timeline = Timeline(entries: [entry], policy: .never)
        completion(timeline)
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
}

struct PhotoNoteWidgetEntryView: View {
    var entry: Provider.Entry

    var body: some View {
        if #available(iOS 17.0, *) {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "camera.fill")
                    .font(.system(size: 24, weight: .medium))
            }
            .containerBackground(.clear, for: .widget)
        } else {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "camera.fill")
                    .font(.system(size: 24, weight: .medium))
            }
        }
    }
}

@main
struct PhotoNoteWidget: Widget {
    let kind: String = "PhotoNoteWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            PhotoNoteWidgetEntryView(entry: entry)
                .widgetURL(URL(string: "omfg://photonote"))
        }
        .configurationDisplayName("Photo Note")
        .description("Quick access to photo notes")
        .supportedFamilies([.accessoryCircular])
    }
}
