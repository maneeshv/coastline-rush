import AppKit
let output = CommandLine.arguments[1]
let fm = FileManager.default
try fm.createDirectory(atPath: output, withIntermediateDirectories: true)
func render(_ size: Int, _ path: String) throws {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(size)/1024, y: CGFloat(size)/1024)
    NSColor(calibratedRed: 0.04, green: 0.25, blue: 0.28, alpha: 1).setFill()
    NSBezierPath(rect: NSRect(x:0,y:0,width:1024,height:1024)).fill()
    NSColor(calibratedRed: 1, green: 0.44, blue: 0.27, alpha: 1).setFill()
    NSBezierPath(ovalIn:NSRect(x:498,y:548,width:355,height:355)).fill()
    NSColor(calibratedRed: 0.29, green: 0.69, blue: 0.64, alpha: 1).setFill()
    let sea=NSBezierPath(); sea.move(to:NSPoint(x:0,y:410));sea.curve(to:NSPoint(x:1024,y:340),controlPoint1:NSPoint(x:390,y:690),controlPoint2:NSPoint(x:690,y:150));sea.line(to:NSPoint(x:1024,y:0));sea.line(to:NSPoint(x:0,y:0));sea.close();sea.fill()
    NSColor(calibratedRed: 1, green: 0.93, blue: 0.77, alpha: 1).setFill()
    let track=NSBezierPath();track.move(to:NSPoint(x:480,y:540));track.line(to:NSPoint(x:540,y:540));track.line(to:NSPoint(x:860,y:0));track.line(to:NSPoint(x:165,y:0));track.close();track.fill()
    NSColor(calibratedRed: 0.96, green: 0.63, blue: 0.42, alpha: 1).setStroke()
    for ratio in [0.34,0.66] {let p=NSBezierPath();p.lineWidth=11;p.move(to:NSPoint(x:480+60*ratio,y:540));p.line(to:NSPoint(x:165+695*ratio,y:0));p.stroke()}
    // The courier's rounded running silhouette.
    NSColor(calibratedRed: 0.06, green: 0.27, blue: 0.29, alpha: 1).setStroke()
    let body=NSBezierPath();body.lineWidth=62;body.lineCapStyle = .round;body.lineJoinStyle = .round
    body.move(to:NSPoint(x:499,y:610));body.line(to:NSPoint(x:462,y:414));body.line(to:NSPoint(x:369,y:306));body.move(to:NSPoint(x:461,y:425));body.line(to:NSPoint(x:569,y:345));body.line(to:NSPoint(x:556,y:232));body.move(to:NSPoint(x:487,y:544));body.line(to:NSPoint(x:387,y:497));body.line(to:NSPoint(x:331,y:569));body.move(to:NSPoint(x:489,y:545));body.line(to:NSPoint(x:588,y:472));body.line(to:NSPoint(x:650,y:525));body.stroke()
    NSColor(calibratedRed: 1, green: 0.93, blue: 0.77, alpha: 1).setFill();NSBezierPath(ovalIn:NSRect(x:461,y:615,width:100,height:110)).fill()
    NSColor(calibratedRed: 1, green: 0.44, blue: 0.27, alpha: 1).setFill();NSBezierPath(roundedRect:NSRect(x:425,y:445,width:85,height:130),xRadius:25,yRadius:25).fill()
    for (x,y,r) in [(655.0,640.0,25.0),(733,731,20),(794,804,15)] {
        NSColor(calibratedRed: 1, green: 0.80, blue: 0.29, alpha: 1).setFill();NSBezierPath(ovalIn:NSRect(x:x,y:y,width:r*2,height:r*2)).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:path))
}
var images:[[String:Any]]=[]
for idiom in ["iphone", "ipad", "mac"] {
    let sizes: [Double] = idiom == "iphone" ? [20,29,40,60] : (idiom == "ipad" ? [20,29,40,76,83.5] : [16,32,128,256,512])
    for size in sizes {
        let scales = idiom == "iphone" ? [2,3] : (size == 83.5 ? [2] : [1,2])
        for scale in scales {
            let filename="\(idiom)-\(size)-\(scale).png"
            try render(Int(size*Double(scale)),output+"/"+filename)
            let label=size.truncatingRemainder(dividingBy:1)==0 ? String(Int(size)) : String(size)
            images.append(["idiom":idiom,"size":"\(label)x\(label)","scale":"\(scale)x","filename":filename])
        }
    }
}
try render(1024,output+"/store.png")
images.append(["idiom":"ios-marketing","size":"1024x1024","scale":"1x","filename":"store.png"])
let data=try JSONSerialization.data(withJSONObject:["images":images,"info":["version":1,"author":"xcode"]], options:[.prettyPrinted,.sortedKeys])
try data.write(to:URL(fileURLWithPath:output+"/Contents.json"))
print("App icon generated for iOS and macOS")
