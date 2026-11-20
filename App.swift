import UIKit
import WebKit
import Network

// This loopback-only server starts inside the app. It gives WebKit a stable
// origin for IndexedDB and local fetch; no PC, hosting or public listener.
final class LocalAssets {
 let queue = DispatchQueue(label: "nl.atelier.assets")
 var listener: NWListener?
 let base: URL
 init(base: URL) { self.base = base.standardizedFileURL }
 func start(_ ready: @escaping (Bool) -> Void) throws {
  let p = NWParameters.tcp
  p.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: 18781)
  let l = try NWListener(using: p); listener = l
  l.stateUpdateHandler = { state in switch state { case .ready: DispatchQueue.main.async { ready(true) }; case .failed: DispatchQueue.main.async { ready(false) }; default: break } }
  l.newConnectionHandler = { [weak self] c in self?.receive(c) }; l.start(queue: queue)
 }
 func receive(_ c: NWConnection) {
  c.start(queue: queue)
  func read(_ accumulated: Data) {
   c.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, done, error in
    guard let self else { c.cancel(); return }
    var bytes = accumulated; if let data { bytes.append(data) }
    if bytes.count > 16384 || error != nil { c.cancel(); return }
    guard bytes.range(of: Data("\r\n\r\n".utf8)) != nil else { if done { c.cancel() } else { read(bytes) }; return }
    let line = String(decoding: bytes, as: UTF8.self).components(separatedBy: "\r\n").first ?? ""
    let parts = line.split(separator: " "); var payload = Data(); var code = "404 Not Found"; var mime = "text/plain"
    if parts.count == 3, parts[0] == "GET", let raw = String(parts[1]).components(separatedBy: "?").first?.removingPercentEncoding, raw.hasPrefix("/"), !raw.contains(".."), !raw.contains("\\"), !raw.contains("\0") {
     let path = raw == "/" ? "index.html" : String(raw.dropFirst()); let file = self.base.appendingPathComponent(path).standardizedFileURL
     if file.path.hasPrefix(self.base.path + "/"), let data = try? Data(contentsOf: file, options: .mappedIfSafe) {
      payload = data; code = "200 OK"; mime = ["html":"text/html; charset=utf-8", "js":"text/javascript; charset=utf-8", "css":"text/css; charset=utf-8", "jpg":"image/jpeg", "png":"image/png"][file.pathExtension] ?? "application/octet-stream"
     }
    }
    var response = Data("HTTP/1.1 \(code)\r\nContent-Type: \(mime)\r\nContent-Length: \(payload.count)\r\nConnection: close\r\nCache-Control: no-cache\r\nX-Content-Type-Options: nosniff\r\n\r\n".utf8); response.append(payload)
    c.send(content: response, completion: .contentProcessed { _ in c.cancel() })
   }
  }
  read(Data())
 }
}

@main final class AppDelegate: UIResponder, UIApplicationDelegate {
 var window: UIWindow?
 func application(_ app: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
  let w = UIWindow(frame: UIScreen.main.bounds); w.rootViewController = AtelierController(); window = w; w.makeKeyAndVisible(); return true
 }
}

final class AtelierController: UIViewController, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
 var web: WKWebView!; var assets: LocalAssets?; var exportFile: URL?
 #if SIMULATOR_SMOKE
 func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { recordSmoke(0) }
 func recordSmoke(_ attempt: Int) {
  web.evaluateJavaScript("window.__containerSmoke || null") { [weak self] value, error in
   guard let self else { return }
   if let result = value as? [String:Any], let folder = FileManager.default.urls(for:.documentDirectory,in:.userDomainMask).first, let data = try? JSONSerialization.data(withJSONObject:result,options:.prettyPrinted) { try? data.write(to:folder.appendingPathComponent("container-smoke.json")); return }
   if attempt < 100 { DispatchQueue.main.asyncAfter(deadline:.now()+0.3) { [weak self] in self?.recordSmoke(attempt+1) } }
  }
 }
 #endif
 override func viewDidLoad() {
  super.viewDidLoad(); view.backgroundColor = UIColor(red:0.96,green:0.95,blue:0.92,alpha:1)
  let config = WKWebViewConfiguration(); config.websiteDataStore = .default(); config.userContentController.add(self, name: "AtelierNative")
  web = WKWebView(frame:.zero,configuration:config); web.navigationDelegate = self; web.uiDelegate = self; web.isOpaque = false; web.backgroundColor = view.backgroundColor; web.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(web)
  NSLayoutConstraint.activate([web.leadingAnchor.constraint(equalTo:view.safeAreaLayoutGuide.leadingAnchor),web.trailingAnchor.constraint(equalTo:view.safeAreaLayoutGuide.trailingAnchor),web.topAnchor.constraint(equalTo:view.safeAreaLayoutGuide.topAnchor),web.bottomAnchor.constraint(equalTo:view.safeAreaLayoutGuide.bottomAnchor)])
  guard let folder = Bundle.main.resourceURL?.appendingPathComponent("web") else { fail(); return }
  assets = LocalAssets(base:folder)
  do { try assets?.start { [weak self] ok in if ok { self?.web.load(URLRequest(url:URL(string:"http://127.0.0.1:18781/")!)) } else { self?.fail() } } } catch { fail() }
 }
 func fail() { let a = UIAlertController(title:"Atelier kon niet starten",message:"Sluit de app volledig en open opnieuw. Je bewaarde ontwerpen blijven op dit toestel.",preferredStyle:.alert);a.addAction(UIAlertAction(title:"OK",style:.default));present(a,animated:true) }
 func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy)->Void) {
  guard let u = action.request.url else { decisionHandler(.cancel);return }
  if u.scheme == "http", u.host == "127.0.0.1", u.port == 18781 { decisionHandler(.allow);return }
  decisionHandler(.cancel)
  if action.navigationType == .linkActivated, u.scheme == "https" { UIApplication.shared.open(u) }
 }
 func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
  guard message.frameInfo.isMainFrame, message.frameInfo.request.url?.host == "127.0.0.1", message.frameInfo.request.url?.port == 18781, presentedViewController == nil,
   let o = message.body as? [String:String], let raw = o["data"], raw.count <= 46000000, let data = Data(base64Encoded:raw), data.count <= 32*1024*1024 else { return }
  let name = String((o["name"] ?? "Atelier-export").replacingOccurrences(of:"/",with:"_").replacingOccurrences(of:"\\",with:"_").filter { !$0.isNewline && $0.asciiValue != 0 }.prefix(180))
  guard !name.isEmpty, name != ".", name != ".." else { return }
  let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory:true).appendingPathComponent(name)
  do {
   try FileManager.default.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true);try data.write(to:file,options:.atomic);exportFile = file
   let sheet = UIActivityViewController(activityItems:[file],applicationActivities:nil)
   sheet.popoverPresentationController?.sourceView = view;sheet.popoverPresentationController?.sourceRect = CGRect(x:view.bounds.midX,y:view.bounds.midY,width:1,height:1)
   sheet.completionWithItemsHandler = { [weak self] _,_,_,_ in try? FileManager.default.removeItem(at:file.deletingLastPathComponent()); self?.exportFile = nil };present(sheet,animated:true)
  } catch { let a = UIAlertController(title:"Export niet gelukt",message:"Je ontwerp staat nog in Atelier. Probeer opnieuw.",preferredStyle:.alert);a.addAction(UIAlertAction(title:"OK",style:.default));present(a,animated:true) }
 }
 func webView(_ w: WKWebView, runJavaScriptAlertPanelWithMessage message:String, initiatedByFrame frame:WKFrameInfo, completionHandler:@escaping ()->Void) { let a=UIAlertController(title:"Atelier",message:message,preferredStyle:.alert);a.addAction(UIAlertAction(title:"OK",style:.default){_ in completionHandler()});present(a,animated:true) }
 func webView(_ w: WKWebView, runJavaScriptConfirmPanelWithMessage message:String, initiatedByFrame frame:WKFrameInfo, completionHandler:@escaping (Bool)->Void) { let a=UIAlertController(title:"Atelier",message:message,preferredStyle:.alert);a.addAction(UIAlertAction(title:"OK",style:.default){_ in completionHandler(true)});a.addAction(UIAlertAction(title:"Annuleren",style:.cancel){_ in completionHandler(false)});present(a,animated:true) }
}
