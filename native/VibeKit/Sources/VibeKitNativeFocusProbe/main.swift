import Foundation
import VibeKitHost

var checks = 0, failures = 0
func check(_ name:String,_ ok:@autoclosure ()->Bool) { checks += 1; if !ok() { failures += 1; print("FAIL \(name)") } }
for configured in [false,true] {
 for ready in [false,true] {
  for content in [false,true] {
   for front in [nil,"com.openai.codex","com.other.app","com.openai.codex.fake"] as [String?] {
    for held in [false,true] {
     let result = NativeFocusShortcut.route(configured:configured,navigationReady:ready,contentSelected:content,frontmostBundleID:front,rotaryHeld:held)
     let expected = configured && ready && content && front == "com.openai.codex" && !held
     check("routing truth table",(result == .physicalShortcut) == expected)
    }
   }
  }
 }
}
check("default explicit main key",NativeFocusShortcut.defaultMainKey == "F12")
check("fixed focus combo",NativeFocusShortcut.preferredCombo(mainKey:"F12",used:[])?.tokens == ["LCtrl","LOpt","LCmd","F12"])
check("no silent key substitution on conflict",NativeFocusShortcut.preferredCombo(mainKey:"F12",used:[["LCtrl","LOpt","LCmd","F12"]]) == nil)
check("left/right normalized conflict",NativeFocusShortcut.preferredCombo(mainKey:"F12",used:[["RCtrl","ROpt","RCmd","F12"]]) == nil)
check("invalid key rejected",NativeFocusShortcut.preferredCombo(mainKey:"Enter",used:[]) == nil)
check("other key remains available",NativeFocusShortcut.preferredCombo(mainKey:"F11",used:[["LCtrl","LOpt","LCmd","F12"]])?.mainKey == "F11")
do {
 var captured=true, writes=0, releases=0
 func apply(_ route:NativeFocusShortcut.Route,_ succeeds:Bool=true)->NativeFocusCaptureLease.Result {
  NativeFocusCaptureLease.apply(route:route,isCaptured:{captured},capture:{writes += 1;captured=succeeds;return succeeds},release:{releases += 1;captured=false})
 }
 check("selection retains existing capture",apply(.captureForNavigation) == .captured && writes == 0 && releases == 0)
 check("content releases only capture",apply(.physicalShortcut) == .physicalShortcut && !captured && releases == 1)
 check("same content route idempotent",apply(.physicalShortcut) == .physicalShortcut && releases == 1)
 check("return re-registers capture",apply(.captureForNavigation) == .captured && captured && writes == 1)
 _ = apply(.physicalShortcut)
 check("capture failure explicit",apply(.captureForNavigation,false) == .captureFailed && !captured)
 check("retry restores capture",apply(.captureForNavigation,true) == .captured && captured)
}
// Device-edge copies must never turn a short click or a context-crossing hold into navigation.
do {
 var hold = PhysicalRotaryHold()
 check("physical down does not navigate", !hold.edge(down: true, at: 1, eligible: true))
 check("physical short release leaves focus alone", !hold.edge(down: false, at: 1.2, eligible: true))
 _ = hold.edge(down: true, at: 2, eligible: true)
 check("repeat down ignored", !hold.edge(down: true, at: 2.8, eligible: true))
 check("hold returns on release", hold.edge(down: false, at: 3, eligible: true))
 check("duplicate up ignored", !hold.edge(down: false, at: 3.1, eligible: true))
 _ = hold.edge(down: true, at: 4, eligible: true); hold.cancel()
 check("context change cancels hold", !hold.edge(down: false, at: 5, eligible: true))
 _ = hold.edge(down: true, at: 6, eligible: false)
 check("ineligible down cannot navigate after switching back", !hold.edge(down: false, at: 7, eligible: true))
 _ = hold.edge(down: true, at: 8, eligible: true)
 check("ineligible release cancels", !hold.edge(down: false, at: 9, eligible: false))
 hold = PhysicalRotaryHold(initiallyHeld: true)
 _ = hold.edge(down: true, at: 10, eligible: true)
 check("already held at listener start ignored", !hold.edge(down: false, at: 12, eligible: true))
 _ = hold.edge(down: true, at: 13, eligible: true)
 check("next real hold works", hold.edge(down: false, at: 14, eligible: true))
 _ = hold.edge(down: true, at: 15, eligible: true)
 check("backwards timestamp ignored", !hold.edge(down: false, at: 14, eligible: true))
 _ = hold.edge(down: true, at: 16, eligible: true)
 _ = hold.edge(down: false, at: 16.1, eligible: true)
 _ = hold.edge(down: true, at: 16.2, eligible: true)
 check("double short press not long", !hold.edge(down: false, at: 16.3, eligible: true))
}
// Real Carbon ownership check: no event is generated and no application is controlled.
do {
 let center=HotKeyCenter.shared,id="native-focus-lease-test",combo=SentinelCombo(mainKey:"F12")
 check("register physical capture",center.register(tokens:combo.tokens,id:id) {})
 let released=NativeFocusCaptureLease.apply(route:.physicalShortcut,isCaptured:{center.isRegistered(id)},capture:{false},release:{center.unregister(id)})
 check("real capture released",released == .physicalShortcut && !center.isRegistered(id))
 let restored=NativeFocusCaptureLease.apply(route:.captureForNavigation,isCaptured:{center.isRegistered(id)},capture:{center.register(tokens:combo.tokens,id:id) {}},release:{center.unregister(id)})
 check("real capture restored",restored == .captured && center.isRegistered(id))
 center.unregister(id);check("no test capture retained",!center.isRegistered(id))
}
print("Native focus checks: \(checks), failures: \(failures). No synthetic input, AX, target UI access or device writes.")
exit(failures == 0 ? 0 : 1)
