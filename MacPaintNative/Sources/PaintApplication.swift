import AppKit

final class PaintApplication: NSApplication {
    var modalEventFilter: ((NSEvent) -> Bool)?

    override func nextEvent(matching mask: NSEvent.EventTypeMask, until expiration: Date?,
                            inMode mode: RunLoop.Mode, dequeue flag: Bool) -> NSEvent? {
        while let event = super.nextEvent(matching: mask, until: expiration, inMode: mode, dequeue: flag) {
            // The original MyFilter handles canvas clicks before ModalDialog
            // rejects events outside the editor. AppKit's local monitors run later.
            if flag && modalEventFilter?(event) == true { continue }
            return event
        }
        return nil
    }
}
