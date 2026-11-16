import UIKit
import SpriteKit

/// プレミアムの購入画面（ペイウォール）。
/// 明るい背景に、おもちゃが動く窓・中身の紹介・下に固定した購入ボタンを並べる。
/// 鍵の付いたおもちゃを押して開いたときは、そのおもちゃを主役にした文言と窓にする
final class PaywallViewController: UIViewController {

    /// どこから開いたか。見出しと窓の主役が変わる
    enum Context: Equatable {
        /// 選択画面の札から開いた
        case general
        /// 鍵の付いたおもちゃを押して開いた
        case toy(Toy)
        /// 鍵の付いた「写真から追加」を押して開いた
        case photo
    }

    /// 購入か復元でプレミアムになり、画面を閉じたあとに呼ぶ
    var onUnlock: (() -> Void)?

    private let context: Context
    private let scrollView = UIScrollView()
    private let previewView = SKView()
    private let featureRows = UIStackView()
    private let buyButton = PulseButton()
    private let buyNoteLabel = UILabel()
    private let restoreButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)
    /// 購入か復元の途中か
    private var isBusy = false { didSet { updateBuyButton() } }
    /// 使えるようになったときの表示を始めたか（二重に閉じないため）
    private var didUnlock = false
    /// 中身の紹介を出す動きを済ませたか
    private var didAnimateEntrance = false

    init(context: Context = .general) {
        self.context = context
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        setUpContent()
        setUpCloseButton()
        updateBuyButton()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(premiumDidChange),
                                               name: PremiumStore.didChangeNotification,
                                               object: nil)
        if PremiumStore.shared.product == nil {
            Task { await PremiumStore.shared.loadProduct() }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // 窓の大きさが決まってから、おもちゃを動かすシーンを作る
        if previewView.scene == nil, previewView.bounds.width > 0 {
            let scene = PaywallPreviewScene(size: previewView.bounds.size, context: context)
            scene.scaleMode = .resizeFill
            previewView.presentScene(scene)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        animateEntrance()
    }

    // MARK: - 文言

    private var titleText: String {
        switch context {
        case .general: return "きゃっぷ プレミアム"
        case .toy(let toy): return "\(ToyPickerViewController.title(for: toy))はプレミアムのおもちゃです"
        case .photo: return "写真がおもちゃになります"
        }
    }

    private var subtitleText: String {
        switch context {
        case .general:
            return "新しいおもちゃと、写真から作るおもちゃで、いつもと違う遊びを。"
        case .toy(let toy):
            return "プレミアムにすると、\(ToyPickerViewController.title(for: toy))をふくむ\(Toy.premiumToys.count)種類のおもちゃと、写真から作るおもちゃが使えるようになります。"
        case .photo:
            return "プレミアムにすると、写っている猫や物を切り抜いておもちゃにできます。ねずみ・ちょうちょなど\(Toy.premiumToys.count)種類のおもちゃも使えるようになります。"
        }
    }

    // MARK: - 画面の組み立て

    private func setUpContent() {
        // 購入ボタンはスクロールしても常に見えるように、画面の下に固定する
        let footer = makeFooter()
        view.addSubview(footer)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        view.insertSubview(scrollView, belowSubview: footer)
        NSLayoutConstraint.activate([
            footer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: 24),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)
        constrainReadableWidth(stack, in: scrollView.frameLayoutGuide)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 60),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -32),
        ])

        // おもちゃが動く窓。アプリのピンクと水色を淡く敷く
        let stage = PastelStageView()
        stage.translatesAutoresizingMaskIntoConstraints = false
        previewView.allowsTransparency = true
        previewView.backgroundColor = .clear
        previewView.translatesAutoresizingMaskIntoConstraints = false
        stage.addSubview(previewView)
        NSLayoutConstraint.activate([
            previewView.topAnchor.constraint(equalTo: stage.topAnchor),
            previewView.bottomAnchor.constraint(equalTo: stage.bottomAnchor),
            previewView.leadingAnchor.constraint(equalTo: stage.leadingAnchor),
            previewView.trailingAnchor.constraint(equalTo: stage.trailingAnchor),
            stage.heightAnchor.constraint(equalToConstant: traitCollection.userInterfaceIdiom == .pad ? 240 : 190),
        ])
        stack.addArrangedSubview(stage)
        stack.setCustomSpacing(20, after: stage)

        // PREMIUM の小さな札
        let crown = UIImageView(image: UIImage(systemName: "crown.fill"))
        crown.tintColor = Self.gold
        crown.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)
        let badgeLabel = UILabel()
        badgeLabel.attributedText = NSAttributedString(string: "PREMIUM", attributes: [
            .font: UIFont.systemFont(ofSize: 12, weight: .heavy),
            .foregroundColor: Self.gold,
            .kern: 2.5,
        ])
        let badge = UIStackView(arrangedSubviews: [crown, badgeLabel])
        badge.spacing = 5
        badge.alignment = .center
        let badgeRow = UIStackView(arrangedSubviews: [badge])
        badgeRow.axis = .vertical
        badgeRow.alignment = .center
        stack.addArrangedSubview(badgeRow)
        stack.setCustomSpacing(4, after: badgeRow)

        let titleLabel = makeLabel(titleText, font: Self.font("NotoSansJP-Bold", context == .general ? 26 : 22), color: .label)
        stack.addArrangedSubview(titleLabel)
        stack.setCustomSpacing(8, after: titleLabel)

        let subtitleLabel = makeLabel(subtitleText, font: Self.font("NotoSansJP-Regular", 14), color: .secondaryLabel)
        stack.addArrangedSubview(subtitleLabel)
        stack.setCustomSpacing(22, after: subtitleLabel)

        // 中身の紹介
        let thumbnails = UIStackView(arrangedSubviews: Toy.premiumToys.map { toy in
            let imageView = UIImageView(image: ToyImage.thumbnail(for: toy))
            imageView.contentMode = .scaleAspectFit
            imageView.widthAnchor.constraint(equalToConstant: 30).isActive = true
            imageView.heightAnchor.constraint(equalToConstant: 30).isActive = true
            return imageView
        })
        thumbnails.spacing = 8
        let rows = [
            FeatureRow(symbol: "sparkles",
                       title: "\(Toy.premiumToys.count)種類のプレミアムおもちゃ",
                       detail: "ねずみ・ちょうちょ・レーザーポインター・ねこじゃらし・毛糸玉",
                       accessory: thumbnails),
            FeatureRow(symbol: "photo.on.rectangle.angled",
                       title: "写真がおもちゃに",
                       detail: "写っている猫や物を切り抜いて、画面の中を走らせます。\(PhotoToyStore.maxCount)つまで登録できます。",
                       accessory: nil),
            FeatureRow(symbol: "infinity",
                       title: "一度買えば、ずっと使える",
                       detail: "買い切りなので、月額料金はかかりません。",
                       accessory: nil),
        ]
        rows.forEach { featureRows.addArrangedSubview($0) }
        featureRows.axis = .vertical
        featureRows.spacing = 16
        featureRows.isLayoutMarginsRelativeArrangement = true
        featureRows.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 18, leading: 16, bottom: 18, trailing: 16)
        featureRows.backgroundColor = .secondarySystemGroupedBackground
        featureRows.layer.cornerRadius = 18
        stack.addArrangedSubview(featureRows)
    }

    /// 画面の下に固定する、購入ボタン・説明・復元ボタンの入れ物
    private func makeFooter() -> UIView {
        let footer = FadingFooterView()
        footer.translatesAutoresizingMaskIntoConstraints = false

        buyButton.heightAnchor.constraint(equalToConstant: 56).isActive = true
        buyButton.addTarget(self, action: #selector(buyTapped), for: .touchUpInside)

        buyNoteLabel.font = Self.font("NotoSansJP-Regular", 12)
        buyNoteLabel.textColor = .secondaryLabel
        buyNoteLabel.textAlignment = .center
        buyNoteLabel.numberOfLines = 0

        restoreButton.setTitle("購入を復元", for: .normal)
        restoreButton.titleLabel?.font = Self.font("NotoSansJP-Regular", 14)
        restoreButton.addTarget(self, action: #selector(restoreTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [buyButton, buyNoteLabel, restoreButton])
        stack.axis = .vertical
        stack.spacing = 8
        stack.setCustomSpacing(2, after: buyNoteLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        footer.addSubview(stack)
        constrainReadableWidth(stack, in: footer.safeAreaLayoutGuide)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: footer.topAnchor, constant: 28),
            stack.bottomAnchor.constraint(equalTo: footer.safeAreaLayoutGuide.bottomAnchor, constant: -4),
        ])
        return footer
    }

    /// 横幅を左右 24pt あけた幅にし、iPad では 520 までにして中央に置く
    private func constrainReadableWidth(_ target: UIView, in guide: UILayoutGuide) {
        let preferredWidth = target.widthAnchor.constraint(equalTo: guide.widthAnchor, constant: -48)
        preferredWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            target.centerXAnchor.constraint(equalTo: guide.centerXAnchor),
            target.widthAnchor.constraint(lessThanOrEqualToConstant: 520),
            target.widthAnchor.constraint(lessThanOrEqualTo: guide.widthAnchor, constant: -48),
            preferredWidth,
        ])
    }

    private func setUpCloseButton() {
        closeButton.setImage(UIImage(systemName: "xmark",
                                     withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)),
                             for: .normal)
        closeButton.tintColor = .secondaryLabel
        closeButton.backgroundColor = .tertiarySystemFill
        closeButton.layer.cornerRadius = 16
        closeButton.accessibilityLabel = "閉じる"
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(closeButton)
        NSLayoutConstraint.activate([
            closeButton.widthAnchor.constraint(equalToConstant: 32),
            closeButton.heightAnchor.constraint(equalToConstant: 32),
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            closeButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
        ])
    }

    private func makeLabel(_ text: String, font: UIFont, color: UIColor) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = font
        label.textColor = color
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }

    /// 中身の紹介を、上から順にふわっと出す。視差効果を減らす設定のときは動かさない
    private func animateEntrance() {
        guard !didAnimateEntrance else { return }
        didAnimateEntrance = true
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        for (index, row) in featureRows.arrangedSubviews.enumerated() {
            row.alpha = 0
            row.transform = CGAffineTransform(translationX: 0, y: 8)
            UIView.animate(withDuration: 0.4, delay: 0.1 + Double(index) * 0.08, options: .curveEaseOut) {
                row.alpha = 1
                row.transform = .identity
            }
        }
    }

    /// 購入ボタンと、その下の説明を今の状態に合わせる。価格は App Store から読み込んだものだけを出す
    private func updateBuyButton() {
        guard !didUnlock else { return }
        let store = PremiumStore.shared
        if isBusy {
            buyButton.setTitle("お待ちください…", for: .normal)
            buyButton.isEnabled = false
        } else if let product = store.product {
            buyButton.setTitle("プレミアムを購入　\(product.displayPrice)", for: .normal)
            buyButton.isEnabled = true
        } else if store.didLoadProduct {
            buyButton.setTitle("プレミアムを購入", for: .normal)
            buyButton.isEnabled = true
        } else {
            buyButton.setTitle("価格を読み込んでいます…", for: .normal)
            buyButton.isEnabled = false
        }
        if store.product == nil && store.didLoadProduct {
            buyNoteLabel.text = "価格を読み込めませんでした。押すともう一度読み込みます。"
        } else {
            buyNoteLabel.text = "買い切り・月額料金はかかりません"
        }
        restoreButton.isEnabled = !isBusy
        closeButton.isEnabled = !isBusy
    }

    // MARK: - 操作

    @objc private func premiumDidChange() {
        updateBuyButton()
        if PremiumStore.shared.isPremium {
            showUnlockedAndClose()
        }
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    @objc private func buyTapped() {
        isBusy = true
        Task { @MainActor in
            defer { isBusy = false }
            do {
                switch try await PremiumStore.shared.purchase() {
                case .purchased:
                    showUnlockedAndClose()
                case .pending:
                    showMessage(title: "購入の承認待ちです", message: "承認されると使えるようになります。")
                case .cancelled:
                    break
                }
            } catch {
                showMessage(title: "購入できませんでした", message: error.localizedDescription)
            }
        }
    }

    @objc private func restoreTapped() {
        isBusy = true
        Task { @MainActor in
            defer { isBusy = false }
            do {
                try await PremiumStore.shared.restore()
                if PremiumStore.shared.isPremium {
                    showUnlockedAndClose()
                } else {
                    showMessage(title: "復元できる購入が見つかりませんでした")
                }
            } catch {
                showMessage(title: "復元できませんでした", message: error.localizedDescription)
            }
        }
    }

    private func showMessage(title: String, message: String? = nil) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    /// 使えるようになったことを購入ボタンに短く出し、少し待ってから閉じる
    private func showUnlockedAndClose() {
        guard !didUnlock else { return }
        didUnlock = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        buyButton.showCompleted(title: "使えるようになりました")
        buyNoteLabel.text = "ありがとうございます"
        restoreButton.isHidden = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.dismiss(animated: true) {
                self?.onUnlock?()
            }
        }
    }

    // MARK: - 色・フォント

    static let gold = UIColor(red: 0.85, green: 0.62, blue: 0.1, alpha: 1)
    /// 購入ボタンの色。アプリの肉球のピンク（puni）を、白い文字が読める濃さにしたもの
    static let accentPink = UIColor(red: 0.93, green: 0.36, blue: 0.6, alpha: 1)
    static let pastelPink = UIColor(red: 1, green: 0.74, blue: 0.87, alpha: 1)
    static let pastelCyan = UIColor(red: 0.62, green: 1, blue: 1, alpha: 1)

    static func font(_ name: String, _ size: CGFloat) -> UIFont {
        UIFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: .bold)
    }
}

// MARK: - おもちゃが動く窓の下地

/// アプリのピンクと水色を淡く重ねた、角の丸い下地
private final class PastelStageView: UIView {

    private let gradientLayer = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        gradientLayer.colors = [PaywallViewController.pastelPink.withAlphaComponent(0.35).cgColor,
                                PaywallViewController.pastelCyan.withAlphaComponent(0.35).cgColor]
        gradientLayer.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer.endPoint = CGPoint(x: 1, y: 1)
        layer.addSublayer(gradientLayer)
        backgroundColor = .secondarySystemGroupedBackground
        layer.cornerRadius = 22
        clipsToBounds = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds
    }
}

// MARK: - 下に固定する入れ物

/// 上の端が透明で、下へ行くほど背景の色になる入れ物
private final class FadingFooterView: UIView {

    private let fadeLayer = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.addSublayer(fadeLayer)
        updateColors()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        fadeLayer.frame = bounds
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateColors()
    }

    /// ライトとダークで背景の色が変わるので、そのつど作り直す
    private func updateColors() {
        let background = UIColor.systemGroupedBackground.resolvedColor(with: traitCollection)
        fadeLayer.colors = [background.withAlphaComponent(0).cgColor,
                            background.withAlphaComponent(0.95).cgColor,
                            background.cgColor]
        fadeLayer.locations = [0, 0.3, 1]
    }
}

// MARK: - 中身の紹介の1行

private final class FeatureRow: UIView {

    init(symbol: String, title: String, detail: String, accessory: UIView?) {
        super.init(frame: .zero)

        let iconBackground = UIView()
        iconBackground.backgroundColor = PaywallViewController.pastelPink.withAlphaComponent(0.35)
        iconBackground.layer.cornerRadius = 18
        iconBackground.translatesAutoresizingMaskIntoConstraints = false
        let icon = UIImageView(image: UIImage(systemName: symbol))
        icon.tintColor = PaywallViewController.accentPink
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        icon.translatesAutoresizingMaskIntoConstraints = false
        iconBackground.addSubview(icon)

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = PaywallViewController.font("NotoSansJP-Bold", 15)
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 0

        let detailLabel = UILabel()
        detailLabel.text = detail
        detailLabel.font = PaywallViewController.font("NotoSansJP-Regular", 13)
        detailLabel.textColor = .secondaryLabel
        detailLabel.numberOfLines = 0

        let texts = UIStackView(arrangedSubviews: [titleLabel, detailLabel])
        texts.axis = .vertical
        texts.spacing = 2
        if let accessory {
            let row = UIStackView(arrangedSubviews: [accessory, UIView()])
            texts.addArrangedSubview(row)
            texts.setCustomSpacing(8, after: detailLabel)
        }

        let row = UIStackView(arrangedSubviews: [iconBackground, texts])
        row.spacing = 12
        row.alignment = .top
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        NSLayoutConstraint.activate([
            iconBackground.widthAnchor.constraint(equalToConstant: 36),
            iconBackground.heightAnchor.constraint(equalToConstant: 36),
            icon.centerXAnchor.constraint(equalTo: iconBackground.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconBackground.centerYAnchor),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - 軽く脈打つ購入ボタン

/// ピンク一色の購入ボタン。押せるあいだは、ときどき軽く大きくなって目を引く
private final class PulseButton: UIButton {

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = PaywallViewController.accentPink
        titleLabel?.font = PaywallViewController.font("NotoSansJP-Bold", 17)
        setTitleColor(.white, for: .normal)
        setTitleColor(UIColor(white: 1, alpha: 0.85), for: .disabled)
        layer.shadowColor = PaywallViewController.accentPink.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 10
        layer.shadowOffset = CGSize(width: 0, height: 4)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updatePulse()
    }

    override var isEnabled: Bool {
        didSet {
            alpha = isEnabled ? 1 : 0.6
            updatePulse()
        }
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.12) {
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.97, y: 0.97) : .identity
            }
        }
    }

    /// 使えるようになったことを、チェックの印と一緒に出す
    func showCompleted(title: String) {
        layer.removeAnimation(forKey: "pulse")
        setImage(UIImage(systemName: "checkmark.circle.fill"), for: .normal)
        tintColor = .white
        setTitle(" \(title)", for: .normal)
        isUserInteractionEnabled = false
        alpha = 1
    }

    /// 2.4 秒ごとに少しだけ大きくなって戻る。視差効果を減らす設定のときは動かさない
    private func updatePulse() {
        layer.removeAnimation(forKey: "pulse")
        guard window != nil, isEnabled, !UIAccessibility.isReduceMotionEnabled else { return }
        let pulse = CAKeyframeAnimation(keyPath: "transform.scale")
        pulse.values = [1, 1.03, 1, 1]
        pulse.keyTimes = [0, 0.12, 0.25, 1]
        pulse.duration = 2.4
        pulse.repeatCount = .infinity
        layer.add(pulse, forKey: "pulse")
    }
}
