import Foundation
import VibeKitHost

var count = 0, failures = 0
func check(_ name: String, _ ok: @autoclosure () -> Bool) {
    count += 1; if !ok() { failures += 1; print("FAIL \(name)") }
}
let first = "00000000-0000-0000-0000-000000000001", second = "00000000-0000-0000-0000-000000000002"
let named: [String: Any] = ["id":first,"name":"真实会话标题","preview":"不要把首条提示词当作标题", "cwd":"/tmp/project-one", "updatedAt":30]
let unnamed: [String: Any] = ["id":second,"name":NSNull(),"preview":"private prompt", "cwd":"/tmp/project-two","updatedAt":20]
do {
    let page = try CodexThreadListClient.parsePage(["data":[named,unnamed,["id":"not-a-thread"]],"nextCursor":"next"])
    check("valid page retains server order", page.threads.map(\.session.id) == [first,second])
    check("server name retained", page.threads[0].session.title == "真实会话标题")
    check("preview never used as title", !page.threads[1].session.title.contains("private") && page.threads[1].session.title.contains("未命名"))
    check("project derived from cwd", page.threads[0].project == "project-one")
    check("cursor preserved", page.cursor == "next")
    check("invalid id counted", page.rejected == 1)
    let empty = try CodexThreadListClient.parsePage(["data":[],"nextCursor":NSNull()])
    check("empty listing is successful", empty.threads.isEmpty && empty.cursor == nil)
    do { _ = try CodexThreadListClient.parsePage(["data":[],"nextCursor":17]); check("bad cursor rejected",false) }
    catch { check("bad cursor rejected",true) }
    do { _ = try CodexThreadListClient.parsePage(["data":"bad"]); check("bad data rejected",false) }
    catch { check("bad data rejected",true) }
    let long = try CodexThreadListClient.parsePage(["data":[["id":first,"name":String(repeating:"a",count:500)]]])
    check("server long title not silently truncated", long.threads.first?.session.title.count == 500 && long.threads[0].session.isValid)
    let pin = CodexSession(reference:first,title:"older alias")!
    let offline = CodexSession(reference:"00000000-0000-0000-0000-000000000003",title:"离线固定会话")!
    let merged = CodexSessionCatalog.merge(pinned:[pin,pin,offline],recent:page.threads)
    check("pinned dedup and recent merge", merged.map(\.id) == [first,offline.id,second])
    check("server title authoritative", merged[0].title == "真实会话标题")
    check("offline pin retained", merged[1] == offline)
    let projects = Dictionary(uniqueKeysWithValues:page.threads.map{($0.session.id,$0.project)})
    check("search by Chinese title", CodexSessionCatalog.filter(merged,query:"真实",projects:projects).map(\.id) == [first])
    check("search by case-insensitive project", CodexSessionCatalog.filter(merged,query:"PROJECT-TWO",projects:projects).map(\.id) == [second])
    check("search by id", CodexSessionCatalog.filter(merged,query:second,projects:projects).map(\.id) == [second])
    check("empty search keeps order", CodexSessionCatalog.filter(merged,query:"  ",projects:projects) == merged)
    var nav = CodexNavigation(); nav.enter(sessions:merged); nav.select(id:second)
    nav.enter(sessions:[offline,pin,page.threads[1].session],preferredID:second)
    check("explicit refresh preserves highlighted id", nav.selected?.id == second)
} catch { check("metadata parsing threw unexpectedly",false) }

let temp = FileManager.default.temporaryDirectory.appendingPathComponent("vibekey-thread-tests-"+UUID().uuidString)
try FileManager.default.createDirectory(at:temp,withIntermediateDirectories:true)
defer { try? FileManager.default.removeItem(at:temp) }
let fixture = temp.appendingPathComponent("server.py"), audit = temp.appendingPathComponent("audit.jsonl")
let script = #"""
import sys,json,time
mode=sys.argv[1];audit=sys.argv[2]
if mode=='closed':sys.exit(0)
page=0
for line in sys.stdin:
 r=json.loads(line)
 with open(audit,'a') as f:f.write(json.dumps(r)+'\n')
 assert r['method'] in ['initialize','initialized','thread/list']
 if r['method']=='initialized':continue
 if r['method']=='initialize':
  if mode=='timeout':time.sleep(5)
  print(json.dumps({'id':r['id'],'result':{}}),flush=True);continue
 p=r['params'];assert p['archived'] is False and p['modelProviders']==[] and p['useStateDbOnly'] is True
 assert p['sortKey']=='updated_at' and 'searchTerm' not in p and 'cwd' not in p
 if mode=='error':print(json.dumps({'id':r['id'],'error':{'code':123,'message':'test-only error'}}),flush=True);continue
 if mode=='malformed':print('invalid JSON',flush=True);continue
 page+=1
 one={'id':'00000000-0000-0000-0000-000000000001','name':'first','preview':'x'*90000,'cwd':'/tmp/project','updatedAt':9}
 two={'id':'00000000-0000-0000-0000-000000000002','name':'second','cwd':'/tmp/project','updatedAt':8}
 data=[one] if page==1 else [one,two]
 result={'data':data,'nextCursor':'next' if page==1 or mode=='loop' else None}
 # Notification before a large (>64 KiB) JSONL response must not desynchronize the reader.
 print(json.dumps({'method':'test/notification','params':{}}),flush=True)
 print(json.dumps({'id':r['id'],'result':result}),flush=True)
"""#
try script.write(to:fixture,atomically:true,encoding:.utf8)
func client(_ mode:String) -> CodexThreadListClient {
    CodexThreadListClient(executable:URL(fileURLWithPath:"/usr/bin/python3"),arguments:[fixture.path,mode,audit.path])
}
do {
    let result = try client("normal").fetch(timeout:5)
    check("real subprocess pagination and oversized line", result.threads.count == 2 && result.pages == 2 && !result.hasMore)
    check("duplicates across pages removed", result.threads.map(\.session.id) == [first,second])
    let requests = try String(contentsOf:audit,encoding:.utf8).split(separator:"\n").map { try JSONSerialization.jsonObject(with:Data($0.utf8)) as! [String:Any] }
    check("only read-only RPCs sent", requests.compactMap{$0["method"] as? String} == ["initialize","initialized","thread/list","thread/list"])
    let limited = try client("normal").fetch(maximumPages:1,timeout:5)
    check("bounded pagination reports incomplete coverage", limited.pages == 1 && limited.hasMore)
} catch { print(error); check("normal subprocess did not complete",false) }
for (mode,expected) in [("loop",CodexThreadListFailure.paginationLoop),("error",.serverRejected),("malformed",.malformedReply),("timeout",.timeout),("closed",.malformedReply)] {
    do { _ = try client(mode).fetch(timeout:mode=="timeout" ? 0.15 : 5); check("\(mode) should fail",false) }
    catch let error as CodexThreadListFailure { check("\(mode) bounded failure", String(describing:error) == String(describing:expected)) }
    catch { check("\(mode) unexpected error type",false) }
}
do { _ = try client("normal").fetch(cancelled:{true});check("cancel should fail",false) }
catch let error as CodexThreadListFailure { check("cancel reported",String(describing:error)=="cancelled") }
catch { check("cancel error type",false) }
print("Thread-list checks: \(count), failures: \(failures). Fixtures only; no hardware or Codex control.")
exit(failures == 0 ? 0 : 1)
