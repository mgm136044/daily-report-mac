import AppKit
import CoreImage

/// KakaoPay 후원 QR. The QR is REGENERATED at runtime from the payment URL via
/// CoreImage — NOT shipped as a bundled image, because `Bundle.module` image
/// resources can crash on some Macs' release builds (fatalError when the bundle
/// isn't found). A runtime-drawn QR is also
/// crisp at any size and needs no white-chrome screenshot ("show only the QR").
enum CoffeeQR {
    /// The developer's KakaoPay transfer URL that the QR encodes. Decoded from the
    /// provided KakaoPay QR screenshot (not the screenshot itself).
    static let kakaoPayURL = "https://qr.kakaopay.com/2810060111129813800079878ca04632"

    /// Draw a clean QR for `kakaoPayURL` at `side` points (2× for retina crispness).
    static func image(side: CGFloat) -> NSImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(kakaoPayURL.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage, output.extent.width > 0 else { return nil }
        // Nearest sampling so QR modules stay hard-edged when scaled up.
        let scale = (side * 2) / output.extent.width
        let scaled = output.samplingNearest().transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let rep = NSCIImageRep(ciImage: scaled)
        let image = NSImage(size: NSSize(width: side, height: side))
        image.addRepresentation(rep)
        return image
    }
}
