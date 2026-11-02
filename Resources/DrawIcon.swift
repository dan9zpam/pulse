import Cocoa
let size: CGFloat = 1024
let image = NSImage(size:NSSize(width:size,height:size))
image.lockFocus()
let rect = NSRect(x:40,y:40,width:944,height:944)
let shape = NSBezierPath(roundedRect:rect,xRadius:220,yRadius:220)
NSColor(calibratedRed:0.065,green:0.085,blue:0.11,alpha:1).setFill(); shape.fill()
NSGradient(starting:NSColor(calibratedRed:0.15,green:0.25,blue:0.25,alpha:1),ending:NSColor(calibratedRed:0.045,green:0.055,blue:0.085,alpha:1))?.draw(in:shape,angle:-65)
let path = NSBezierPath(); path.move(to:NSPoint(x:180,y:492))
for p in [NSPoint(x:333,y:492),NSPoint(x:403,y:660),NSPoint(x:510,y:310),NSPoint(x:605,y:560),NSPoint(x:655,y:492),NSPoint(x:844,y:492)] { path.line(to:p) }
path.lineWidth = 49; path.lineCapStyle = .round; path.lineJoinStyle = .round
NSColor(calibratedRed:0.43,green:0.91,blue:0.76,alpha:1).setStroke(); path.stroke()
image.unlockFocus()
let dir = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath:dir,withIntermediateDirectories:true)
for s in [16,32,128,256,512] {
    for scale in [1,2] {
        let pixels = s*scale
        let rep = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:pixels,pixelsHigh:pixels,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:rep)
        image.draw(in:NSRect(x:0,y:0,width:pixels,height:pixels),from:.zero,operation:.copy,fraction:1)
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try rep.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"\(dir)/icon_\(s)x\(s)\(suffix).png"))
    }
}
