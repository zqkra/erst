import CoreGraphics
import Foundation

extension PreviewContent {
    static func xFeed(_ variant: Int) -> [PreviewLineSpec] {
        let navigation = [
            "Home", "Explore", "Notifications", "Messages", "Bookmarks", "Jobs", "Communities", "Profile",
            "More",
        ]
        var specs = navigation.enumerated().map { index, item in
            line(item, 110, 180 + CGFloat(index) * 46, 190, 18)
        }
        specs += [
            line("Home", 380, 112, 130, 30),
            line("For you", 380, 162, 80, 16),
            line("Following", 480, 162, 100, 16),
            line("Subscribe to Premium", 1080, 176, 340, 18),
            line("What's happening", 1080, 242, 340, 26),
            line("Design systems", 1080, 288, 300, 18),
            line("36.4K posts", 1080, 310, 240, 14),
            line("Screen memory", 1080, 356, 300, 18),
            line("12.1K posts", 1080, 378, 240, 14),
            line("Local first", 1080, 424, 300, 18),
            line("8,204 posts", 1080, 446, 240, 14),
            line("Show more", 1080, 492, 240, 14),
            // The type sample on the post's design system card.
            line("Aa", 486, 402, 96, 66),
        ]
        for (index, post) in xPosts(variant).enumerated() {
            let top = 230 + CGFloat(index) * 360
            specs += [
                line(post.name, 452, top, 160, 17),
                line(post.handle, 620, top, 150, 17),
                line(post.time, 780, top, 60, 14),
                line(post.lines[0], 452, top + 32, 560, 19),
                line(post.lines[1], 452, top + 58, 540, 19),
                line(post.lines[2], 452, top + 84, 460, 19),
                line("18 replies   64 reposts   420 likes", 452, top + 118, 460, 13),
            ]
        }
        return specs
    }

    private struct Post {
        let name: String
        let handle: String
        let time: String
        let lines: [String]
    }

    private static func xPosts(_ variant: Int) -> [Post] {
        let groups: [[Post]] = [
            [
                Post(
                    name: "Maya Chen", handle: "@mayachen", time: "2h",
                    lines: [
                        "The design system is live.",
                        "Spacing, type, and color now live in one place.",
                        "Every screen speaks the same language.",
                    ]
                ),
                Post(
                    name: "Noah Park", handle: "@noahpark", time: "4h",
                    lines: [
                        "Spent the morning deleting settings.",
                        "Fewer switches, clearer defaults.",
                        "The best preference is the one you never open.",
                    ]
                ),
            ],
            [
                Post(
                    name: "Lea Fischer", handle: "@leafischer", time: "1h",
                    lines: [
                        "A quiet app is not an empty app.",
                        "It only asks for attention when it has something to say.",
                        "That is the whole design rule.",
                    ]
                ),
                Post(
                    name: "Maya Chen", handle: "@mayachen", time: "3h",
                    lines: [
                        "Two weeks of screen memory.",
                        "The feature I use most is yesterday.",
                        "Not search. Just looking back.",
                    ]
                ),
            ],
            [
                Post(
                    name: "Erst", handle: "@erstapp", time: "38m",
                    lines: [
                        "The new timeline dock is in.",
                        "Drag the strip, step with the arrows, press Escape.",
                        "Keyboard actions never animate.",
                    ]
                ),
                Post(
                    name: "Noah Park", handle: "@noahpark", time: "2h",
                    lines: [
                        "Search now highlights the line you saw.",
                        "Not the page. The exact sentence.",
                        "Try it with design system.",
                    ]
                ),
            ],
        ]
        return groups[variant % groups.count]
    }

    static func whatsApp(_ variant: Int) -> [PreviewLineSpec] {
        let chats = [
            ("Maya Chen", "The design system docs are ready", "09:41"),
            ("Design crew", "Noah: the spacing scale is in", "09:22"),
            ("Dad", "Call me when you have a minute", "08:55"),
            ("Noah Park", "Sending the review tonight", "Yesterday"),
            ("Book club", "Lea: chapter six for Thursday", "Yesterday"),
            ("Lea Fischer", "That inspector radius looks right", "Mon"),
        ]
        var specs: [PreviewLineSpec] = [
            line("Chats", 140, 122, 130, 24),
            line("All", 430, 126, 60, 16),
        ]
        for (index, chat) in chats.enumerated() {
            let y = 218 + CGFloat(index) * 72
            specs += [
                line(chat.0, 150, y, 230, 17),
                line(chat.2, 430, y, 70, 13),
                line(chat.1, 150, y + 24, 320, 14),
            ]
        }
        let conversation = whatsAppConversation(variant)
        let slots: [(CGFloat, CGFloat, CGFloat)] = [
            (600, 206, 470), (600, 230, 440),
            (918, 306, 500),
            (600, 388, 470), (600, 412, 440),
            (958, 492, 460),
            (600, 572, 470),
            (898, 656, 520), (898, 680, 480),
        ]
        specs.append(line(conversation.0, 580, 118, 250, 22))
        specs.append(line("online", 580, 144, 110, 13))
        for (index, message) in conversation.1.enumerated() where index < slots.count {
            let slot = slots[index]
            specs.append(line(message, slot.0, slot.1, slot.2, 16))
        }
        specs.append(line("Message", 610, 888, 160, 18))
        return specs
    }

    private static func whatsAppConversation(_ variant: Int) -> (String, [String]) {
        let conversations: [(String, [String])] = [
            (
                "Maya Chen",
                [
                    "The design system docs are ready for review.",
                    "I moved spacing and type onto one page.",
                    "Can you look before Friday?",
                    "Yes. Sending notes tonight.",
                    "The settings screen feels calmer.",
                    "Fewer switches, clearer defaults.",
                    "Good. The inspector still has the old radius.",
                    "Changed it to 26. Matches the window.",
                    "Perfect. Shipping the panel today.",
                ]
            ),
            (
                "Design crew",
                [
                    "The spacing scale is in the build.",
                    "Every screen uses the same four steps.",
                    "The inspector still needs a smaller radius.",
                    "I will fix it after lunch.",
                    "Search highlights look right now.",
                    "Nice. Let's ship the panel today.",
                    "One more thing. The empty state needs an action.",
                    "Added. It opens search with the date filled in.",
                    "Then we are done with this pass.",
                ]
            ),
        ]
        return conversations[variant % conversations.count]
    }

}
