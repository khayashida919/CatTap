import UIKit
import PhotosUI

/// プレミアムのおもちゃと写真のおもちゃを選ぶ画面。
/// プレミアムを持っていないときは、いちばん上に購入画面（復元もここでできる）を開く札を出す
final class ToyPickerViewController: UITableViewController {

    private enum Section: Int, CaseIterable {
        case purchase
        case premium
        case photo
    }

    private let premiumToys = Toy.premiumToys
    private var photoIDs: [UUID] = []
    private var isPremium: Bool { PremiumStore.shared.isPremium }
    /// 写真の加工の途中か
    private var isBusy = false { didSet { updateBusyIndicator() } }

    init() {
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// 画面に出すおもちゃの名前
    static func title(for toy: Toy) -> String {
        switch toy {
        case .standard(.bug): return "虫"
        case .standard(.bird): return "鳥"
        case .standard(.fish): return "魚"
        case .laser: return "レーザーポインター"
        case .teaser: return "ねこじゃらし"
        case .mouse: return "ねずみ"
        case .butterfly: return "ちょうちょ"
        case .yarn: return "毛糸玉"
        case .photo(let id):
            let number = (PhotoToyStore.ids.firstIndex(of: id) ?? 0) + 1
            return "写真 \(number)"
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "もっとおもちゃ"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.register(PremiumBannerCell.self, forCellReuseIdentifier: "banner")
        photoIDs = PhotoToyStore.ids
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(premiumDidChange),
                                               name: PremiumStore.didChangeNotification,
                                               object: nil)
    }

    @objc private func premiumDidChange() {
        tableView.reloadData()
    }

    private func reloadPhotos() {
        photoIDs = PhotoToyStore.ids
        tableView.reloadData()
    }

    private func updateBusyIndicator() {
        tableView.isUserInteractionEnabled = !isBusy
        if isBusy {
            let indicator = UIActivityIndicatorView(style: .medium)
            indicator.startAnimating()
            navigationItem.rightBarButtonItem = UIBarButtonItem(customView: indicator)
        } else {
            navigationItem.rightBarButtonItem = nil
        }
    }

    // MARK: - 表の中身

    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section) {
        case .purchase: return isPremium ? 0 : 1
        case .premium: return premiumToys.count
        case .photo: return photoIDs.count + (PhotoToyStore.canAdd ? 1 : 0)
        case nil: return 0
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section) {
        case .purchase: return nil
        case .premium: return "プレミアムのおもちゃ"
        case .photo: return "写真のおもちゃ"
        case nil: return nil
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard Section(rawValue: section) == .photo else { return nil }
        return "写真に写っている猫や物を切り抜いて、おもちゃにします。\(PhotoToyStore.maxCount)つまで登録でき、横にスワイプすると削除できます。"
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if Section(rawValue: indexPath.section) == .purchase {
            // 購入画面（PaywallViewController）を開く札
            return tableView.dequeueReusableCell(withIdentifier: "banner", for: indexPath)
        }
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.accessoryType = .none
        cell.accessoryView = nil
        cell.selectionStyle = .default

        switch Section(rawValue: indexPath.section) {
        case .purchase:
            break
        case .premium:
            configureToyCell(cell, toy: premiumToys[indexPath.row])
        case .photo:
            if indexPath.row < photoIDs.count {
                configureToyCell(cell, toy: .photo(photoIDs[indexPath.row]))
            } else {
                var content = cell.defaultContentConfiguration()
                content.image = UIImage(systemName: "plus.circle")
                content.text = "写真から追加"
                content.textProperties.color = view.tintColor
                content.imageProperties.reservedLayoutSize = CGSize(width: 44, height: 44)
                cell.contentConfiguration = content
                if !isPremium {
                    cell.accessoryView = lockView()
                }
            }
        case nil:
            break
        }
        return cell
    }

    private func configureToyCell(_ cell: UITableViewCell, toy: Toy) {
        var content = cell.defaultContentConfiguration()
        content.image = ToyImage.thumbnail(for: toy)
        content.imageProperties.maximumSize = CGSize(width: 44, height: 44)
        content.imageProperties.reservedLayoutSize = CGSize(width: 44, height: 44)
        content.text = Self.title(for: toy)
        cell.contentConfiguration = content
        if !isPremium {
            cell.accessoryView = lockView()
        } else if App.shared.toy == toy {
            cell.accessoryType = .checkmark
        }
    }

    private func lockView() -> UIView {
        let imageView = UIImageView(image: UIImage(systemName: "lock.fill"))
        imageView.tintColor = .secondaryLabel
        return imageView
    }

    // MARK: - 操作

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch Section(rawValue: indexPath.section) {
        case .purchase:
            presentPaywall(context: .general)
        case .premium:
            select(premiumToys[indexPath.row])
        case .photo:
            if indexPath.row < photoIDs.count {
                select(.photo(photoIDs[indexPath.row]))
            } else if isPremium {
                presentPhotoPicker()
            } else {
                presentPaywall(context: .photo)
            }
        case nil:
            break
        }
    }

    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard Section(rawValue: indexPath.section) == .photo, indexPath.row < photoIDs.count else {
            return nil
        }
        let id = photoIDs[indexPath.row]
        let delete = UIContextualAction(style: .destructive, title: "削除") { [weak self] _, _, completion in
            PhotoToyStore.remove(id)
            self?.reloadPhotos()
            completion(true)
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }

    private func select(_ toy: Toy) {
        guard isPremium else {
            if case .photo = toy {
                presentPaywall(context: .photo)
            } else {
                presentPaywall(context: .toy(toy))
            }
            return
        }
        App.shared.toy = toy
        tableView.reloadData()
    }

    /// プレミアムの購入画面をシートで開く。押したおもちゃに合わせた画面にする
    private func presentPaywall(context: PaywallViewController.Context) {
        let paywall = PaywallViewController(context: context)
        paywall.modalPresentationStyle = .pageSheet
        paywall.onUnlock = { [weak self] in
            self?.tableView.reloadData()
        }
        present(paywall, animated: true)
    }

    private func showMessage(title: String, message: String? = nil) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func presentPhotoPicker() {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: true)
    }
}

extension ToyPickerViewController: PHPickerViewControllerDelegate {

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider,
              provider.canLoadObject(ofClass: UIImage.self) else {
            return
        }
        isBusy = true
        provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
            guard let photo = object as? UIImage else {
                DispatchQueue.main.async {
                    self?.isBusy = false
                    self?.showMessage(title: "写真を読み込めませんでした")
                }
                return
            }
            // 切り抜きに時間がかかるので、メインスレッド以外で加工する
            DispatchQueue.global(qos: .userInitiated).async {
                let result = Result { try PhotoToyStore.add(from: photo) }
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.isBusy = false
                    switch result {
                    case .success(let id):
                        PhotoToyStore.register(id)
                        App.shared.toy = .photo(id)
                        self.reloadPhotos()
                    case .failure:
                        self.showMessage(title: "おもちゃを作れませんでした")
                    }
                }
            }
        }
    }
}

// MARK: - 購入画面を開く札

/// 白い札に淡いピンクを敷き、金色の王冠で少しだけ目立たせる
private final class PremiumBannerCell: UITableViewCell {

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        var background = UIBackgroundConfiguration.listGroupedCell()
        background.backgroundColor = PaywallViewController.pastelPink.withAlphaComponent(0.25)
        backgroundConfiguration = background

        var content = UIListContentConfiguration.subtitleCell()
        content.image = UIImage(systemName: "crown.fill")
        content.imageProperties.tintColor = PaywallViewController.gold
        content.imageProperties.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20, weight: .bold)
        content.text = "きゃっぷ プレミアム"
        content.textProperties.font = PaywallViewController.font("NotoSansJP-Bold", 16)
        content.secondaryText = "ねずみ・ちょうちょ・写真のおもちゃなどを使えるようにする"
        content.secondaryTextProperties.font = PaywallViewController.font("NotoSansJP-Regular", 12)
        content.secondaryTextProperties.color = .secondaryLabel
        content.textToSecondaryTextVerticalPadding = 2
        content.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 14, leading: 0, bottom: 14, trailing: 0)
        contentConfiguration = content
        accessoryType = .disclosureIndicator
    }

    required init?(coder: NSCoder) { fatalError() }
}
