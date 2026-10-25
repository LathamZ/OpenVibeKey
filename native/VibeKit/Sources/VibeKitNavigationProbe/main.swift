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
 check("disconnect does not reset attempt",!gate.take(enabled:true,deviceReady:false,recoverySeen:false,diagnostic:false))
 gate=NavigationStartupGate()
 check("crash recovery blocks auto replay",!gate.take(enabled:true,deviceReady:false,recoverySeen:true,diagnostic:false) && !gate.pending)
 check("recovery later succeeds still requires manual enable",!gate.take(enabled:true,deviceReady:true,recoverySeen:false,diagnostic:false))
 gate=NavigationStartupGate()
 check("diagnostic never takes normal startup intent",!gate.take(enabled:true,deviceReady:true,recoverySeen:false,diagnostic:true) && !gate.attempted)
 gate=NavigationStartupGate();gate.cancel()
 check("manual choice cancels pending startup",!gate.take(enabled:true,deviceReady:true,recoverySeen:false,diagnostic:false))
 gate=NavigationStartupGate()
 for _ in 0..<5 { _=gate.take(enabled:true,deviceReady:false,recoverySeen:false,diagnostic:false) }
 check("late device arrival enables once",gate.take(enabled:true,deviceReady:true,recoverySeen:false,diagnostic:false))
}
print("Navigation checks: \(checks), failures: \(failures). No hardware IO or target-app control performed.")
exit(failures == 0 ? 0 : 1)
