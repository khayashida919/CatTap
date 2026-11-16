import UIKit
import Vision
import CoreImage
import os

/// 利用者が写真から作ったおもちゃの画像を作り、アプリの中に保存する
///
/// 画像は Application Support/PhotoToys に PNG で保存し、
/// 登録した順番は `App.shared.photoToyIDs` に持つ。
enum PhotoToyStore {

    /// 登録できる数の上限
    static let maxCount = 3

    /// 保存する画像の長辺の上限（ピクセル）
    private static let maxPixelLength: CGFloat = 512

    private static let logger = Logger(subsystem: "kayashida.CatTap", category: "PhotoToy")

    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("PhotoToys", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).png")
    }

    /// 登録済みで、画像ファイルが残っているおもちゃのID
    static var ids: [UUID] {
        App.shared.photoToyIDs.filter { FileManager.default.fileExists(atPath: fileURL(for: $0).path) }
    }

    static var canAdd: Bool {
        ids.count < maxCount
    }

    static func image(for id: UUID) -> UIImage? {
        UIImage(contentsOfFile: fileURL(for: id).path)
    }

    /// 写真からおもちゃの画像を作って保存し、新しいIDを返す。
    /// 切り抜きに時間がかかるので、メインスレッド以外で呼ぶ
    static func add(from photo: UIImage) throws -> UUID {
        let toyImage = makeToyImage(from: photo)
        guard let data = toyImage.pngData() else {
            throw CocoaError(.fileWriteUnknown)
        }
        let id = UUID()
        try data.write(to: fileURL(for: id), options: .atomic)
        return id
    }

    /// 登録の一覧に加える。メインスレッドで呼ぶ
    static func register(_ id: UUID) {
        App.shared.photoToyIDs = ids + [id]
    }

    /// 削除する。選択中のおもちゃだったときは虫に戻す。メインスレッドで呼ぶ
    static func remove(_ id: UUID) {
        try? FileManager.default.removeItem(at: fileURL(for: id))
        App.shared.photoToyIDs = App.shared.photoToyIDs.filter { $0 != id }
        if App.shared.toy == .photo(id) {
            App.shared.toy = .standard(.bug)
        }
    }

    // MARK: - 画像の加工

    /// iOS 17 以上では写っている猫や物だけを切り抜く。
    /// それより前の iOS と、切り抜けなかったときは丸く切り抜く
    static func makeToyImage(from photo: UIImage) -> UIImage {
        let normalized = resized(photo, maxLength: 1024)
        let cutout: UIImage
        if #available(iOS 17.0, *), let foreground = foregroundImage(of: normalized) {
            cutout = foreground
        } else {
            cutout = circleImage(of: normalized)
        }
        return resized(cutout, maxLength: maxPixelLength)
    }

    @available(iOS 17.0, *)
    private static func foregroundImage(of image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        do {
            return try foregroundImage(of: cgImage)
        } catch {
            // シミュレータでは切り抜き用のモデルを動かせず、
            // 「Could not create inference context」で失敗する（CPU を指定しても同じ）
            logger.error("切り抜きに失敗しました: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// 写っている猫や物を切り抜く。被写体が見つからないときは nil を返す
    @available(iOS 17.0, *)
    private static func foregroundImage(of cgImage: CGImage) throws -> UIImage? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])
        guard let result = request.results?.first, !result.allInstances.isEmpty else {
            logger.notice("切り抜く被写体が見つかりませんでした")
            return nil
        }
        let buffer = try result.generateMaskedImage(ofInstances: result.allInstances,
                                                    from: handler,
                                                    croppedToInstancesExtent: true)
        let ciImage = CIImage(cvPixelBuffer: buffer)
        guard let output = CIContext().createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        return UIImage(cgImage: output)
    }

    /// 中央を正方形に切り取り、丸く切り抜く
    private static func circleImage(of image: UIImage) -> UIImage {
        let side = min(image.size.width, image.size.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: side, height: side)).addClip()
            image.draw(at: CGPoint(x: (side - image.size.width) / 2, y: (side - image.size.height) / 2))
        }
    }

    /// 長辺が maxLength ピクセル以下になるように縮める。
    /// 描き直すので、写真の向き（imageOrientation）もここで正しい向きにそろう
    private static func resized(_ image: UIImage, maxLength: CGFloat) -> UIImage {
        let pixelSize = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let ratio = min(1, maxLength / max(pixelSize.width, pixelSize.height))
        let size = CGSize(width: (pixelSize.width * ratio).rounded(), height: (pixelSize.height * ratio).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
