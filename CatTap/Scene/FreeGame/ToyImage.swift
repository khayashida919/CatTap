import UIKit

/// 画像素材を使わずにコードで描くおもちゃの画像。
/// キャンバスの大きさは、大きさ「大きい」のときの表示サイズ（pt）にそろえてある。
/// 縦横比を変えるときは、ToyScene.setUp(_:as:) と PaywallPreviewScene.baseSize(for:) の数値も合わせる
enum ToyImage {

    /// レーザーポインターの赤い点。ゲーム中は回るので、どの向きから見ても同じ形に描く
    static let laser: UIImage = render(width: 140, height: 140) { context in
        let center = CGPoint(x: 70, y: 70)
        // 周りのぼんやりした光。画像の端より手前で透明にする
        radial(context, center: center, radius: 66, stops: [
            (0, color(0xFF1A1A, alpha: 0.6)),
            (0.34, color(0xFF1A1A, alpha: 0.4)),
            (0.56, color(0xFF1A1A, alpha: 0.19)),
            (0.78, color(0xFF1A1A, alpha: 0.06)),
            (1, color(0xFF1A1A, alpha: 0)),
        ])
        // 芯のすぐ外のにじみ。芯の縁と同じ赤から始めて、境目を作らない
        radial(context, center: center, radius: 38, stops: [
            (0, color(0xFF1414)),
            (0.55, color(0xFF1414)),
            (0.72, color(0xFF1C18, alpha: 0.58)),
            (1, color(0xFF1C18, alpha: 0)),
        ])
        // 芯。中心は白く光らせ、外へ向かって濃い赤にする
        radial(context, center: center, radius: 21, stops: [
            (0, .white),
            (0.24, color(0xFFF4EE)),
            (0.5, color(0xFF8A72)),
            (0.78, color(0xFF3626)),
            (1, color(0xFF1414)),
        ])
    }

    /// ねこじゃらし（エノコログサ）。ふさふさの穂と茎と葉。画像の中心で左右に揺れる
    static let teaser: UIImage = render(width: 140, height: 280) { context in
        let line = color(0x2E6B2C)
        let fuzzLine = color(0x6F8C24)

        /// 茎から出る葉。root から tip へ伸びる。outer と inner は、両側の縁を曲げる制御点
        func drawLeaf(root: CGPoint, tip: CGPoint, outer: (CGPoint, CGPoint), inner: (CGPoint, CGPoint)) {
            let leaf = UIBezierPath()
            leaf.move(to: root)
            leaf.addCurve(to: tip, controlPoint1: outer.0, controlPoint2: outer.1)
            leaf.addCurve(to: root, controlPoint1: inner.0, controlPoint2: inner.1)
            leaf.close()
            linear(context, in: leaf, from: root, to: tip, stops: [(0, color(0x4A9A38)), (1, color(0x9FDB5A))])
            stroke(leaf, color: line, width: 4)
            // 葉の真ん中の筋
            let rib = UIBezierPath()
            rib.move(to: CGPoint(x: root.x + (tip.x - root.x) * 0.12, y: root.y + (tip.y - root.y) * 0.12))
            rib.addQuadCurve(to: CGPoint(x: root.x + (tip.x - root.x) * 0.8, y: root.y + (tip.y - root.y) * 0.8),
                             controlPoint: CGPoint(x: (outer.0.x + inner.1.x) / 2, y: (outer.0.y + inner.1.y) / 2))
            stroke(rib, color: color(0xD9F4A6, alpha: 0.9), width: 2.4)
        }
        drawLeaf(root: CGPoint(x: 66, y: 246), tip: CGPoint(x: 128, y: 178),
                 outer: (CGPoint(x: 78, y: 214), CGPoint(x: 104, y: 192)),
                 inner: (CGPoint(x: 120, y: 210), CGPoint(x: 94, y: 236)))
        drawLeaf(root: CGPoint(x: 65, y: 260), tip: CGPoint(x: 14, y: 214),
                 outer: (CGPoint(x: 56, y: 236), CGPoint(x: 34, y: 222)),
                 inner: (CGPoint(x: 22, y: 240), CGPoint(x: 42, y: 256)))

        // 茎。濃い線の上に細い線を重ねて、輪郭付きにする
        let stem = UIBezierPath()
        stem.move(to: CGPoint(x: 66, y: 164))
        stem.addCurve(to: CGPoint(x: 66, y: 271),
                      controlPoint1: CGPoint(x: 72, y: 200), controlPoint2: CGPoint(x: 60, y: 238))
        stroke(stem, color: line, width: 9.5)
        stroke(stem, color: color(0x6DB742), width: 4.5)

        // 穂の芯が通る線（根元から先へ）。先が少しおじぎする
        let base = CGPoint(x: 66, y: 170)
        let bend = CGPoint(x: 54, y: 92)
        let tip = CGPoint(x: 86, y: 26)
        /// 芯の線の上の点と、その場所での向き
        func axis(_ t: CGFloat) -> (point: CGPoint, tangent: CGVector) {
            let u = 1 - t
            let point = CGPoint(x: u * u * base.x + 2 * u * t * bend.x + t * t * tip.x,
                                y: u * u * base.y + 2 * u * t * bend.y + t * t * tip.y)
            let dx = 2 * u * (bend.x - base.x) + 2 * t * (tip.x - bend.x)
            let dy = 2 * u * (bend.y - base.y) + 2 * t * (tip.y - bend.y)
            let length = (dx * dx + dy * dy).squareRoot()
            return (point, CGVector(dx: dx / length, dy: dy / length))
        }
        /// 穂の太さの半分。根元から 4 割ほどのところがいちばん太い
        func halfWidth(_ t: CGFloat) -> CGFloat {
            5 + 15 * pow(sin(.pi * pow(t, 0.74)), 0.7)
        }
        /// 芯の線から、向き tangent を angle だけ回した方向へ distance 進んだ点
        func offset(_ point: CGPoint, _ tangent: CGVector, angle: CGFloat, distance: CGFloat) -> CGPoint {
            CGPoint(x: point.x + (tangent.dx * cos(angle) - tangent.dy * sin(angle)) * distance,
                    y: point.y + (tangent.dx * sin(angle) + tangent.dy * cos(angle)) * distance)
        }

        /// ふさふさの穂の形。縁に、先へ向かってなびく毛の房を並べる。
        /// 毎回同じ形になるように、乱数ではなく番号から房の長さを決める
        func fur(scale: CGFloat, tufts: Int, length: CGFloat) -> UIBezierPath {
            /// 芯の線から横へ、太さの分だけ離れた点。push でさらに外へ押し出す
            func edge(_ t: CGFloat, _ side: CGFloat, push: CGFloat = 0) -> CGPoint {
                let (point, tangent) = axis(min(max(t, 0), 1))
                return offset(point, tangent, angle: side * .pi / 2, distance: halfWidth(t) * scale + push)
            }
            /// 房の先の点と、その房の長さ
            func tuftTip(_ index: Int, _ side: CGFloat) -> (point: CGPoint, length: CGFloat) {
                let t = (CGFloat(index) + 0.85) / CGFloat(tufts)
                let wobble = CGFloat((index * 37 + (side > 0 ? 11 : 0)) % 7) / 6
                let tuftLength = length * (0.75 + 0.5 * wobble) * (0.55 + 0.45 * sin(.pi * t))
                let (_, tangent) = axis(t)
                return (offset(edge(t, side), tangent, angle: side * 0.8, distance: tuftLength), tuftLength)
            }
            let path = UIBezierPath()
            path.move(to: edge(0, -1))
            // 左側を根元から先へ
            for index in 0..<tufts {
                let from = CGFloat(index) / CGFloat(tufts)
                let to = CGFloat(index + 1) / CGFloat(tufts)
                let tuft = tuftTip(index, -1)
                path.addQuadCurve(to: tuft.point, controlPoint: edge(from + (to - from) * 0.4, -1, push: tuft.length * 0.6))
                path.addQuadCurve(to: edge(to, -1), controlPoint: edge(to, -1, push: tuft.length * 0.2))
            }
            // 穂先
            let (tipPoint, tipTangent) = axis(1)
            let apex = offset(tipPoint, tipTangent, angle: 0, distance: length * 1.1)
            path.addQuadCurve(to: apex, controlPoint: offset(edge(1, -1), tipTangent, angle: 0, distance: length * 0.4))
            path.addQuadCurve(to: edge(1, 1), controlPoint: offset(edge(1, 1), tipTangent, angle: 0, distance: length * 0.4))
            // 右側を先から根元へ
            for index in (0..<tufts).reversed() {
                let from = CGFloat(index) / CGFloat(tufts)
                let to = CGFloat(index + 1) / CGFloat(tufts)
                let tuft = tuftTip(index, 1)
                path.addQuadCurve(to: tuft.point, controlPoint: edge(to, 1, push: tuft.length * 0.2))
                path.addQuadCurve(to: edge(from, 1), controlPoint: edge(from + (to - from) * 0.4, 1, push: tuft.length * 0.6))
            }
            // 根元は丸く閉じる
            let (basePoint, baseTangent) = axis(0)
            path.addQuadCurve(to: edge(0, -1), controlPoint: offset(basePoint, baseTangent, angle: .pi, distance: halfWidth(0) * scale * 1.6))
            path.close()
            return path
        }

        // 穂。外側の毛の上に、明るい内側の毛を重ねる
        let outer = fur(scale: 1, tufts: 17, length: 12.5)
        linear(context, in: outer, from: CGPoint(x: 34, y: 0), to: CGPoint(x: 100, y: 0),
               stops: [(0, color(0xF3EE80)), (0.5, color(0xDADB55)), (1, color(0xACB937))])
        stroke(outer, color: fuzzLine, width: 3.2)
        let inner = fur(scale: 0.5, tufts: 12, length: 7)
        linear(context, in: inner, from: CGPoint(x: 50, y: 0), to: CGPoint(x: 90, y: 0),
               stops: [(0, color(0xFDFBCB)), (1, color(0xE9EA82))])

        // 内側の毛並み
        let marks = 8
        for mark in 0..<marks {
            let t = 0.14 + 0.7 * CGFloat(mark) / CGFloat(marks - 1)
            let (point, tangent) = axis(t)
            let side: CGFloat = mark.isMultiple(of: 2) ? 1 : -1
            let start = offset(point, tangent, angle: side * .pi / 2, distance: halfWidth(t) * 0.16)
            let dash = UIBezierPath()
            dash.move(to: start)
            dash.addQuadCurve(to: offset(start, tangent, angle: side * 0.45, distance: 8),
                              controlPoint: offset(start, tangent, angle: side * 0.9, distance: 4))
            stroke(dash, color: color(0xC3CA4E), width: 2.4)
        }
    }

    /// ねずみ。右を向いた姿で描く（走る向きに合わせてシーン側で左右を反転する）
    static let mouse: UIImage = render(width: 240, height: 160) { context in
        let line = color(0x2F3A5C)
        let pink = color(0xF9A8BC)
        let outline: CGFloat = 5

        // しっぽ。濃い線の上に細いピンクを重ねて、輪郭付きにする
        let tail = UIBezierPath()
        tail.move(to: CGPoint(x: 52, y: 122))
        tail.addCurve(to: CGPoint(x: 18, y: 80),
                      controlPoint1: CGPoint(x: 26, y: 130), controlPoint2: CGPoint(x: 10, y: 106))
        tail.addCurve(to: CGPoint(x: 44, y: 34),
                      controlPoint1: CGPoint(x: 24, y: 58), controlPoint2: CGPoint(x: 52, y: 56))
        stroke(tail, color: line, width: 13.5)
        stroke(tail, color: pink, width: 6)

        // 奥の耳
        let farEar = UIBezierPath(arcCenter: CGPoint(x: 177, y: 51), radius: 22, startAngle: 0, endAngle: .pi * 2, clockwise: true)
        color(0x7088B8).setFill()
        farEar.fill()
        stroke(farEar, color: line, width: outline)
        color(0xE98FA8).setFill()
        UIBezierPath(arcCenter: CGPoint(x: 177, y: 52), radius: 13, startAngle: 0, endAngle: .pi * 2, clockwise: true).fill()

        // 足
        for rect in [CGRect(x: 82, y: 136, width: 32, height: 14), CGRect(x: 164, y: 136, width: 26, height: 13)] {
            let foot = UIBezierPath(ovalIn: rect)
            pink.setFill()
            foot.fill()
            stroke(foot, color: line, width: 4)
        }

        // 胴体と頭。鼻先に向かって細くなるしずく形
        let body = UIBezierPath()
        body.move(to: CGPoint(x: 224, y: 108))
        body.addCurve(to: CGPoint(x: 148, y: 60),
                      controlPoint1: CGPoint(x: 212, y: 86), controlPoint2: CGPoint(x: 184, y: 62))
        body.addCurve(to: CGPoint(x: 40, y: 104),
                      controlPoint1: CGPoint(x: 96, y: 56), controlPoint2: CGPoint(x: 40, y: 62))
        body.addCurve(to: CGPoint(x: 88, y: 143),
                      controlPoint1: CGPoint(x: 40, y: 128), controlPoint2: CGPoint(x: 58, y: 143))
        body.addCurve(to: CGPoint(x: 182, y: 142),
                      controlPoint1: CGPoint(x: 120, y: 144), controlPoint2: CGPoint(x: 156, y: 144))
        body.addCurve(to: CGPoint(x: 224, y: 108),
                      controlPoint1: CGPoint(x: 204, y: 140), controlPoint2: CGPoint(x: 226, y: 124))
        body.close()
        linear(context, in: body, from: CGPoint(x: 0, y: 58), to: CGPoint(x: 0, y: 144),
               stops: [(0, color(0xB3C6E8)), (0.5, color(0x93AAD6)), (1, color(0x7890C2))])
        clipped(context, to: body) {
            // 後ろ足の付け根。おなかの色で下の端を隠す
            let haunch = UIBezierPath()
            haunch.move(to: CGPoint(x: 113, y: 141))
            haunch.addCurve(to: CGPoint(x: 78, y: 103),
                            controlPoint1: CGPoint(x: 119, y: 119), controlPoint2: CGPoint(x: 102, y: 101))
            stroke(haunch, color: color(0x4F628F), width: 3.4)
            // おなかのクリーム色
            color(0xFBF4E2).setFill()
            UIBezierPath(ovalIn: CGRect(x: 78, y: 120, width: 170, height: 60)).fill()
            // 背中のつや
            let shine = UIBezierPath()
            shine.move(to: CGPoint(x: 60, y: 90))
            shine.addQuadCurve(to: CGPoint(x: 114, y: 71), controlPoint: CGPoint(x: 72, y: 71))
            stroke(shine, color: color(0xFFFFFF, alpha: 0.32), width: 8)
        }
        stroke(body, color: line, width: outline)

        // 手前の耳
        let ear = UIBezierPath(arcCenter: CGPoint(x: 144, y: 54), radius: 29, startAngle: 0, endAngle: .pi * 2, clockwise: true)
        linear(context, in: ear, from: CGPoint(x: 0, y: 25), to: CGPoint(x: 0, y: 83),
               stops: [(0, color(0xA9BEE3)), (1, color(0x8399C9))])
        stroke(ear, color: line, width: outline)
        let innerEar = UIBezierPath(arcCenter: CGPoint(x: 145, y: 56), radius: 18, startAngle: 0, endAngle: .pi * 2, clockwise: true)
        linear(context, in: innerEar, from: CGPoint(x: 0, y: 38), to: CGPoint(x: 0, y: 74),
               stops: [(0, color(0xFDBDCB)), (1, color(0xF394AC))])

        // ほっぺ
        color(0xF9A8BC, alpha: 0.7).setFill()
        UIBezierPath(ovalIn: CGRect(x: 178, y: 110, width: 20, height: 11)).fill()

        // 目
        line.setFill()
        UIBezierPath(ovalIn: CGRect(x: 181, y: 87, width: 14, height: 16)).fill()
        UIColor.white.setFill()
        UIBezierPath(ovalIn: CGRect(x: 186.5, y: 89.5, width: 5.5, height: 5.5)).fill()

        // ひげ
        let whiskers: [(CGPoint, CGPoint, CGPoint)] = [
            (CGPoint(x: 211, y: 114), CGPoint(x: 224, y: 124), CGPoint(x: 235, y: 123)),
            (CGPoint(x: 207, y: 119), CGPoint(x: 216, y: 133), CGPoint(x: 227, y: 137)),
        ]
        for (start, control, end) in whiskers {
            let whisker = UIBezierPath()
            whisker.move(to: start)
            whisker.addQuadCurve(to: end, controlPoint: control)
            stroke(whisker, color: line, width: 2.8)
        }

        // 鼻
        let nose = UIBezierPath(arcCenter: CGPoint(x: 225, y: 107), radius: 6.5, startAngle: 0, endAngle: .pi * 2, clockwise: true)
        color(0xF07C98).setFill()
        nose.fill()
        stroke(nose, color: line, width: 4)
        color(0xFFFFFF, alpha: 0.8).setFill()
        UIBezierPath(ovalIn: CGRect(x: 222, y: 103, width: 3.5, height: 3.5)).fill()
    }

    /// ちょうちょ。上から見た姿で、左右対称に描く。羽ばたきは横に縮めて見せるので、胴体を中心に置く
    static let butterfly: UIImage = render(width: 220, height: 190) { context in
        let line = color(0x4A2E18)
        let outline: CGFloat = 5.5

        // 右の羽の形。左は鏡写しにする
        let fore = UIBezierPath()
        fore.move(to: CGPoint(x: 112, y: 70))
        fore.addCurve(to: CGPoint(x: 190, y: 18),
                      controlPoint1: CGPoint(x: 126, y: 40), controlPoint2: CGPoint(x: 160, y: 14))
        fore.addCurve(to: CGPoint(x: 204, y: 84),
                      controlPoint1: CGPoint(x: 214, y: 22), controlPoint2: CGPoint(x: 216, y: 62))
        fore.addCurve(to: CGPoint(x: 112, y: 106),
                      controlPoint1: CGPoint(x: 194, y: 114), controlPoint2: CGPoint(x: 148, y: 106))
        fore.close()
        let hind = UIBezierPath()
        hind.move(to: CGPoint(x: 112, y: 98))
        hind.addCurve(to: CGPoint(x: 186, y: 124),
                      controlPoint1: CGPoint(x: 142, y: 92), controlPoint2: CGPoint(x: 180, y: 98))
        hind.addCurve(to: CGPoint(x: 148, y: 178),
                      controlPoint1: CGPoint(x: 192, y: 152), controlPoint2: CGPoint(x: 172, y: 180))
        hind.addCurve(to: CGPoint(x: 112, y: 130),
                      controlPoint1: CGPoint(x: 126, y: 176), controlPoint2: CGPoint(x: 114, y: 152))
        hind.close()

        /// 右半分に描いたものを、左にも鏡写しで描く
        func mirrored(_ draw: () -> Void) {
            draw()
            context.saveGState()
            context.translateBy(x: 220, y: 0)
            context.scaleBy(x: -1, y: 1)
            draw()
            context.restoreGState()
        }

        /// 羽 1 枚。付け根が明るく、縁に向かって濃くなる
        func drawWing(_ wing: UIBezierPath, root: CGPoint, radius: CGFloat, spot: CGRect) {
            radial(context, in: wing, center: root, radius: radius, stops: [
                (0, color(0xFFF2A0)), (0.45, color(0xFFD83A)), (1, color(0xFFAE1C)),
            ])
            clipped(context, to: wing) {
                // 縁の帯
                stroke(wing, color: color(0xF08A12, alpha: 0.75), width: 20)
                // 青い斑点
                let spotPath = UIBezierPath(ovalIn: spot)
                radial(context, in: spotPath, center: CGPoint(x: spot.midX - spot.width * 0.15, y: spot.midY - spot.height * 0.2),
                       radius: spot.width * 0.75, stops: [(0, color(0x6FC3FF)), (1, color(0x2563EB))])
                stroke(spotPath, color: line, width: 4)
                color(0xFFFFFF, alpha: 0.9).setFill()
                let shine = spot.width * 0.24
                UIBezierPath(ovalIn: CGRect(x: spot.midX - spot.width * 0.24, y: spot.midY - spot.height * 0.28,
                                            width: shine, height: shine)).fill()
            }
            stroke(wing, color: line, width: outline)
        }

        /// 羽の縁に並べる小さい点
        func drawDots(_ centers: [CGPoint]) {
            color(0xFFF7D6).setFill()
            for center in centers {
                UIBezierPath(arcCenter: center, radius: 3.2, startAngle: 0, endAngle: .pi * 2, clockwise: true).fill()
            }
        }

        mirrored {
            drawWing(hind, root: CGPoint(x: 112, y: 112), radius: 86, spot: CGRect(x: 141, y: 126, width: 26, height: 26))
            drawDots([CGPoint(x: 178, y: 150), CGPoint(x: 165, y: 166), CGPoint(x: 147, y: 171)])
        }
        mirrored {
            drawWing(fore, root: CGPoint(x: 112, y: 88), radius: 112, spot: CGRect(x: 158, y: 36, width: 34, height: 36))
            drawDots([CGPoint(x: 204, y: 46), CGPoint(x: 205, y: 62), CGPoint(x: 201, y: 78)])
        }

        // 触角
        mirrored {
            let antenna = UIBezierPath()
            antenna.move(to: CGPoint(x: 113, y: 46))
            antenna.addQuadCurve(to: CGPoint(x: 134, y: 12), controlPoint: CGPoint(x: 116, y: 22))
            stroke(antenna, color: line, width: 3.6)
            line.setFill()
            UIBezierPath(arcCenter: CGPoint(x: 135, y: 12), radius: 4.6, startAngle: 0, endAngle: .pi * 2, clockwise: true).fill()
        }

        // 胴体
        let body = UIBezierPath()
        body.move(to: CGPoint(x: 110, y: 54))
        body.addCurve(to: CGPoint(x: 110, y: 156),
                      controlPoint1: CGPoint(x: 126, y: 60), controlPoint2: CGPoint(x: 118, y: 132))
        body.addCurve(to: CGPoint(x: 110, y: 54),
                      controlPoint1: CGPoint(x: 102, y: 132), controlPoint2: CGPoint(x: 94, y: 60))
        body.close()
        linear(context, in: body, from: CGPoint(x: 100, y: 0), to: CGPoint(x: 120, y: 0),
               stops: [(0, color(0x7A5230)), (0.5, color(0x6B4526)), (1, color(0x553419))])
        clipped(context, to: body) {
            // おなかのしま
            for y in [98, 112, 126] as [CGFloat] {
                let stripe = UIBezierPath()
                stripe.move(to: CGPoint(x: 98, y: y))
                stripe.addQuadCurve(to: CGPoint(x: 122, y: y), controlPoint: CGPoint(x: 110, y: y + 5))
                stroke(stripe, color: color(0xA9793F, alpha: 0.9), width: 3)
            }
        }
        stroke(body, color: line, width: 4)
        let head = UIBezierPath(arcCenter: CGPoint(x: 110, y: 49), radius: 10.5, startAngle: 0, endAngle: .pi * 2, clockwise: true)
        color(0x6B4526).setFill()
        head.fill()
        stroke(head, color: line, width: 4)
    }

    /// 毛糸玉。転がるので、玉を画像の中心に置く。糸の端が少し出ている
    static let yarn: UIImage = render(width: 200, height: 200) { context in
        let center = CGPoint(x: 100, y: 100)
        let radius: CGFloat = 84
        let line = color(0x1E3A8A)
        let ball = UIBezierPath(arcCenter: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: true)

        // 糸の端。画像の右下の角へ向けて、はみ出さない長さにする
        let thread = UIBezierPath()
        thread.move(to: CGPoint(x: 148, y: 160))
        thread.addCurve(to: CGPoint(x: 178, y: 182),
                        controlPoint1: CGPoint(x: 156, y: 180), controlPoint2: CGPoint(x: 168, y: 190))
        thread.addCurve(to: CGPoint(x: 191, y: 160),
                        controlPoint1: CGPoint(x: 188, y: 174), controlPoint2: CGPoint(x: 180, y: 164))
        stroke(thread, color: line, width: 10)
        stroke(thread, color: color(0x5B9BF5), width: 5)

        /// 玉の地の色。左上が明るい
        func fillBall(_ path: UIBezierPath) {
            radial(context, in: path, center: CGPoint(x: 74, y: 70), radius: 128, stops: [
                (0, color(0x86BEFF)), (0.5, color(0x4C8CF0)), (1, color(0x2A5CC8)),
            ])
        }

        /// 巻いた糸の筋 1 本。玉を球と見て、軸を rotation だけ回し、tilt だけ手前に倒したときの、
        /// 高さ height（半径に対する割合）の緯線の見えている側。両端は玉の縁の少し外まで伸ばす
        func strand(height: CGFloat, tilt: CGFloat, rotation: CGFloat) -> [CGPoint] {
            let h = height * radius
            let ringRadius = max(radius * radius - h * h, 0).squareRoot()
            guard 0.5 < ringRadius else { return [] }
            // 緯線のうち、手前に見えている範囲
            let hidden = h * tan(tilt) / ringRadius
            guard hidden < 1 else { return [] }
            let start = asin(max(hidden, -1))
            let steps = 48
            var points: [CGPoint] = []
            for step in 0...steps {
                let angle = start + (.pi - 2 * start) * CGFloat(step) / CGFloat(steps)
                let x = ringRadius * cos(angle)
                let y = h * cos(tilt) + ringRadius * sin(tilt) * sin(angle)
                points.append(CGPoint(x: center.x + x * cos(rotation) - y * sin(rotation),
                                      y: center.y + x * sin(rotation) + y * cos(rotation)))
            }
            if -1 < hidden, let first = points.first, let last = points.last {
                points.insert(CGPoint(x: center.x + (first.x - center.x) * 1.2, y: center.y + (first.y - center.y) * 1.2), at: 0)
                points.append(CGPoint(x: center.x + (last.x - center.x) * 1.2, y: center.y + (last.y - center.y) * 1.2))
            }
            return points
        }

        /// 点を順につないだ線
        func path(through points: [CGPoint], closes: Bool = false) -> UIBezierPath {
            let path = UIBezierPath()
            guard let first = points.first else { return path }
            path.move(to: first)
            points.dropFirst().forEach { path.addLine(to: $0) }
            if closes {
                path.close()
            }
            return path
        }

        /// 同じ向きに巻いた糸の束。高さ from から to までを count 本の糸に分けて描く
        func wrap(from: CGFloat, to: CGFloat, count: Int, tilt: CGFloat, rotation: CGFloat, isOnTop: Bool) {
            let step = (to - from) / CGFloat(count)
            if isOnTop {
                // 下の束との境目に影を落としてから、束の範囲を塗り直す
                let band = path(through: strand(height: from, tilt: tilt, rotation: rotation)
                                + strand(height: to, tilt: tilt, rotation: rotation).reversed(), closes: true)
                stroke(band, color: color(0x14296B, alpha: 0.3), width: 10)
                fillBall(band)
            }
            for index in 0...count {
                let height = from + step * CGFloat(index)
                // 糸 1 本ごとのつや
                if index < count {
                    let shine = path(through: strand(height: height + step * 0.4, tilt: tilt, rotation: rotation))
                    stroke(shine, color: color(0xC4E2FF, alpha: 0.3), width: 3)
                }
                let isBorder = isOnTop && (index == 0 || index == count)
                let edge = path(through: strand(height: height, tilt: tilt, rotation: rotation))
                stroke(edge, color: color(0x1E3A8A, alpha: isBorder ? 1 : 0.8), width: isBorder ? 3.4 : 2.6)
            }
        }

        fillBall(ball)
        clipped(context, to: ball) {
            wrap(from: -1, to: 1, count: 10, tilt: 0.5, rotation: -0.55, isOnTop: false)
            wrap(from: -0.3, to: 0.5, count: 4, tilt: 0.45, rotation: 0.95, isOnTop: true)
            wrap(from: -0.86, to: -0.26, count: 3, tilt: 0.5, rotation: 2.4, isOnTop: true)
            // 縁の影と左上のつや。転がっても不自然にならない程度に弱くする
            stroke(ball, color: color(0x14296B, alpha: 0.2), width: 16)
            radial(context, center: CGPoint(x: 68, y: 62), radius: 58, stops: [
                (0, color(0xFFFFFF, alpha: 0.34)), (1, color(0xFFFFFF, alpha: 0)),
            ])
        }
        stroke(ball, color: line, width: 5)
    }

    /// 選択画面に並べる小さい画像
    static func thumbnail(for toy: Toy) -> UIImage? {
        switch toy {
        case .standard(let kind): return UIImage(named: String(describing: kind))
        case .laser: return laser
        case .teaser: return teaser
        case .mouse: return mouse
        case .butterfly: return butterfly
        case .yarn: return yarn
        case .photo(let id): return PhotoToyStore.image(for: id)
        }
    }
}

// MARK: - 描くための道具

private extension ToyImage {

    /// 幅と高さ（pt）を決めて描く。3x の画面で 200pt に表示してもぼやけないよう、端末によらず 3 倍の解像度にする
    static func render(width: CGFloat, height: CGFloat, _ draw: (CGContext) -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = 3
        format.opaque = false
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { rendererContext in
            let context = rendererContext.cgContext
            context.setLineCap(.round)
            context.setLineJoin(.round)
            draw(context)
        }
    }

    /// 0xRRGGBB で色を書く
    static func color(_ hex: UInt32, alpha: CGFloat = 1) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: alpha)
    }

    static func gradient(_ stops: [(CGFloat, UIColor)]) -> CGGradient? {
        CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                   colors: stops.map { $0.1.cgColor } as CFArray,
                   locations: stops.map { $0.0 })
    }

    /// path の中だけに描く
    static func clipped(_ context: CGContext, to path: UIBezierPath, _ draw: () -> Void) {
        context.saveGState()
        context.addPath(path.cgPath)
        context.clip()
        draw()
        context.restoreGState()
    }

    /// 線を引く。端と角は丸める
    static func stroke(_ path: UIBezierPath, color: UIColor, width: CGFloat) {
        path.lineWidth = width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        color.setStroke()
        path.stroke()
    }

    /// 中心から外へ色が変わる塗り。path を渡すと、その中だけを塗る
    static func radial(_ context: CGContext, in path: UIBezierPath? = nil,
                       center: CGPoint, radius: CGFloat, stops: [(CGFloat, UIColor)]) {
        guard let gradient = gradient(stops) else { return }
        context.saveGState()
        if let path {
            context.addPath(path.cgPath)
            context.clip()
        }
        context.drawRadialGradient(gradient, startCenter: center, startRadius: 0,
                                   endCenter: center, endRadius: radius,
                                   options: path == nil ? [] : [.drawsAfterEndLocation])
        context.restoreGState()
    }

    /// from から to へ色が変わる塗り。path の中だけを塗る
    static func linear(_ context: CGContext, in path: UIBezierPath,
                       from: CGPoint, to: CGPoint, stops: [(CGFloat, UIColor)]) {
        guard let gradient = gradient(stops) else { return }
        context.saveGState()
        context.addPath(path.cgPath)
        context.clip()
        context.drawLinearGradient(gradient, start: from, end: to,
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        context.restoreGState()
    }
}
