import CoreGraphics

extension PreviewFrameRenderer {
    static func drawContent(layout: PreviewLayout, content: CGRect, context: CGContext) {
        switch layout {
        case .article: article(content, context)
        case .xFeed: xFeed(content, context)
        case .whatsApp: whatsApp(content, context)
        case .youtube: youtube(content, context)
        case .mail: mail(content, context)
        case .notes: notes(content, context)
        case .editor: editor(content, context)
        }
    }

    private static func article(_ content: CGRect, _ context: CGContext) {
        fill(content, PreviewPalette.lightWindow, context)
        fill(
            CGRect(x: content.minX, y: content.minY, width: 320, height: content.height),
            PreviewPalette.lightPanel,
            context
        )
        fill(
            CGRect(x: content.minX + 320, y: content.minY, width: 1, height: content.height),
            PreviewPalette.hairlineLight,
            context
        )
        fill(
            CGRect(x: 1040, y: 470, width: 480, height: 110),
            PreviewPalette.lightPanel,
            context
        )
    }

    private static func xFeed(_ content: CGRect, _ context: CGContext) {
        fill(content, PreviewPalette.window, context)
        fill(
            CGRect(x: content.minX, y: content.minY, width: 320, height: content.height),
            PreviewPalette.chrome,
            context
        )
        fill(
            CGRect(x: content.minX + 320, y: content.minY, width: 1, height: content.height),
            PreviewPalette.hairlineDark,
            context
        )
        fill(
            CGRect(x: 1020, y: content.minY, width: 1, height: content.height),
            PreviewPalette.hairlineDark,
            context
        )
        fill(CGRect(x: 380, y: 592, width: 620, height: 1), PreviewPalette.hairlineDark, context)
        fill(CGRect(x: 380, y: 952, width: 620, height: 1), PreviewPalette.hairlineDark, context)
        // The post's image: a design system card with a type sample and the color tokens.
        rounded(CGRect(x: 452, y: 360, width: 520, height: 150), 12, PreviewPalette.rgb(0x1E2329), context)
        for (index, color) in PreviewPalette.swatches.enumerated() {
            rounded(CGRect(x: 640 + CGFloat(index) * 62, y: 412, width: 46, height: 46), 10, color, context)
        }
        rounded(CGRect(x: 108, y: 640, width: 190, height: 44), 22, PreviewPalette.butter, context)
    }

    private static func whatsApp(_ content: CGRect, _ context: CGContext) {
        fill(content, PreviewPalette.whatsAppPage, context)
        fill(
            CGRect(x: content.minX, y: content.minY, width: 440, height: content.height),
            PreviewPalette.rgb(0xF7F3EC),
            context
        )
        fill(
            CGRect(x: 500, y: content.minY, width: 1, height: content.height),
            PreviewPalette.hairlineLight,
            context
        )
        fill(
            CGRect(x: 500, y: content.minY, width: 1000, height: 86),
            PreviewPalette.rgb(0xF2ECE3),
            context
        )
        fill(CGRect(x: 500, y: 169, width: 1000, height: 1), PreviewPalette.hairlineLight, context)
        rounded(CGRect(x: 140, y: 160, width: 300, height: 32), 16, PreviewPalette.lightWindow, context)
        let bubbles: [(CGRect, CGColor)] = [
            (CGRect(x: 580, y: 190, width: 520, height: 84), PreviewPalette.lightWindow),
            (CGRect(x: 900, y: 292, width: 540, height: 60), PreviewPalette.green),
            (CGRect(x: 580, y: 372, width: 520, height: 84), PreviewPalette.lightWindow),
            (CGRect(x: 940, y: 478, width: 500, height: 60), PreviewPalette.green),
            (CGRect(x: 580, y: 558, width: 520, height: 60), PreviewPalette.lightWindow),
            (CGRect(x: 880, y: 642, width: 560, height: 84), PreviewPalette.green),
        ]
        for (rect, color) in bubbles {
            rounded(rect, 14, color, context)
        }
        rounded(CGRect(x: 580, y: 872, width: 900, height: 52), 22, PreviewPalette.lightWindow, context)
        context.setFillColor(PreviewPalette.rgb(0x2FB86C))
        context.fillEllipse(in: convert(CGRect(x: 1430, y: 882, width: 30, height: 30)))
    }

    private static func youtube(_ content: CGRect, _ context: CGContext) {
        fill(content, PreviewPalette.youtubePage, context)
        fill(
            CGRect(x: content.minX, y: content.minY, width: content.width, height: 94),
            PreviewPalette.lightWindow,
            context
        )
        fill(
            CGRect(x: content.minX, y: 169, width: content.width, height: 1), PreviewPalette.hairlineLight,
            context)
        rounded(CGRect(x: 680, y: 118, width: 470, height: 42), 21, PreviewPalette.lightPanel, context)
        for (index, color) in PreviewPalette.thumbnails.enumerated() {
            let column = CGFloat(index % 3)
            let row = CGFloat(index / 3)
            let rect = CGRect(x: 110 + column * 480, y: 210 + row * 330, width: 430, height: 210)
            rounded(rect, 12, color, context)
        }
    }

    private static func mail(_ content: CGRect, _ context: CGContext) {
        fill(content, PreviewPalette.lightWindow, context)
        fill(
            CGRect(x: content.minX, y: content.minY, width: 260, height: content.height),
            PreviewPalette.lightPanel,
            context
        )
        fill(
            CGRect(x: 280, y: content.minY, width: 580, height: content.height),
            PreviewPalette.rgb(0xFAF7F1),
            context
        )
        fill(
            CGRect(x: 860, y: content.minY, width: 700, height: content.height),
            PreviewPalette.lightWindow,
            context
        )
        fill(
            CGRect(x: 280, y: content.minY, width: 1, height: content.height), PreviewPalette.hairlineLight,
            context)
        fill(
            CGRect(x: 860, y: content.minY, width: 1, height: content.height), PreviewPalette.hairlineLight,
            context)
        rounded(CGRect(x: 300, y: 190, width: 540, height: 76), 0, PreviewPalette.lightSelection, context)
        for index in 0..<5 {
            fill(
                CGRect(x: 300, y: 270 + CGFloat(index) * 78, width: 540, height: 1),
                PreviewPalette.hairlineLight,
                context
            )
        }
    }

    private static func notes(_ content: CGRect, _ context: CGContext) {
        fill(content, PreviewPalette.lightWindow, context)
        fill(
            CGRect(x: content.minX, y: content.minY, width: 280, height: content.height),
            PreviewPalette.lightPanel,
            context
        )
        fill(
            CGRect(x: 380, y: content.minY, width: 400, height: content.height),
            PreviewPalette.rgb(0xF7F3EB),
            context
        )
        fill(
            CGRect(x: 780, y: content.minY, width: 780, height: content.height),
            PreviewPalette.lightWindow,
            context
        )
        fill(
            CGRect(x: 380, y: content.minY, width: 1, height: content.height), PreviewPalette.hairlineLight,
            context)
        fill(
            CGRect(x: 780, y: content.minY, width: 1, height: content.height), PreviewPalette.hairlineLight,
            context)
        rounded(CGRect(x: 400, y: 182, width: 360, height: 52), 8, PreviewPalette.lightSelection, context)
        for index in 0..<5 {
            fill(
                CGRect(x: 400, y: 240 + CGFloat(index) * 48, width: 350, height: 1),
                PreviewPalette.hairlineLight,
                context
            )
        }
    }

    private static func editor(_ content: CGRect, _ context: CGContext) {
        fill(content, PreviewPalette.editorPage, context)
        fill(
            CGRect(x: content.minX, y: content.minY, width: 300, height: content.height),
            PreviewPalette.editorSidebar,
            context
        )
        fill(
            CGRect(x: 340, y: content.minY, width: 1, height: content.height),
            PreviewPalette.hairlineDark,
            context
        )
        fill(
            CGRect(x: content.minX, y: content.minY, width: content.width, height: 44),
            PreviewPalette.editorBar,
            context
        )
        fill(
            CGRect(x: content.minX, y: 690, width: content.width, height: 1),
            PreviewPalette.rgb(0x2B2D31),
            context
        )
        fill(
            CGRect(x: content.minX, y: 691, width: content.width, height: 270),
            PreviewPalette.terminal,
            context
        )
        rounded(CGRect(x: 380, y: 96, width: 130, height: 32), 6, PreviewPalette.editorPage, context)
        rounded(CGRect(x: 100, y: 248, width: 200, height: 28), 6, PreviewPalette.rgb(0x2A2D32), context)
    }

}
