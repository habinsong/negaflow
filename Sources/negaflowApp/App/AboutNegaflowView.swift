import AppKit
import Chromabase
import SwiftUI

@MainActor
struct AboutNegaflowView: View {
    static let windowID = "about-negaflow"
    static let contentSize = CGSize(width: 460, height: 330)

    @ObservedObject var model: AppModel

    private let version: String
    private let copyright: String?
    private let applicationIcon: NSImage

    init(
        model: AppModel,
        bundle: Bundle = .main,
        applicationIcon: NSImage? = nil
    ) {
        self.model = model
        version = NegaflowProductVersion.applicationVersion(in: bundle)
        copyright = bundle.object(
            forInfoDictionaryKey: "NSHumanReadableCopyright"
        ) as? String
        self.applicationIcon = applicationIcon
            ?? NSApplication.shared.applicationIconImage
    }

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: applicationIcon)
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
                .padding(.bottom, 12)

            Text(verbatim: "negaflow")
                .font(.title)
                .fontWeight(.semibold)
                .padding(.bottom, 10)

            Text(verbatim: model.text(.aboutAnniversaryMessage))
                .font(.callout)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 390)
                .padding(.bottom, 10)

            Text(verbatim: "\(model.text(.aboutVersionLabel)) \(version)")
                .font(.callout)
                .foregroundStyle(.secondary)

            if let copyright, !copyright.isEmpty {
                Text(verbatim: copyright)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 12)
            }
        }
        .frame(
            width: Self.contentSize.width,
            height: Self.contentSize.height
        )
    }
}
