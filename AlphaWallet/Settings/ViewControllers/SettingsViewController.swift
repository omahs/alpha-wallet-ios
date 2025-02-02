// Copyright © 2018 Stormbird PTE. LTD.

import UIKit
import Combine
import AlphaWalletFoundation

protocol SettingsViewControllerDelegate: class, CanOpenURL {
    func advancedSettingsSelected(in controller: SettingsViewController)
    func changeWalletSelected(in controller: SettingsViewController)
    func myWalletAddressSelected(in controller: SettingsViewController)
    func backupWalletSelected(in controller: SettingsViewController)
    func showSeedPhraseSelected(in controller: SettingsViewController)
    func walletConnectSelected(in controller: SettingsViewController)
    func nameWalletSelected(in controller: SettingsViewController)
    func blockscanChatSelected(in controller: SettingsViewController)
    func activeNetworksSelected(in controller: SettingsViewController)
    func helpSelected(in controller: SettingsViewController)
}

class SettingsViewController: UIViewController {
    private let promptBackupWalletViewHolder = UIView()
    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .grouped)
        tableView.register(SettingTableViewCell.self)
        tableView.register(SwitchTableViewCell.self)
        tableView.separatorStyle = .singleLine
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.estimatedRowHeight = Metrics.anArbitraryRowHeightSoAutoSizingCellsWorkIniOS10
        tableView.tableFooterView = UIView.tableFooterToRemoveEmptyCellSeparators()
        tableView.separatorColor = Configuration.Color.Semantic.tableViewSeparator

        return tableView
    }()
    private lazy var dataSource = makeDataSource()
    private let appear = PassthroughSubject<Void, Never>()
    private let toggleSelection = PassthroughSubject<(indexPath: IndexPath, isOn: Bool), Never>()
    private let blockscanChatUnreadCount = PassthroughSubject<Int?, Never>()
    private let didSetPasscode = PassthroughSubject<Bool, Never>()
    private var cancellable = Set<AnyCancellable>()
    private let viewModel: SettingsViewModel

    weak var delegate: SettingsViewControllerDelegate?
    var promptBackupWalletView: UIView? {
        didSet {
            oldValue?.removeFromSuperview()
            if let promptBackupWalletView = promptBackupWalletView {
                promptBackupWalletView.translatesAutoresizingMaskIntoConstraints = false
                promptBackupWalletViewHolder.addSubview(promptBackupWalletView)
                NSLayoutConstraint.activate([
                    promptBackupWalletView.leadingAnchor.constraint(equalTo: promptBackupWalletViewHolder.leadingAnchor, constant: 7),
                    promptBackupWalletView.trailingAnchor.constraint(equalTo: promptBackupWalletViewHolder.trailingAnchor, constant: -7),
                    promptBackupWalletView.topAnchor.constraint(equalTo: promptBackupWalletViewHolder.topAnchor, constant: 7),
                    promptBackupWalletView.bottomAnchor.constraint(equalTo: promptBackupWalletViewHolder.bottomAnchor, constant: 0),
                ])
                tabBarItem.badgeValue = "1"
                showPromptBackupWalletViewAsTableHeaderView()
            } else {
                hidePromptBackupWalletView()
                tabBarItem.badgeValue = nil
            }
        }
    }

    init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)

        view.addSubview(tableView)
        
        NSLayoutConstraint.activate([
            tableView.anchorsConstraint(to: view)
        ])
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.dataSource = dataSource
        tableView.delegate = self

        if promptBackupWalletView == nil {
            hidePromptBackupWalletView()
        }

        bind(viewModel: viewModel)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        appear.send(())
    }

    private func bind(viewModel: SettingsViewModel) {
        navigationItem.largeTitleDisplayMode = viewModel.largeTitleDisplayMode
        title = viewModel.title
        view.backgroundColor = viewModel.backgroundColor
        tableView.backgroundColor = viewModel.backgroundColor

        let input = SettingsViewModelInput(
            appear: appear.eraseToAnyPublisher(),
            toggleSelection: toggleSelection.eraseToAnyPublisher(),
            didSetPasscode: didSetPasscode.eraseToAnyPublisher(),
            blockscanChatUnreadCount: blockscanChatUnreadCount.eraseToAnyPublisher())

        let output = viewModel.transform(input: input)

        output.viewState
            .sink { [dataSource, viewModel, tabBarItem] viewState in
                dataSource.apply(viewState.snapshot, animatingDifferences: viewModel.animatingDifferences)
                tabBarItem?.badgeValue = viewState.badge
            }.store(in: &cancellable)

        output.askToSetPasscode
            .sink { [weak self, didSetPasscode] _ in
                self?.askUserToSetPasscode { value in
                    didSetPasscode.send(value)
                }
            }.store(in: &cancellable)
    }

    func configure(blockscanChatUnreadCount: Int?) {
        self.blockscanChatUnreadCount.send(blockscanChatUnreadCount)
    }

    private func showPromptBackupWalletViewAsTableHeaderView() {
        let size = promptBackupWalletViewHolder.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        promptBackupWalletViewHolder.bounds.size.height = size.height

        tableView.tableHeaderView = promptBackupWalletViewHolder
    }

    private func hidePromptBackupWalletView() {
        tableView.tableHeaderView = nil
    }

    private func askUserToSetPasscode(completion: ((Bool) -> Void)? = .none) {
        guard let navigationController = navigationController else { return }
        let lock = LockCreatePasscodeCoordinator(navigationController: navigationController, lock: viewModel.lock)
        lock.start()
        lock.lockViewController.willFinishWithResult = { result in
            completion?(result)
            lock.stop()
        }
    }

    required init?(coder aDecoder: NSCoder) {
        return nil
    }
}

extension SettingsViewController: CanOpenURL {

    func didPressViewContractWebPage(forContract contract: AlphaWallet.Address, server: RPCServer, in viewController: UIViewController) {
        delegate?.didPressViewContractWebPage(forContract: contract, server: server, in: viewController)
    }

    func didPressViewContractWebPage(_ url: URL, in viewController: UIViewController) {
        delegate?.didPressViewContractWebPage(url, in: viewController)
    }

    func didPressOpenWebPage(_ url: URL, in viewController: UIViewController) {
        delegate?.didPressOpenWebPage(url, in: viewController)
    }
}

extension SettingsViewController: SwitchTableViewCellDelegate {

    func cell(_ cell: SwitchTableViewCell, switchStateChanged isOn: Bool) {
        guard let indexPath = cell.indexPath else { return }

        toggleSelection.send((indexPath, isOn))
    }
}

fileprivate extension SettingsViewController {
    func makeDataSource() -> UITableViewDiffableDataSource<SettingsSection, SettingsViewModel.ViewType> {
        return UITableViewDiffableDataSource(tableView: tableView, cellProvider: { tableView, indexPath, viewModel in
            switch viewModel {
            case .cell(let vm):
                let cell: SettingTableViewCell = tableView.dequeueReusableCell(for: indexPath)
                cell.accessoryView = vm.accessoryView
                cell.accessoryType = vm.accessoryType
                cell.configure(viewModel: vm)

                return cell
            case .undefined:
                return UITableViewCell()
            case .passcode(let vm):
                let cell: SwitchTableViewCell = tableView.dequeueReusableCell(for: indexPath)
                cell.configure(viewModel: vm)
                cell.delegate = self

                return cell
            }
        })
    }
}

extension SettingsViewController: UITableViewDelegate {

    //Hide the footer
    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        .leastNormalMagnitude
    }

    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        nil
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let headerView: SettingViewHeader = SettingViewHeader()
        let viewModel = SettingViewHeaderViewModel(section: self.viewModel.sections[section])
        headerView.configure(viewModel: viewModel)

        return headerView
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        switch viewModel.sections[indexPath.section] {
        case .wallet(let rows):
            switch rows[indexPath.row] {
            case .backup:
                delegate?.backupWalletSelected(in: self)
            case .changeWallet:
                delegate?.changeWalletSelected(in: self)
            case .showMyWallet:
                delegate?.myWalletAddressSelected(in: self)
            case .showSeedPhrase:
                delegate?.showSeedPhraseSelected(in: self)
            case .walletConnect:
                delegate?.walletConnectSelected(in: self)
            case .nameWallet:
                delegate?.nameWalletSelected(in: self)
            case .blockscanChat:
                delegate?.blockscanChatSelected(in: self)
            }
        case .system(let rows):
            switch rows[indexPath.row] {
            case .advanced:
                delegate?.advancedSettingsSelected(in: self)
            case .notifications, .passcode:
                break
            case .selectActiveNetworks:
                delegate?.activeNetworksSelected(in: self)
            }
        case .help:
            delegate?.helpSelected(in: self)
        case .tokenStandard:
            self.delegate?.didPressOpenWebPage(TokenScript.tokenScriptSite, in: self)
        case .version:
            break
        }
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return viewModel.heightForRow(at: indexPath, fallbackHeight: tableView.rowHeight)
    }
}
