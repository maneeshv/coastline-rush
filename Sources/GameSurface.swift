import SwiftUI
import SceneKit

/// SceneKit may call its delegate off the main thread. Keep game/UI ownership
/// on main and coalesce callbacks instead of allowing frames to queue up.
final class GameFrameRelay: NSObject, SCNSceneRendererDelegate {
    weak var controller: GameController?
    weak var view: SCNView?
    private let lock = NSLock()
    private var pending = false

    func attach(_ view: SCNView, controller: GameController) {
        self.view = view
        self.controller = controller
        view.delegate = self
        controller.onRenderSettingsChanged = { [weak self] in self?.refresh() }
        controller.world.onWorldPrepared = { [weak view] node in
            view?.prepare([node], completionHandler: nil)
        }
        refresh()
    }

    func refresh() {
        guard let view, let controller else { return }
        let active = controller.shouldAnimateScene
        if view.isPlaying != active { view.isPlaying = active }
        if view.rendersContinuously != active { view.rendersContinuously = active }
        if view.preferredFramesPerSecond != controller.preferredFrameRate { view.preferredFramesPerSecond = controller.preferredFrameRate }
        let antialiasing: SCNAntialiasingMode = controller.effectiveQuality == .ultra ? .multisampling4X : controller.effectiveQuality == .balanced ? .multisampling2X : .none
        if view.antialiasingMode != antialiasing { view.antialiasingMode = antialiasing }
        if !active {
            #if os(iOS)
            view.setNeedsDisplay()
            #else
            view.needsDisplay = true
            #endif
        }
    }

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        lock.lock()
        guard !pending else { lock.unlock(); return }
        pending = true
        lock.unlock()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.controller?.renderFrame(at: time)
            self.lock.lock()
            self.pending = false
            self.lock.unlock()
        }
    }
}

#if os(iOS)
import UIKit

struct GameSurface: UIViewRepresentable {
    let controller: GameController
    let controlMode: RunMode
    func makeUIView(context: Context) -> TouchGameView {
        let view = TouchGameView()
        view.controller = controller
        view.installTouchControls()
        configure(view)
        return view
    }
    func updateUIView(_ view: TouchGameView, context: Context) { view.updateControlDescriptions(); view.frameRelay.refresh() }
    private func configure(_ view: TouchGameView) {
        view.scene = controller.world.scene
        view.pointOfView = controller.world.camera
        view.frameRelay.attach(view, controller: controller)
        view.backgroundColor = .init(red: 0.03, green: 0.06, blue: 0.12, alpha: 1)
    }
}

final class TouchGameView: SCNView {
    weak var controller: GameController?
    let frameRelay = GameFrameRelay()
    private var lastGestureAction = 0.0
    private var waterOrigin = 0.0
    private var waterVerticalAnchor = 0.0
    private var describedMode: RunMode?
    private var describedWater: Bool?
    override var canBecomeFirstResponder: Bool { true }
    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.height > 0 { controller?.world.resize(aspect: Double(bounds.width / bounds.height)) }
    }
    override func didMoveToWindow() { super.didMoveToWindow(); becomeFirstResponder() }

    func installTouchControls() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        addGestureRecognizer(pan)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.require(toFail: pan)
        addGestureRecognizer(doubleTap)
        isAccessibilityElement = true
        updateControlDescriptions()
    }
    func updateControlDescriptions() {
        let mode = controller.map { $0.run.phase == .menu ? $0.selectedMode : $0.run.mode } ?? .endless
        let water = controller.map { $0.run.phase == .menu ? $0.selectedMode == .jetSki : $0.run.isWaterTraversal } ?? false
        guard describedMode != mode || describedWater != water else { return }
        describedMode = mode
        describedWater = water
        accessibilityLabel = water ? (mode == .odyssey ? "Tidal channel jet ski course" : "Harbor jet ski course") : mode == .odyssey ? "Portal Odyssey course" : "Coastal race track"
        accessibilityHint = water ? "Swipe sideways to steer, down to brake, up to trick after a ramp. Double-tap to boost." : mode == .odyssey ? "Swipe sideways to steer, up to jump, down to roll. At the portal, jump to travel to the next world." : "Swipe to run, or use the custom actions to change lane, jump, roll, and activate a board."
        accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "Move left", target: self, selector: #selector(accessibleLeft)),
            UIAccessibilityCustomAction(name: "Move right", target: self, selector: #selector(accessibleRight)),
            UIAccessibilityCustomAction(name: water ? "Air trick" : "Jump", target: self, selector: #selector(accessibleJump)),
            UIAccessibilityCustomAction(name: water ? "Brake" : "Roll", target: self, selector: #selector(accessibleRoll)),
            UIAccessibilityCustomAction(name: water ? "Boost" : "Ride board", target: self, selector: #selector(accessibleBoard)),
            UIAccessibilityCustomAction(name: "Use artifact ability", target: self, selector: #selector(accessibleAbility))
        ]
    }
    @objc private func accessibleLeft() -> Bool { accessibleAction(.left) }
    @objc private func accessibleRight() -> Bool { accessibleAction(.right) }
    @objc private func accessibleJump() -> Bool { accessibleAction(.jump) }
    @objc private func accessibleRoll() -> Bool { accessibleAction(.roll) }
    @objc private func accessibleBoard() -> Bool { accessibleAction(.board) }
    @objc private func accessibleAbility() -> Bool { accessibleAction(.ability) }
    private func accessibleAction(_ action: RunnerAction) -> Bool {
        guard controller?.run.phase == .running else { return false }
        controller?.perform(action)
        return true
    }
    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        if gesture.state == .began {
            lastGestureAction = 0
            waterOrigin = controller?.run.lateral ?? 0
            waterVerticalAnchor = 0
        }
        if gesture.state == .cancelled || gesture.state == .failed || gesture.state == .ended {
            controller?.steerWater(nil)
        }
        guard gesture.state == .began || gesture.state == .changed || gesture.state == .ended else { return }
        let translation = gesture.translation(in: self)
        let dx = translation.x, dy = translation.y
        let sensitivity = controller?.profile.swipeSensitivity ?? 1
        let now = ProcessInfo.processInfo.systemUptime
        if controller?.run.isWaterTraversal == true {
            if gesture.state != .ended {
                controller?.steerWater(waterOrigin + Double(dx) * sensitivity / max(90, Double(bounds.width) * 0.35))
            }
            let vertical = Double(dy) - waterVerticalAnchor
            if abs(vertical) >= 30 / sensitivity, now - lastGestureAction >= 0.12 {
                controller?.perform(vertical < 0 ? .jump : .roll)
                waterVerticalAnchor = Double(dy)
                lastGestureAction = now
            }
            return
        }
        guard max(abs(dx), abs(dy)) >= 24 / sensitivity, now - lastGestureAction >= 0.08 else { return }
        lastGestureAction = now
        gesture.setTranslation(.zero, in: self)
        if abs(dx) > abs(dy) { controller?.perform(dx < 0 ? .left : .right) }
        else { controller?.perform(dy < 0 ? .jump : .roll) }
    }
    @objc private func handleDoubleTap() { controller?.perform(.board) }
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false
        for press in presses {
            guard let key = press.key else { continue }
            switch key.keyCode {
            case .keyboardLeftArrow, .keyboardA: controller?.perform(.left); handled = true
            case .keyboardRightArrow, .keyboardD: controller?.perform(.right); handled = true
            case .keyboardUpArrow, .keyboardW, .keyboardSpacebar: controller?.perform(.jump); handled = true
            case .keyboardDownArrow, .keyboardS: controller?.perform(.roll); handled = true
            case .keyboardB: controller?.perform(.board); handled = true
            case .keyboardE: controller?.perform(.ability); handled = true
            case .keyboardEscape: controller?.togglePause(); handled = true
            default: break
            }
        }
        if !handled { super.pressesBegan(presses, with: event) }
    }
}
#else
import AppKit

struct GameSurface: NSViewRepresentable {
    let controller: GameController
    let controlMode: RunMode
    func makeNSView(context: Context) -> DesktopGameView {
        let view = DesktopGameView()
        view.controller = controller
        view.scene = controller.world.scene
        view.pointOfView = controller.world.camera
        view.frameRelay.attach(view, controller: controller)
        view.backgroundColor = .init(red: 0.03, green: 0.06, blue: 0.12, alpha: 1)
        return view
    }
    func updateNSView(_ view: DesktopGameView, context: Context) { view.frameRelay.refresh() }
    static func dismantleNSView(_ view: DesktopGameView, coordinator: ()) { view.removeMonitor() }
}

final class DesktopGameView: SCNView {
    weak var controller: GameController?
    let frameRelay = GameFrameRelay()
    private var monitor: Any?
    private var dragOrigin: NSPoint?
    private var lastGestureAction = 0.0
    private var waterOrigin = 0.0
    private var waterVerticalAnchor = 0.0
    override var acceptsFirstResponder: Bool { true }
    override func layout() {
        super.layout()
        if bounds.height > 0 { controller?.world.resize(aspect: Double(bounds.width / bounds.height)) }
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeMonitor()
        guard window != nil else { return }
        window?.makeFirstResponder(self)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window == self.window, !event.modifierFlags.contains(.command), self.controller?.panel == nil else { return event }
            return self.handleKey(event) ? nil : event
        }
    }
    func removeMonitor() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil }
    deinit { removeMonitor() }
    private func handleKey(_ event: NSEvent) -> Bool {
        guard let controller else { return false }
        if event.isARepeat { return true }
        switch event.keyCode {
        case 123, 0: controller.perform(.left)
        case 124, 2: controller.perform(.right)
        case 126, 13, 49: controller.perform(.jump)
        case 125, 1: controller.perform(.roll)
        case 11: controller.perform(.board)
        case 14: controller.perform(.ability)
        case 53, 35: controller.togglePause()
        case 36:
            if controller.run.phase == .menu || controller.run.phase == .finished { controller.start() }
            else if controller.run.phase == .paused { controller.resume() }
        default: return false
        }
        return true
    }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        dragOrigin = convert(event.locationInWindow, from: nil)
        lastGestureAction = 0
        waterOrigin = controller?.run.lateral ?? 0
        waterVerticalAnchor = 0
        if event.clickCount == 2 { controller?.perform(.board) }
    }
    override func mouseDragged(with event: NSEvent) {
        guard let origin = dragOrigin else { return }
        let point = convert(event.locationInWindow, from: nil)
        let dx = point.x - origin.x, dy = point.y - origin.y
        let now = ProcessInfo.processInfo.systemUptime
        let sensitivity = controller?.profile.swipeSensitivity ?? 1
        if controller?.run.isWaterTraversal == true {
            controller?.steerWater(waterOrigin + Double(dx) * sensitivity / max(120, Double(bounds.width) * 0.3))
            let vertical = Double(dy) - waterVerticalAnchor
            if abs(vertical) >= 30 / sensitivity, now - lastGestureAction >= 0.12 {
                controller?.perform(vertical > 0 ? .jump : .roll)
                waterVerticalAnchor = Double(dy)
                lastGestureAction = now
            }
            return
        }
        guard max(abs(dx), abs(dy)) > 28 / sensitivity, now - lastGestureAction >= 0.08 else { return }
        lastGestureAction = now
        dragOrigin = point
        if abs(dx) > abs(dy) { controller?.perform(dx < 0 ? .left : .right) }
        else { controller?.perform(dy > 0 ? .jump : .roll) }
    }
    override func mouseUp(with event: NSEvent) { controller?.steerWater(nil); dragOrigin = nil }
}
#endif
