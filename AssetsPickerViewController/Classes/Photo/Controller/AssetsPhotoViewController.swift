//
//  AssetsPhotoViewController.swift
//  Pods
//
//  Created by DragonCherry on 5/17/17.
//
//

import UIKit
import Photos
import PhotosUI
import SnapKit

// MARK: - AssetsPhotoViewController
open class AssetsPhotoViewController: UIViewController {
    
    override open var preferredStatusBarStyle: UIStatusBarStyle {
        return AssetsPickerConfig.statusBarStyle
    }
    
    var isAccessLimited: Bool{
        get{
            if #available(iOS 14, *) {
                #if targetEnvironment(macCatalyst)
                return false
                #else
                let accessLevel: PHAccessLevel = .readWrite
                let status = PHPhotoLibrary.authorizationStatus(for: accessLevel)
                return status == .limited
                #endif
                
            }
            return false
        }
    }
    
    // MARK: Properties
    var pickerConfig: AssetsPickerConfig!
    var previewing: UIViewControllerPreviewing?
    let cameraPicker = AssetsPickerManager()
    var newlySavedIdentifier: String?
    
    let cellReuseIdentifier: String = UUID().uuidString
    let footerReuseIdentifier: String = UUID().uuidString
    
    let fetchService = AssetsFetchService()
    
    var previousPreheatRect: CGRect = .zero
    
    lazy var cancelButtonItem: UIBarButtonItem = {
        let buttonItem = UIBarButtonItem(barButtonSystemItem: .cancel,
                                         target: self,
                                         action: #selector(pressedCancel(button:)))
        return buttonItem
    }()
    lazy var takeButtonItem: UIBarButtonItem = {
        let buttonItem = UIBarButtonItem(barButtonSystemItem: .camera, target: self, action: #selector(pressedCamera(button:)))
        return buttonItem
    }()
    lazy var doneButtonItem: UIBarButtonItem = {
        let buttonItem = UIBarButtonItem(barButtonSystemItem: .done,
                                         target: self,
                                         action: #selector(pressedDone(button:)))
        return buttonItem
    }()
    let emptyView: AssetsEmptyView = {
        return AssetsEmptyView()
    }()
    let noPermissionView: AssetsNoPermissionView = {
        return AssetsNoPermissionView()
    }()
    var delegate: AssetsPickerViewControllerDelegate? {
        return (navigationController as? AssetsPickerViewController)?.pickerDelegate
    }
    var picker: AssetsPickerViewController {
        return navigationController as! AssetsPickerViewController
    }
    var tapGesture: UITapGestureRecognizer?
    var syncOffsetRatio: CGFloat = -1
    
    var selectedArray = [PHAsset]()
    var selectedMap = [String: PHAsset]()
    var isDragSelectionEnabled: Bool = false
    var didSetInitialPosition: Bool = false
    
    var isPortrait: Bool = true
    
    var leadingConstraint: LayoutConstraint?
    var trailingConstraint: LayoutConstraint?
    
    lazy var collectionView: UICollectionView = {
        
        let layout = AssetsPhotoLayout(pickerConfig: self.pickerConfig)
        self.updateLayout(layout: layout, isPortrait: UIApplication.shared.statusBarOrientation.isPortrait)
        layout.scrollDirection = .vertical
        
        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.allowsMultipleSelection = true
        view.allowsSelection = true
        view.alwaysBounceVertical = true
        view.register(self.pickerConfig.assetCellType, forCellWithReuseIdentifier: self.cellReuseIdentifier)
        view.register(AssetsPhotoFooterView.classForCoder(), forSupplementaryViewOfKind: UICollectionView.elementKindSectionFooter, withReuseIdentifier: self.footerReuseIdentifier)
        view.contentInset = UIEdgeInsets(top: 1, left: 0, bottom: 0, right: 0)
        view.backgroundColor = .clear
        view.dataSource = self
        view.delegate = self
        view.remembersLastFocusedIndexPath = true
        if #available(iOS 10.0, *) {
            view.prefetchDataSource = self
        }
        view.showsHorizontalScrollIndicator = false
        view.showsVerticalScrollIndicator = true
        
        return view
    }()
    
    lazy var loadingActivityIndicatorView: UIActivityIndicatorView = {
        
        if #available(iOS 13.0, *) {
            if UITraitCollection.current.userInterfaceStyle == .dark {
                let indicator = UIActivityIndicatorView(style: .whiteLarge)
                return indicator
            } else {
                let indicator = UIActivityIndicatorView(style: .large)
                return indicator
            }
        } else {
            let indicator = UIActivityIndicatorView()
            return indicator
        }
    }()
    lazy var loadingPlaceholderView: UIView = UIView()
    
    // MARK: Lifecycle Methods
    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    override public init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }
    
    override open func loadView() {
        super.loadView()
        view = UIView()
		view.backgroundColor = .ap_background
        view.addSubview(collectionView)
        view.addSubview(emptyView)
        view.addSubview(noPermissionView)
        view.setNeedsUpdateConstraints()
        view.addSubview(loadingPlaceholderView)
        view.addSubview(loadingActivityIndicatorView)
    }
    
    override open func viewDidLoad() {
        super.viewDidLoad()
        
        setupCommon()
        setupBarButtonItems()
        setupCollectionView()
        setupPlaceholderView()
        setupLoadActivityIndicatorView()
        
        updateEmptyView(count: 0)
        updateNoPermissionView()
        
        if let selectedAssets = self.pickerConfig?.selectedAssets {
            setSelectedAssets(assets: selectedAssets)
        }
        
        AssetsManager.shared.authorize { [weak self] (isGranted) in
            guard let `self` = self else { return }
            self.updateNoPermissionView()
            if isGranted {
                self.setupAssets()
            } else {
                self.delegate?.assetsPickerCannotAccessPhotoLibrary?(controller: self.picker)
            }
        }
        
        if isAccessLimited {
            let bannerHeight: CGFloat = 70
            let topView = UIView()
            view.addSubview(topView)
            topView.translatesAutoresizingMaskIntoConstraints = false
            topView.leadingAnchor.constraint(equalTo: collectionView.leadingAnchor, constant: 0).isActive = true
            topView.trailingAnchor.constraint(equalTo: collectionView.trailingAnchor, constant: 0).isActive = true
            topView.heightAnchor.constraint(equalToConstant: bannerHeight).isActive = true
            
            collectionView.contentInset = UIEdgeInsets(top: collectionView.contentInset.top + bannerHeight, left: collectionView.contentInset.left, bottom: collectionView.contentInset.right, right: collectionView.contentInset.bottom)
            topView.backgroundColor = self.pickerConfig.limitedDiscalmerBackgroundcolor
            DispatchQueue.main.async {
                //topView.topAnchor.constraint(equalTo: self.collectionView.topAnchor, constant: abs(self.collectionView.contentInset.top) - 30).isActive = true
                topView.topAnchor.constraint(equalTo: self.collectionView.topAnchor, constant: abs(self.topbarHeight)).isActive = true
                
                let button = UIButton()
                topView.addSubview(button)
                button.translatesAutoresizingMaskIntoConstraints = false
                button.setTitle(self.pickerConfig.manageText, for: .normal)
                button.setTitleColor(self.pickerConfig.limitedDisclamerTextColor, for: .normal)
                button.centerYAnchor.constraint(equalTo: topView.centerYAnchor).isActive = true
                button.trailingAnchor.constraint(equalTo: topView.trailingAnchor, constant: -20).isActive = true
                button.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
                //button.titleLabel?.font = self.pickerConfig.manageTextFont
                
                let label = UILabel()
                topView.addSubview(label)
                label.translatesAutoresizingMaskIntoConstraints = false
                label.adjustsFontSizeToFitWidth = true
                label.centerYAnchor.constraint(equalTo: topView.centerYAnchor).isActive = true
                label.textColor = self.pickerConfig.limitedDisclamerTextColor
                label.numberOfLines = 2
                label.leadingAnchor.constraint(equalTo: topView.leadingAnchor, constant: 20).isActive = true
                label.trailingAnchor.constraint(equalTo: button.leadingAnchor, constant: -12).isActive = true
                label.text = self.pickerConfig.limitedAccessText
                label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
                //label.font = self.pickerConfig.limitedAccessTextFont
                label.textAlignment = .left
                label.minimumScaleFactor = 0.2
                if #available(iOS 14, *) {
                    button.addTarget(self, action: #selector(self.didButtonClick), for: .touchUpInside)
                }
            }
        }
    }
    
    @available(iOS 14, *)
    @objc func didButtonClick(_ sender: UIButton) {
        let actionSheet = UIAlertController(title: self.pickerConfig.limitedAccessPopupTitle, message: "", preferredStyle: UIAlertController.Style.actionSheet)
        let selecPhoto = UIAlertAction(title: pickerConfig.selectPhotoText, style: .default) { (action: UIAlertAction) in
            PHPhotoLibrary.shared().register(self)
            #if targetEnvironment(macCatalyst)
              //code to run on macOS
            #else
                PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: self)
            #endif
            
            
        }
        let settings = UIAlertAction(title: pickerConfig.modifySettingsText, style: .default) { (action: UIAlertAction) in
            UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
        }
        
        let continueSheet = UIAlertAction(title: pickerConfig.cancelText, style: .cancel) { (action: UIAlertAction) in
        }

        actionSheet.addAction(selecPhoto)
        actionSheet.addAction(settings)
        actionSheet.addAction(continueSheet)
        if let popoverController = actionSheet.popoverPresentationController {
            popoverController.sourceView = self.view
            popoverController.sourceRect = CGRect(x: self.view.bounds.midX, y: self.view.bounds.midY, width: 0, height: 0)
            popoverController.permittedArrowDirections = []
        }
        self.present(actionSheet, animated: true, completion: nil)
    }
    
    override open func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if let previewing = self.previewing {
            if traitCollection.forceTouchCapability != .available {
                unregisterForPreviewing(withContext: previewing)
                self.previewing = nil
            }
        } else {
            if traitCollection.forceTouchCapability == .available {
                self.previewing = registerForPreviewing(with: self, sourceView: collectionView)
            }
        }
    }
    
    override open func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if !didSetInitialPosition {
            if pickerConfig.assetsIsScrollToBottom {
                guard let fetchResult = AssetsManager.shared.fetchResult else { return }
                let count = fetchResult.count
                if count > 0 {
                    if self.collectionView.collectionViewLayout.collectionViewContentSize.height > 0 {
                        let lastRow = self.collectionView.numberOfItems(inSection: 0) - 1
                        self.collectionView.scrollToItem(at: IndexPath(row: lastRow, section: 0), at: .bottom, animated: false)
                    }
                }
            }
            didSetInitialPosition = true
        }
    }
    
    open func deselectAll() {
        var indexPaths = [IndexPath]()
        guard let fetchResult = AssetsManager.shared.fetchResult else { return }
        for selectedAsset in selectedArray {
            let row = fetchResult.index(of: selectedAsset)
            let indexPath = IndexPath(row: row, section: 0)
            deselectCell(at: indexPath)
            delegate?.assetsPicker?(controller: picker, didDeselect: selectedAsset, at: indexPath)
            indexPaths.append(indexPath)
        }
        updateSelectionCount()
        updateNavigationStatus()
        collectionView.reloadItems(at: indexPaths)
    }
    
    @available(iOS 11.0, *)
    override open func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        leadingConstraint?.constant = view.safeAreaInsets.left
        trailingConstraint?.constant = -view.safeAreaInsets.right
        updateLayout(layout: collectionView.collectionViewLayout)
        logi("\(view.safeAreaInsets)")
    }
    
    override open func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        let isPortrait = size.height > size.width
        let contentSize = CGSize(width: size.width, height: size.height)
        if let photoLayout = collectionView.collectionViewLayout as? AssetsPhotoLayout {
            if let offset = photoLayout.translateOffset(forChangingSize: contentSize, currentOffset: collectionView.contentOffset) {
                photoLayout.translatedOffset = offset
                logi("translated offset: \(offset)")
            }
            coordinator.animate(alongsideTransition: { (_) in
            }) { (_) in
                photoLayout.translatedOffset = nil
            }
        }
        updateLayout(layout: collectionView.collectionViewLayout, isPortrait: isPortrait)
    }
    
    override open func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateNavigationStatus()
    }
    
    override open func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        setupGestureRecognizer()
        if traitCollection.forceTouchCapability == .available {
            previewing = registerForPreviewing(with: self, sourceView: collectionView)
        }
    }
    
    override open func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        removeGestureRecognizer()
        if let previewing = self.previewing {
            self.previewing = nil
            unregisterForPreviewing(withContext: previewing)
        }
    }
    
    deinit {
        logd("Released \(type(of: self))")
    }
}

extension UICollectionView {
    var fullyVisibleCells: [UICollectionViewCell] {
        return self.visibleCells.filter { cell in
            let cellRect = self.convert(cell.frame, to: self.superview)
            return self.frame.contains(cellRect)
        }
    }
}

extension UIViewController {

    /**
     *  Height of status bar + navigation bar (if navigation bar exist)
     */

    var topbarHeight: CGFloat {
        return //UIApplication.shared.statusBarFrame.size.height +
            (self.navigationController?.navigationBar.frame.height ?? 0.0)
    }
}

extension AssetsPhotoViewController: PHPhotoLibraryChangeObserver{
    public func photoLibraryDidChange(_ changeInstance: PHChange) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.setupAssets()

        }
    }
}
