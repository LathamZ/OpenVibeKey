import Foundation
import VibeKitHost

var failures = 0, checks = 0
func check(_ name: String, _ value: @autoclosure () -> Bool) {
    checks += 1
    if !value() { failures += 1; print("FAIL \(name)") }
}
func session(_ n: Int) -> CodexSession {
    CodexSession(reference: String(format: "00000000-0000-0000-0000-%012d", n), title: "Chat \(n)")!
}

for held in [0.150, 0.146] {
    var g = PressGesture()
    check("down has no action", g.press(at: 10).isEmpty)
    check("short release waits", g.release(at: 10 + held).isEmpty)
    check("no early single", g.expire(at: 10 + held + 0.279).isEmpty)
    check("single after release window", g.expire(at: 10 + held + 0.281) == [.single])
    check("no repeated single", g.expire(at: 30).isEmpty)
}
for held in [2.385, 2.208] {
    var g = PressGesture()
    _ = g.press(at: 10)
    check("held before threshold", g.expire(at: 10.649).isEmpty)
    check("actual physical long", g.expire(at: 10.651) == [.long])
    check("held repeat ignored", g.press(at: 11).isEmpty)
    check("held no second long", g.expire(at: 11).isEmpty)
    check("release after long no click", g.release(at: 10 + held).isEmpty)
    check("nothing after long", g.expire(at: 30).isEmpty)
}
do {
    var g = PressGesture(); _ = g.press(at: 0); _ = g.release(at: 0.1)
    check("second down waits for its release", g.press(at: 0.3).isEmpty)
    check("double at second release", g.release(at: 0.4) == [.double])
    check("no single after double", g.expire(at: 1).isEmpty)
    _ = g.press(at: 2); _ = g.release(at: 2.1)
    check("third down starts next group", g.expire(at: 2.4) == [.single])
}
do {
    var g = PressGesture(); _ = g.press(at: 0); _ = g.release(at: 0.1); _ = g.press(at: 0.2)
    check("first single suppressed while second held", g.expire(at: 0.6).isEmpty)
    check("second held becomes long only", g.expire(at: 0.851) == [.long])
    check("second long release silent", g.release(at: 1).isEmpty)
}
do {
    var g = PressGesture(); _ = g.press(at: 0)
    check("late timer long at release", g.release(at: 2) == [.long])
    _ = g.press(at: 3); g.cancel()
    check("context change keeps held barrier", g.press(at: 4).isEmpty)
    check("cancelled held release silent", g.release(at: 5).isEmpty)
    _ = g.press(at: 6); _ = g.release(at: 6.1); g.cancel()
    check("cancel pending click", g.expire(at: 7).isEmpty)
    g.reset(); check("unmatched release ignored", g.release(at: 8).isEmpty)
}
do {
    var g = PressGesture(); _ = g.press(at: 10); _ = g.release(at: 10.1)
    let end = g.deadline!
    check("exact double boundary", g.press(at: end).isEmpty)
    check("exact double release", g.release(at: end + 0.1) == [.double])
    g.reset(); _ = g.press(at: 20); _ = g.release(at: 20.1)
    check("after boundary commits previous single", g.press(at: g.deadline! + 0.001) == [.single])
    g.reset(); _ = g.press(at: 0)
    check("exact long boundary", g.expire(at: g.deadline!) == [.long])
}
let a = session(1), b = session(2), c = session(3)
check("accept official deep link", CodexSession(reference: a.deepLink.absoluteString, title: "A")?.id == a.id)
for text in ["codex://new?prompt=send", "https://example.com", "codex://threads/\(a.id)?prompt=x", "codex://threads/\(a.id)#a", "codex://threads/\(a.id)/extra", "codex://user@threads/\(a.id)", "../../hello", ""] {
    check("reject non-existing-chat reference: \(text)", CodexSession(reference: text, title: "A") == nil)
}
check("empty title rejected", CodexSession(reference: a.id, title: " ") == nil)
check("long title rejected", CodexSession(reference: a.id, title: String(repeating: "a", count: 101)) == nil)
do {
    var nav = CodexNavigation()
    check("idle rotate does not open", nav.rotate(1).isEmpty && nav.stage == .idle)
    nav.enter(sessions: [a, a, b, c]); check("dedup stable list", nav.candidates == [a,b,c])
    _ = nav.rotate(-1); check("start clamp", nav.selected == a)
    check("selection change has no open effect", nav.rotate(1).isEmpty && nav.selected == b)
    _ = nav.rotate(100); check("end clamp", nav.selected == c)
    nav.select(id: b.id)
    check("confirm creates only deep-link effect", nav.gesture(.single, control: .dial, sessions: []) == [.open(b)])
    let request = nav.requestID!
    check("opening rotation ignored", nav.rotate(1).isEmpty && nav.stage == .opening)
    nav.suspend(); nav.dispatched(request: request, session: b, accepted: true)
    check("stale completion cannot reenter", nav.stage == .suspended && nav.lastRequestedID == nil)
    nav.enter(sessions: [a,b,c]); _ = nav.rotate(1); _ = nav.gesture(.single, control: .dial, sessions: [])
    nav.dispatched(request: nav.requestID!, session: b, accepted: true)
    check("OS acknowledgement only openRequested", nav.stage == .openRequested && nav.lastRequestedID == b.id)
    check("content scroll explicitly unavailable", nav.rotate(1).count == 1 && nav.stage == .openRequested)
    check("stop explicitly unavailable", nav.gesture(.single, control: .exit, sessions: []).count == 1)
    check("voice undo explicitly unavailable", nav.gesture(.double, control: .exit, sessions: []).count == 1)
    _ = nav.gesture(.long, control: .exit, sessions: [a,b,c]); check("long exit enters selector remembering last", nav.stage == .choosing && nav.selected == b)
    _ = nav.gesture(.single, control: .exit, sessions: []); check("short exit closes selector without stop", nav.stage == .openRequested)
    nav.enter(sessions: [a]); _ = nav.gesture(.single, control: .dial, sessions: [])
    nav.dispatched(request: nav.requestID!, session: a, accepted: false); check("failed dispatch stays selector", nav.stage == .choosing)
    _ = nav.gesture(.double, control: .dial, sessions: []); check("single workflow double does not write/cycle profiles", nav.stage == .idle && nav.requestID == nil)
    nav.enter(sessions: []); check("empty selector cannot emit open", nav.gesture(.single, control: .dial, sessions: []).count == 1 && nav.stage == .choosing)
}
let slots = zip(["dialP", "dialL", "dialR", "btn3"], [3,5,4,2]).enumerated().map { i, value in
    NavigationCaptureJournal.Slot(id: value.0, index: UInt8(value.1), original: i == 3 ? [] : ["A"], originalFunction: i == 3 ? 12 : 0, captureKey: SentinelPool.mainKeys[i])
}
let journal = NavigationCaptureJournal(deviceSerial: "test-only", slots: slots)
check("valid complete journal", journal.isValid)
check("journal roundtrip preserves raw banks", (try? JSONDecoder().decode(NavigationCaptureJournal.self, from: JSONEncoder().encode(journal))) == journal)
check("partial journal invalid", !NavigationCaptureJournal(deviceSerial: "test", slots: Array(slots.dropLast())).isValid)
check("missing serial invalid", !NavigationCaptureJournal(deviceSerial: "—", slots: slots).isValid)
do {
    let nativeSlots = slots.map { s in
        NavigationCaptureJournal.Slot(id: s.id, index: s.index, original: s.original,
            originalFunction: s.originalFunction, captureKey: s.capture.mainKey,
            nativeBackspace: s.id == "btn3" ? true : nil)
    }
    let native = NavigationCaptureJournal(deviceSerial: "test-only", slots: nativeSlots)
    check("native backspace journal valid", native.isValid)
    check("only bottom emits unmodified backspace", nativeSlots.filter { $0.programmedTokens == ["Backspace"] }.map(\.id) == ["btn3"])
    check("rotary capture preserved", nativeSlots[0].programmedTokens == slots[0].capture.tokens)
    check("original bottom banks preserved", nativeSlots[3].original == slots[3].original && nativeSlots[3].originalFunction == 12)
    check("native journal roundtrip", (try? JSONDecoder().decode(NavigationCaptureJournal.self, from: JSONEncoder().encode(native))) == native)
    check("old journal without field still decodes", (try? JSONDecoder().decode(NavigationCaptureJournal.self, from: JSONEncoder().encode(journal)))?.slots[3].nativeBackspace == nil)
    var wrong = nativeSlots
    wrong[0] = .init(id: "dialP", index: slots[0].index, original: ["A"], captureKey: slots[0].capture.mainKey, nativeBackspace: true)
    check("native backspace forbidden on other slots", !NavigationCaptureJournal(deviceSerial: "test", slots: wrong).isValid)
    // A failure after changing the bottom's function must restore both original banks.
    var keys = Dictionary(uniqueKeysWithValues: nativeSlots.map { ($0.id, $0.original) })
    var functions = Dictionary(uniqueKeysWithValues: nativeSlots.map { ($0.id, $0.originalFunction) })
    let outcome = NavigationCaptureTransaction.install(slots: nativeSlots, capture: { s in
        keys[s.id] = s.programmedTokens; functions[s.id] = 0
        return s.id != "btn3"
    }, restore: { s in keys[s.id] = s.original; functions[s.id] = s.originalFunction; return true })
    check("native backspace failure rolls back all banks", outcome == .rolledBack && nativeSlots.allSatisfy { keys[$0.id] == $0.original && functions[$0.id] == $0.originalFunction })
}
do {
    var calls: [String] = []
    let ok = NavigationCaptureTransaction.install(slots: slots, capture: { calls.append("c:"+$0.id); return true }, restore: { calls.append("r:"+$0.id); return true })
    check("successful capture writes exactly four", ok == .installed && calls == slots.map { "c:"+$0.id })
    for failAt in slots.indices {
        calls = []; var count = 0
        let outcome = NavigationCaptureTransaction.install(slots: slots, capture: { slot in calls.append("c:"+slot.id); defer { count += 1 }; return count != failAt }, restore: { calls.append("r:"+$0.id); return true })
        check("failure at \(failAt) restores all original banks", outcome == .rolledBack && calls.suffix(4) == slots.map { "r:"+$0.id })
    }
    var attempted: [String] = []
    let failed = NavigationCaptureTransaction.install(slots: slots, capture: { _ in false }, restore: { slot in attempted.append(slot.id); return slot.id != "dialP" })
    check("rollback failure retains recovery state", failed == .recoveryRequired)
    check("rollback does not stop at first failure", attempted == slots.map(\.id))
}
for enabled in [false,true] {
 for ready in [false,true] {
  for content in [false,true] {
   for front in [nil,"com.openai.codex","com.other.app","com.openai.codex.fake"] as [String?] {
    check("native page route truth table", (NativePageScroll.desired(enabled:enabled,ready:ready,contentSelected:content,frontmostBundleID:front) == .pages) == (enabled && ready && content && front == "com.openai.codex"))
   }
  }
 }
}
do {
 check("left native PageUp",NativePageScroll.tokens(slot:slots[1],mode:.pages) == ["PageUp"])
 check("right native PageDown",NativePageScroll.tokens(slot:slots[2],mode:.pages) == ["PageDown"])
 check("selection restores exact capture",NativePageScroll.tokens(slot:slots[1],mode:.navigation) == slots[1].programmedTokens)
 check("rotary push not changed by pages",NativePageScroll.tokens(slot:slots[0],mode:.pages) == slots[0].programmedTokens)
 let bottom = NavigationCaptureJournal.Slot(id:"btn3",index:2,original:["Esc"],captureKey:"1",nativeBackspace:true)
 check("native backspace preserved in pages",NativePageScroll.tokens(slot:bottom,mode:.pages) == ["Backspace"])
 var writes:[String]=[]
 check("page install successful",NativePageScroll.apply(slots:slots,mode:.pages,writeAndVerify:{s,t in writes.append(s.id+":"+t.joined(separator:"+"));return true}))
 check("only two direction slots written",writes == ["dialL:PageUp","dialR:PageDown"])
 for failAt in 0...1 {
  var index=0;writes=[]
  let ok=NativePageScroll.apply(slots:slots,mode:.pages,writeAndVerify:{s,t in
   writes.append(s.id+":"+t.joined(separator:"+"));defer{index+=1};return index != failAt
  })
  check("partial page failure reports failure",!ok)
  check("partial failure attempts both capture restorations",writes.suffix(2) == slots[1...2].map{$0.id+":"+$0.programmedTokens.joined(separator:"+")})
 }
 var invalidWrites=0
 check("missing direction rejected",!NativePageScroll.apply(slots:[slots[1]],mode:.pages,writeAndVerify:{_,_ in invalidWrites+=1;return true}) && invalidWrites == 0)
}
do {
 var state=NativePageRouteState()
 check("same layer no USB write",state.request(.navigation) == nil)
 let first=state.request(.pages)!
 check("in-flight intent coalesced",state.request(.navigation) == nil && state.operation == first)
 let back=state.complete(first,succeeded:true)!
 check("return queued after content write",back.mode == .navigation && state.applied == .pages)
 check("one operation at a time",state.request(.pages) == nil)
 let again=state.complete(back,succeeded:true)!
 check("latest foreground intent survives",again.mode == .pages)
 check("completed content stable",state.complete(again,succeeded:true) == nil && state.applied == .pages)
 check("repeated content route idempotent",state.request(.pages) == nil)
 let old=state.request(.navigation)!
 state.reset()
 let fresh=state.request(.pages)!
 check("cancelled callback cannot consume new operation",state.complete(old,succeeded:true) == nil && state.operation == fresh)
 check("failure explicit and no retry loop",state.complete(fresh,succeeded:false) == nil && state.failed && state.applied == nil)
 check("failure blocks further mode writes",state.request(.navigation) == nil)
 state.reset()
 check("restoration reset re-enables routing",!state.failed && state.applied == .navigation && state.request(.pages) != nil)
}
do {
 let bottom=NavigationCaptureJournal.Slot(id:"btn3",index:2,original:["Esc"],captureKey:"1",nativeBackspace:true)
 let targets=[slots[0],slots[1],slots[2],bottom]
 check("selector mode takes priority without page experiment",NativePageScroll.desired(enabled:false,ready:true,contentSelected:false,frontmostBundleID:nil,selectorVisible:true) == .selection)
 check("not ready cannot enter selection mode",NativePageScroll.desired(enabled:true,ready:false,contentSelected:true,frontmostBundleID:"com.openai.codex",selectorVisible:true) == .navigation)
 check("selector bottom is rare capture, not Escape injection",NativePageScroll.tokens(slot:bottom,mode:.selection) == bottom.capture.tokens)
 check("content bottom remains Backspace",NativePageScroll.tokens(slot:bottom,mode:.pages) == ["Backspace"])
 check("closed list bottom remains Backspace",NativePageScroll.tokens(slot:bottom,mode:.navigation) == ["Backspace"])
 var writes:[String:[String]]=[:]
 check("selection hardware plan succeeds",NativePageScroll.apply(slots:targets,mode:.selection,writeAndVerify:{s,t in writes[s.id]=t;return true}))
 check("selection updates only two directions and bottom",Set(writes.keys) == Set(["dialL","dialR","btn3"]) && writes["btn3"] == bottom.capture.tokens)
 var held=SelectorExitPress()
 check("stray exit release ignored",!held.release())
 held.press();held.press()
 check("exit does not fire while held",held.isHeld)
 check("exit fires once on release",held.release() && !held.isHeld && !held.release())
 held.press();held.cancel()
 check("cancelled context consumes old release",!held.release())
 held.press()
 check("fresh press after cancellation works",held.release())
 var route=NativePageRouteState()
 let first=route.request(.selection)!
 check("content switch waits for selection write",route.request(.pages) == nil)
 let next=route.complete(first,succeeded:true)!
 check("content switch follows latest intent",next.mode == .pages)
 _=route.complete(next,succeeded:true)
 check("selection can be requested again",route.request(.selection)?.mode == .selection)
 let sessions=[session(1),session(2)]
 var nav=CodexNavigation();nav.enter(sessions:sessions)
 let request=nav.gesture(.single,control:.dial,sessions:sessions)
 if case .open(let opened)?=request.first, let id=nav.requestID {
  nav.dispatched(request:id,session:opened,accepted:true)
  nav.enter(sessions:sessions);_=nav.rotate(1)
  let effects=nav.gesture(.single,control:.exit,sessions:sessions)
  check("window close cancels selection preserving prior chat",effects.isEmpty && nav.stage == .openRequested && nav.lastRequestedID == opened.id)
 } else { check("selector close fixture valid",false) }
}
do {
 var gate=NavigationStartupGate()
 check("default off never auto-enables",!gate.take(enabled:false,deviceReady:true,recoverySeen:false,diagnostic:false) && !gate.attempted)
 gate=NavigationStartupGate()
 check("waits for verified device",!gate.take(enabled:true,deviceReady:false,recoverySeen:false,diagnostic:false) && gate.pending)
 check("ready remembered on attempts once",gate.take(enabled:true,deviceReady:true,recoverySeen:false,diagnostic:false) && gate.attempted)
 check("no repeating auto-enable",!gate.take(enabled:true,deviceReady:true,recoverySeen:false,diagnostic:false))
 check("not-ready heartbeat alone does not reset attempt",!gate.take(enabled:true,deviceReady:false,recoverySeen:false,diagnostic:false))
 gate=NavigationStartupGate()
 check("crash recovery blocks auto replay",!gate.take(enabled:true,deviceReady:false,recoverySeen:true,diagnostic:false) && !gate.pending)
 check("recovery stays blocked until explicit verified rearm",!gate.take(enabled:true,deviceReady:true,recoverySeen:false,diagnostic:false))
 gate=NavigationStartupGate()
 check("diagnostic never takes normal startup intent",!gate.take(enabled:true,deviceReady:true,recoverySeen:false,diagnostic:true) && !gate.attempted)
 gate=NavigationStartupGate();gate.cancel()
 check("manual choice cancels pending startup",!gate.take(enabled:true,deviceReady:true,recoverySeen:false,diagnostic:false))
 gate=NavigationStartupGate()
 for _ in 0..<5 { _=gate.take(enabled:true,deviceReady:false,recoverySeen:false,diagnostic:false) }
 check("late device arrival enables once",gate.take(enabled:true,deviceReady:true,recoverySeen:false,diagnostic:false))
}
// Edit/browse and cross-app routing must never turn a long hold into a short toggle.
do {
 for front in [nil, "com.other.app", "com.openai.codex.fake"] as [String?] {
  for editing in [false,true] {
   check("non-Codex defaults to arrows regardless of Codex mode", NativePageScroll.desired(enabled:true,ready:true,contentSelected:true,frontmostBundleID:front,editing:editing) == .arrows)
  }
 }
 check("Codex edit mode arrows", NativePageScroll.desired(enabled:true,ready:true,contentSelected:true,frontmostBundleID:"com.openai.codex",editing:true) == .arrows)
 check("Codex browsing pages", NativePageScroll.desired(enabled:true,ready:true,contentSelected:true,frontmostBundleID:"com.openai.codex",editing:false) == .pages)
 check("no content defaults to arrows", NativePageScroll.desired(enabled:true,ready:true,contentSelected:false,frontmostBundleID:"com.openai.codex") == .arrows)
 check("disabled browsing still arrows", NativePageScroll.desired(enabled:false,ready:true,contentSelected:true,frontmostBundleID:"com.openai.codex") == .arrows)
 check("selector precedence over edits", NativePageScroll.desired(enabled:true,ready:true,contentSelected:true,frontmostBundleID:"com.openai.codex",selectorVisible:true,editing:true) == .selection)
 check("not-ready retains capture", NativePageScroll.desired(enabled:true,ready:false,contentSelected:true,frontmostBundleID:"com.other.app",editing:true) == .navigation)
 check("native left arrow",NativePageScroll.tokens(slot:slots[1],mode:.arrows) == ["Left"])
 check("native right arrow",NativePageScroll.tokens(slot:slots[2],mode:.arrows) == ["Right"])
 var s=NativePageRouteState();let p=s.request(.pages)!
 check("app switch queues arrows",s.request(.arrows) == nil)
 let a=s.complete(p,succeeded:true)!
 check("app switch wins in-flight pages",a.mode == .arrows)
 _=s.complete(a,succeeded:true)
 check("arrows active after coalesced change",s.applied == .arrows && s.operation == nil)
 for duration in [0.08,0.2,0.649,0.65,2.0] {
  var h=PhysicalRotaryHold()
  check("press does not toggle or navigate",h.action(down:true,at:1,eligible:true) == nil)
  check("repeat down is not a toggle",h.action(down:true,at:1+duration/2,eligible:true) == nil)
  check("exclusive short/long release",h.action(down:false,at:1+duration,eligible:true) == (duration < 0.65 ? .short : .long))
  check("duplicate release silent",h.action(down:false,at:5,eligible:true) == nil)
 }
 var h=PhysicalRotaryHold();_=h.action(down:true,at:0,eligible:true);h.cancel()
 check("foreground change cancels short toggle",h.action(down:false,at:0.2,eligible:true) == nil)
 h=PhysicalRotaryHold();_=h.action(down:true,at:0,eligible:true)
 check("release in another app cannot toggle",h.action(down:false,at:0.2,eligible:false) == nil)
 h=PhysicalRotaryHold(initiallyHeld:true)
 check("key held at startup cannot toggle",h.action(down:false,at:2,eligible:true) == nil)
}

// Unified onboarding and capability-gated app expansion.
do {
 for accessibility in [false,true] { for monitor in [false,true] { for mic in [false,true] { for notice in [false,true] {
  check("complete permission status is accurate", WorkflowDefaults.permissionsReady(accessibility:accessibility,inputMonitoring:monitor,microphone:mic,notifications:notice) == (accessibility && monitor && mic && notice))
  check("navigation depends only on required permissions", WorkflowDefaults.navigationPermissionsReady(accessibility:accessibility,inputMonitoring:monitor) == (accessibility && monitor))
 }}}}
 for id in ["btn1","btn2","btn3","dialP","dialL","dialR"] {
  check("owned slots alone are protected",!WorkflowDefaults.canEdit(slot:id,navigationOwnsHardware:true))
  check("paused navigation permits manual key editing",WorkflowDefaults.canEdit(slot:id,navigationOwnsHardware:false))
 }
 check("catalog restores Claude Code alongside existing targets",WorkflowCatalog.targets.count == 4 && Set(WorkflowCatalog.targets.map(\.id)) == Set([.codex, .deepSeek, .claudeCode, .weChat]))
 check("Codex retains real session capability",WorkflowCatalog.supports(.conversations,in:.codex))
 for id in [WorkflowTargetID.weChat] {
  check("planned adapter is never treated as integrated",!WorkflowCatalog.target(id).integrated)
  for capability in WorkflowCapability.allCases { check("planned adapter cannot dispatch a capability",!WorkflowCatalog.supports(capability,in:id)) }
 }
 check("WeChat has no invented task-stop capability",!WorkflowCatalog.supports(.stopTask,in:.weChat))
 check("Codex resume is not falsely advertised",!WorkflowCatalog.supports(.resumeTask,in:.codex))
}

// Eight-position wheel and safe page-key leases.
do {
    for count in [0, 1, 7, 8, 9, 16, 17, 2000] {
        check("disc count covers every item", SessionWheelPaging.pageCount(count) == (count == 0 ? 0 : (count - 1) / 8 + 1))
        for selected in count == 0 ? [0] : Array(Set([0, count / 2, count - 1])) {
            let range = SessionWheelPaging.range(selection: selected, count: count)
            check("disc contains at most eight real items", range.count <= 8 && range.lowerBound >= 0 && range.upperBound <= count)
            for delta in [-1001, -1, 0, 1, 1001, Int.min, Int.max] {
                let rotated = SessionWheelPaging.rotated(selection: selected, count: count, delta: delta)
                let turned = SessionWheelPaging.turned(selection: selected, count: count, delta: delta)
                check("rotation stays on disc", count == 0 ? rotated == 0 : range.contains(rotated))
                check("paging never selects an empty slot", count == 0 ? turned == 0 : (0..<count).contains(turned))
            }
        }
    }
    check("clockwise last slot wraps on same disc", SessionWheelPaging.rotated(selection: 7, count: 19, delta: 1) == 0)
    check("anticlockwise first slot wraps on same disc", SessionWheelPaging.rotated(selection: 8, count: 19, delta: -1) == 15)
    check("partial disc wraps among three", SessionWheelPaging.rotated(selection: 18, count: 19, delta: 1) == 16)
    check("page keeps angular slot", SessionWheelPaging.turned(selection: 6, count: 19, delta: 1) == 14)
    check("last page clamps absent angular slot", SessionWheelPaging.turned(selection: 14, count: 19, delta: 1) == 18)
    check("previous page from first wraps", SessionWheelPaging.turned(selection: 0, count: 19, delta: -1) == 16)
    var nav = CodexNavigation(); nav.enter(sessions: (1...19).map(session)); nav.rotateWheel(-1)
    check("wheel navigation uses page-local wrapping", nav.selection == 7)
    nav.turnWheelPage(1); check("wheel pager selects real global session", nav.selection == 15 && nav.selected == session(16))
    _ = nav.gesture(.single, control: .dial, sessions: [])
    check("confirm opens actual highlighted ID", nav.selected == session(16) && nav.stage == .opening)
    nav.turnWheelPage(1); nav.rotateWheel(1)
    check("opening stage cannot change target with page keys", nav.selection == 15)
}
do {
    let items = [session(1), session(2), session(3)]
    let sorted = SessionWheelPaging.ordered(items, activity: [items[0].id: 100, items[1].id: 200, items[2].id: 150], opened: [items[0].id: 300])
    check("local opening and server activity share recency order", sorted == [items[0], items[1], items[2]])
    check("server millisecond timestamps normalized", SessionWheelPaging.ordered(items, activity: [items[0].id: 1_800_000_000_000, items[1].id: 1_900_000_000], opened: [:]).first == items[1])
    check("unknown timestamps have deterministic tie order", SessionWheelPaging.ordered(items.reversed(), activity: [:], opened: [:]) == items)
    check("bad timestamps cannot win recency", SessionWheelPaging.ordered(items, activity: [items[2].id: .nan], opened: [items[2].id: -.infinity]).first == items[0])
    var ledger = SessionColorLedger(colors: ["bad":"GG0000", "saved":"abcdef"])
    check("invalid saved color rejected", ledger.colors["bad"] == nil && ledger.colors["saved"] == "ABCDEF")
    let ids = (1...19).map { session($0).id }
    check("new sessions assigned palette colors", ledger.ensure(ids: ids, pick: { _ in 0 }))
    check("initial disc has eight distinguishable colors", Set(ids.prefix(8).compactMap { ledger.colors[$0] }).count == 8)
    let saved = ledger
    check("refresh never rerandomizes existing colors", !ledger.ensure(ids: ids.reversed(), pick: { _ in 0 }) && ledger == saved)
    check("custom color accepted", ledger.set(id: ids[0], hex: "112233"))
    _ = ledger.ensure(ids: ids + [session(20).id])
    check("new conversations preserve manual colors", ledger.colors[ids[0]] == "112233")
    check("invalid custom color does not erase saved value", !ledger.set(id: ids[0], hex: "white") && ledger.colors[ids[0]] == "112233")
    let data = try! JSONEncoder().encode(ledger)
    check("color ledger survives restart", (try! JSONDecoder().decode(SessionColorLedger.self, from: data)) == ledger)
}
do {
    var key = WheelPagePress(); let epoch = UUID()
    check("unmatched page release ignored", key.release("btn1", generation: epoch, eligible: true) == nil)
    key.press("btn1", generation: epoch); key.press("btn1", generation: epoch)
    check("hold and repeat emit one page on release", key.release("btn1", generation: epoch, eligible: true) == -1)
    check("duplicate page up silent", key.release("btn1", generation: epoch, eligible: true) == nil)
    key.press("btn2", generation: epoch); key.cancel(); key.press("btn2", generation: epoch)
    check("cancelled held key retains barrier", key.isHeld && key.release("btn2", generation: epoch, eligible: true) == nil)
    key.press("btn2", generation: epoch)
    check("new physical press works after cancelled release", key.release("btn2", generation: epoch, eligible: true) == 1)
    key.press("btn1", generation: epoch)
    check("old selector generation cannot page new selector", key.release("btn1", generation: UUID(), eligible: true) == nil)
    key.press("btn2", generation: epoch)
    check("background release cannot page", key.release("btn2", generation: epoch, eligible: false) == nil)
}
do {
    let ids = ["dialP", "dialL", "dialR", "btn3", "btn1", "btn2"]
    let entries = ids.enumerated().map { i,id in
        NavigationCaptureJournal.Slot(id: id, index: UInt8(i), original: ["A"], originalFunction: id == "btn1" ? 12 : 0, captureKey: SentinelPool.mainKeys[i], nativeBackspace: id == "btn3" ? true : nil, selectorPaging: id == "btn1" || id == "btn2" ? true : nil)
    }
    let wheel = NavigationCaptureJournal(deviceSerial: "fixture", slots: entries)
    check("new journal is valid version2", wheel.version == 2 && wheel.isValid)
    let legacy = NavigationCaptureJournal(deviceSerial: "fixture", slots: Array(entries.prefix(4)))
    check("old four-slot journal still valid", legacy.version == 1 && legacy.isValid)
    check("partial paging pair rejected", !NavigationCaptureJournal(deviceSerial: "fixture", slots: Array(entries.prefix(5))).isValid)
    check("journal decoding retains selector-only fields", (try! JSONDecoder().decode(NavigationCaptureJournal.self, from: JSONEncoder().encode(wheel))) == wheel)
    for mode in [NativePageScroll.Mode.navigation, .arrows, .pages, .selection] {
        var captured = Set<String>(), restored = Set<String>()
        let ok = NativePageScroll.apply(slots: entries, mode: mode, restoreOriginal: { slot in
            check("paging restores original function bank", slot.id != "btn1" || slot.originalFunction == 12)
            restored.insert(slot.id); return true
        }, writeAndVerify: { slot,tokens in
            if slot.selectorPaging == true { captured.insert(slot.id); check("selector writes exact paging capture", tokens == slot.capture.tokens) }
            return true
        })
        check("routing mode succeeds", ok)
        check("page buttons captured only in selector", mode == .selection ? captured == Set(["btn1","btn2"]) && restored.isEmpty : captured.isEmpty && restored == Set(["btn1","btn2"]))
    }
    var restored = Set<String>()
    let ok = NativePageScroll.apply(slots: entries, mode: .selection, restoreOriginal: { restored.insert($0.id); return true }, writeAndVerify: { slot,_ in slot.id != "btn2" })
    check("failed selector write reports failure", !ok)
    check("failed write restores both original paging banks", restored == Set(["btn1","btn2"]))
    for failure in entries.indices {
        var writes = 0, restored = Set<String>()
        let result = NavigationCaptureTransaction.install(slots: entries, capture: { _ in defer { writes += 1 }; return writes != failure }, restore: { restored.insert($0.id); return true })
        check("every six-slot install failure rolls back every original", result == .rolledBack && restored == Set(ids))
    }
}

// Physical detents produce fractional movement, then settle to the nearest visible conversation.
do {
    for count in [0,1,2,3,8,9,19] {
        for step in [1.0,2,3,8] {
            var m = SessionWheelMotion(); m.reset(selection: 0, total: count)
            m.turn(1, stepsPerItem: step)
            check("motion remains finite", m.position.isFinite)
            check("motion nearest valid", count == 0 ? m.nearest == 0 : (0..<min(count,8)).contains(m.nearest))
            m.settle()
            check("settle lands on exact stop", m.position == m.position.rounded())
        }
    }
    var m = SessionWheelMotion(); m.reset(selection: 0, total: 8)
    m.turn(1, stepsPerItem: 3)
    check("default slower than one item per detent", m.nearest == 0 && abs(m.position - 1.0/3) < 0.0001)
    m.settle(); check("less than halfway attracts back", m.nearest == 0 && m.position == 0)
    m.turn(2, stepsPerItem: 3); check("more than halfway selects next", m.nearest == 1)
    m.settle(); check("more than halfway attracts forward", m.nearest == 1 && m.position == 1)
    m.reset(selection: 0, total: 8); m.turn(-2, stepsPerItem: 3); m.settle()
    check("negative wrap follows nearest stop", m.nearest == 7 && m.position == -1)
    m.turn(2, stepsPerItem: 3); m.settle(); check("direction reversal settles symmetrically", m.nearest == 0)
    m.reset(selection: 18, total: 19); m.turn(1, stepsPerItem: 1); m.settle()
    check("partial disc wraps only real cards", m.nearest == 16)
    m.reset(selection: 10, total: 19); check("page change resets residual", m.position == 2 && m.nearest == 10)
    m.turn(1, stepsPerItem: 8); m.reset(selection: 0, total: 8)
    check("fresh selector never inherits partial travel", m.position == 0)
    m.turn(Int.max, stepsPerItem: 3);m.settle();check("extreme input remains bounded valid", (0..<8).contains(m.nearest) && m.position.isFinite)
    check("sensitivity sanitized", SessionWheelMotion.steps(.nan) == 3 && SessionWheelMotion.steps(.infinity) == 3 && SessionWheelMotion.steps(-1) == 1 && SessionWheelMotion.steps(100) == 8)
    m.reset(selection: 0, total: 8);m.turn(1, stepsPerItem: 2);m.settle();check("halfway tie advances consistently", m.nearest == 1)
}

do {
    var gate = NavigationStartupGate()
    check("first ready connection enables", gate.take(enabled:true,deviceReady:true,recoverySeen:false,diagnostic:false))
    for cycle in 1...3 {
        gate.beginConnection()
        check("connection waits for restoration", !gate.take(enabled:true,deviceReady:false,recoverySeen:true,diagnostic:false))
        gate.beginConnection() // VM only re-arms here after device identity/profile/originals are verified.
        check("verified reconnect arms once", gate.take(enabled:true,deviceReady:true,recoverySeen:false,diagnostic:false))
        for _ in 0..<5 { check("heartbeat never repeats capture", !gate.take(enabled:true,deviceReady:true,recoverySeen:false,diagnostic:false)) }
        check("reconnect attempt recorded", gate.attempted && !gate.pending)
    }
    gate.beginConnection()
    check("explicit pause prevents reconnect auto-enable", !gate.take(enabled:false,deviceReady:true,recoverySeen:false,diagnostic:false))
    gate.beginConnection()
    check("hardware diagnostic never auto-arms", !gate.take(enabled:true,deviceReady:true,recoverySeen:false,diagnostic:true))
    for automatic in [false,true] {
        for diagnostic in [false,true] {
            for restore in [false,true] {
                let route = NavigationStartupGate.dialPriority(automatic:automatic,diagnostic:diagnostic,hasRestore:restore)
                if automatic && !diagnostic {
                    check("automatic workflow never reclaims legacy capture", route != .legacyCapture)
                    check("saved legacy original restored before navigation", route == (restore ? .restoreOriginal : .navigation))
                } else { check("explicit pause and hardware diagnostics retain legacy behavior", route == .legacyCapture) }
            }
        }
    }
    var savedLegacyOriginal = true
    gate = NavigationStartupGate(); gate.cancel() // recovery record at launch
    check("legacy recovery chooses restore, not legacy recapture", NavigationStartupGate.dialPriority(automatic:true,diagnostic:false,hasRestore:savedLegacyOriginal) == .restoreOriginal)
    savedLegacyOriginal = false
    gate.beginConnection()
    check("after verified legacy restore navigation has priority", NavigationStartupGate.dialPriority(automatic:true,diagnostic:false,hasRestore:savedLegacyOriginal) == .navigation)
    check("previously blocked startup automatically re-arms after restore", gate.take(enabled:true,deviceReady:true,recoverySeen:false,diagnostic:false))
    check("failed capture cannot retry each heartbeat", !gate.take(enabled:true,deviceReady:true,recoverySeen:false,diagnostic:false))
}

// Curve, wrap continuity, clear center and strictly local backdrop geometry.
do {
    let front = SessionOrbit.pose(index: 0, position: 0, count: 8)
    check("orbit selected card rests at front", abs(front.x - 500) < 0.001 && abs(front.y - 475) < 0.001 && front.depth == 1)
    let back = SessionOrbit.pose(index: 4, position: 0, count: 8)
    check("orbit back recedes", back.scale < front.scale && back.opacity < front.opacity && back.depth == 0)
    var periodic = true, contained = true, clearCenter = true
    for count in 1...8 {
        for tick in 0..<(count * 100) {
            let position = Double(tick) / 100
            for index in 0..<count {
                let p = SessionOrbit.pose(index: index, position: position, count: count)
                let q = SessionOrbit.pose(index: index, position: position + Double(count), count: count)
                periodic = periodic && abs(p.x-q.x) < 0.0001 && abs(p.y-q.y) < 0.0001
                contained = contained && p.x - 104*p.scale >= 0 && p.x + 104*p.scale <= 1000 && p.y-43*p.scale >= 0 && p.y+43*p.scale <= 680
                let overlaps = p.x-104*p.scale < 630 && p.x+104*p.scale > 370 && p.y-43*p.scale < 366 && p.y+43*p.scale > 254
                clearCenter = clearCenter && !overlaps
            }
        }
    }
    check("orbit seamless over every page size", periodic)
    check("all moving cards stay within canvas", contained)
    check("moving cards never overlap central information", clearCenter)
    var feather = true, edge = true
    for i in 0...100 {
        let x = Double(i)/100
        feather = feather && SessionOrbit.maskAlpha(x: 0.5 + x*0.5, y: 0.5) >= SessionOrbit.maskAlpha(x: 0.5 + min(1,x+0.01)*0.5, y: 0.5)
        edge = edge && SessionOrbit.maskAlpha(x: x, y: 0) == 0 && SessionOrbit.maskAlpha(x: x, y: 1) == 0 && SessionOrbit.maskAlpha(x: 0, y: x) == 0 && SessionOrbit.maskAlpha(x: 1, y: x) == 0
    }
    check("blur feather decreases monotonically", feather)
    check("blur zero at all outer edges", edge)
    check("backdrop strength validates non-finite input", SessionOrbit.glass(.nan) == 0.7 && SessionOrbit.glass(-1) == 0 && SessionOrbit.glass(2) == 1)
    var motion = SessionWheelMotion()
    motion.reset(selection: 7, total: 8)
    motion.select(selection: 0)
    check("click next across seam takes short forward path", motion.position == 8 && motion.nearest == 0)
    motion.select(selection: 7)
    check("click previous across seam takes short backward path", motion.position == 7 && motion.nearest == 7)
    motion.reset(selection: 8, total: 9); motion.select(selection: 0)
    check("outside-page click cannot corrupt selection", motion.position == 0 && motion.nearest == 8)
}

// App identity colors and geometry stay independent of unimplemented adapter actions.
do {
    check("Codex has white selection light", WorkflowCatalog.target(.codex).haloHex == "FFFFFF")
    check("DeepSeek uses official homepage blue", WorkflowCatalog.target(.deepSeek).haloHex == "4176E6")
    check("Claude uses official Claude orange", WorkflowCatalog.target(.claudeCode).haloHex == "D97757")
    check("Claude uses its desktop app", WorkflowCatalog.target(.claudeCode).transport == .native && WorkflowCatalog.target(.claudeCode).integrated)
    check("halo extends 20 percent of the short edge", abs(SessionOrbit.haloExtent(width: 208, height: 86) - 17.2) < 0.001)
    check("halo invalid geometry stays empty", SessionOrbit.haloExtent(width: .nan, height: 86) == 0 && SessionOrbit.haloExtent(width: -2, height: 86) == 0)
    check("halo ends in transparency", SessionOrbit.haloOpacity(progress: 1) == 0 && SessionOrbit.haloOpacity(progress: .infinity) == 0)
    var fade = true
    for i in 0..<100 { fade = fade && SessionOrbit.haloOpacity(progress: Double(i)/100) > SessionOrbit.haloOpacity(progress: Double(i+1)/100) }
    check("halo fades continuously outwards", fade)
}

do {
    let id = "00000000-0000-0000-0000-000000000001"
    let old = Data("{\"id\":\"\(id)\",\"title\":\"Existing pin\"}".utf8)
    let pin = try! JSONDecoder().decode(CodexSession.self, from: old)
    check("legacy pin remains Codex", pin.target == .codex && pin.isValid)
    let foreign = CodexSession(adapterReference: id, title: "Sidebar chat", target: .deepSeek)!
    let roundtrip = try! JSONDecoder().decode(CodexSession.self, from: JSONEncoder().encode(foreign))
    check("external session preserves target through coding", roundtrip == foreign && roundtrip.target == .deepSeek)
    check("Claude desktop has a separate target", CodexSession(adapterReference: id, title: "reviewer", target: .claudeCode)?.target == .claudeCode)
    check("WeChat is outside external adapter scope", CodexSession(adapterReference: id, title: "Chat", target: .weChat) == nil)
    check("external handle is strictly UUID", CodexSession(adapterReference: "../arbitrary", title: "Chat", target: .deepSeek) == nil)
    check("foreign IDs never enter Codex reference parser", CodexSession(reference: "dsh://open", title: "Chat") == nil)
    check("DeepSeek content pages are explicitly target-scoped", NativePageScroll.desired(enabled: true, ready: true, contentSelected: true, frontmostBundleID: "com.deepseek.dsh", contentBundleID: "com.deepseek.dsh") == .pages)
    check("foreign foreground cannot inherit DeepSeek pages", NativePageScroll.desired(enabled: true, ready: true, contentSelected: true, frontmostBundleID: "com.openai.codex", contentBundleID: "com.deepseek.dsh") == .arrows)
    check("DeepSeek edit uses physical arrows", NativePageScroll.desired(enabled: true, ready: true, contentSelected: true, frontmostBundleID: "com.deepseek.dsh", editing: true, contentBundleID: "com.deepseek.dsh") == .arrows)
    for target in [WorkflowTargetID.deepSeek, .claudeCode] {
        check("desktop adapter advertises verified list/open/focus", WorkflowCatalog.supports(.conversations, in: target) && WorkflowCatalog.supports(.openConversation, in: target) && WorkflowCatalog.supports(.focusComposer, in: target))
        check("desktop adapter does not invent stop/resume", !WorkflowCatalog.supports(.stopTask, in: target) && !WorkflowCatalog.supports(.resumeTask, in: target))
    }
    check("Codex focus shortcut never leaks to DeepSeek", NativeFocusShortcut.route(configured: true, navigationReady: true, contentSelected: true, frontmostBundleID: "com.deepseek.dsh", rotaryHeld: false) == .captureForNavigation)
}

print("Navigation checks: \(checks), failures: \(failures). No hardware IO or target-app control performed.")
exit(failures == 0 ? 0 : 1)
