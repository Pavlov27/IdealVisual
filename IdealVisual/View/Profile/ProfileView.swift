//
//  ProfileView.swift
//  IdealVisual
//
//  Created by a.kurganova on 03/10/2019.
//  Copyright © 2019 a.kurganova. All rights reserved.
//

import CoreData
import Foundation
import UIKit
import Photos

final class ProfileView: UIView {
    private var dataState = State()

    private weak var delegateProfile: ProfileDelegate?
    private var userViewModel: UserViewModelProtocol?

    private let scroll: UIScrollView = UIScrollView()
    private var navBar: UIView? = UIView()

    private var height: NSLayoutConstraint?

    private var username: InputFields
    private var email: InputFields
    private var password: InputFields
    private var repeatPassword: InputFields

    private var testAva: UIImagePickerController = UIImagePickerController()
    private let ava: UIImageView = UIImageView()
    private var avaContent: Data? // for saving
    private var avaName: String?

    override func layoutSubviews() {
        super.layoutSubviews()
        navBar?.frame.size = CGSize(width: frame.width, height: 45)
        navBar?.frame.origin = CGPoint(x: 0, y: ((UIApplication.shared.keyWindow?.safeAreaInsets.top)! + 10))
    }

    init(profileDelegate: ProfileDelegate) {
        self.delegateProfile = profileDelegate
        self.userViewModel = UserViewModel()
        self.username = InputFields()
        self.email = InputFields()
        self.password = InputFields()
        self.repeatPassword = InputFields()
        super.init(frame: CGRect())

        navBar = UIView()
        addSubview(navBar!)

        userViewModel?.get(completion: { [weak self] (user, error) in
            DispatchQueue.main.async {
                if let error = error {
                    switch error {
                    case ErrorsUserViewModel.noData:
                        Logger.log(error)
                        self?._error(text: "Упс, что-то пошло не так.")
                    default:
                        Logger.log(error)
                        self?._error(text: "Упс, что-то пошло не так.")
                    }
                }

                guard let user = user else {
                    return
                }

                self?.username = InputFields(labelImage: UIImage(named: "login"),
                                                   text: user.username,
                                                   placeholder: nil, validator: checkValidUsername)
                self?.email = InputFields(labelImage: UIImage(named: "email"),
                                                text: user.email,
                                                placeholder: nil, validator: checkValidEmail)
                self?.password = InputFields(labelImage: UIImage(named: "password"),
                                                   text: nil, placeholder: "Пароль",
                                                   textContentType: .newPassword, validator: checkValidPassword)
                self?.repeatPassword = InputFields(labelImage: UIImage(named: "password"),
                                                         text: nil, placeholder: "Повторите пароль",
                                                         textContentType: .newPassword, validator: checkValidPassword)
            }
        })
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

// MARK: - no edit mode
    private func setNoEdit() {
        testAva.delegate = self
        testAva.allowsEditing = true
        ava.isUserInteractionEnabled = false

        let swipe = UISwipeGestureRecognizer()
        swipe.direction = .up
        swipe.addTarget(self, action: #selector(closeProfile))
        self.addGestureRecognizer(swipe)

        setNavButtons(edit_mode: false)
        setAva()
        setFields()
        [username, email, password, repeatPassword].forEach {
            $0.setEditFields(state: false)
        }
        password.isHidden = true
        repeatPassword.isHidden = true
        renderBottomLine()
    }

// MARK: - edit mode
    @objc
    private func setEdit() {
        dataState.username = username.textField.text ?? ""
        dataState.email = email.textField.text ?? ""
        dataState.oldAva = ava.image

        height?.isActive = false
        setNavButtons(edit_mode: true)

        height = self.heightAnchor.constraint(equalToConstant: self.bounds.height + 155)
        height?.isActive = true

        let tap = UITapGestureRecognizer()
        ava.isUserInteractionEnabled = true
        ava.addGestureRecognizer(tap)
        tap.addTarget(self, action: #selector(chooseAva))

        [username, email, password, repeatPassword].forEach {
            $0.setEditFields(state: true)
        }
        setPassword()
    }

    // MARK: - save/not save settings
    @objc
    private func save_settings() {
        if dataState.email == email.textField.text &&
            dataState.username == username.textField.text &&
            dataState.oldAva == ava.image &&
            password.textField.text?.count == 0 &&
            repeatPassword.textField.text?.count == 0 {

            password.textField.text = ""
            password.clearState()
            repeatPassword.textField.text = ""
            repeatPassword.clearState()

            setupView()

            return
        }

        let usernameIsValid = username.isValid()
        let emailIsValid = email.isValid()
        var pairIsValid = true
        if password.textField.text?.count != 0 || repeatPassword.textField.text?.count != 0 {
            pairIsValid = checkValidPasswordPair(field: password, fieldRepeat: repeatPassword)
        }

        if !(usernameIsValid && emailIsValid && pairIsValid) {
            return
        }

        guard let usrInput = username.textField.text,
            let emlInput = email.textField.text,
            let pasInput = password.textField.text
        else { return }

        if usrInput == "" && emlInput == "" && pasInput == "" && avaContent == nil {
            return
        }

        let loadingIndicator = UIActivityIndicatorView(frame: CGRect(x: navBar!.frame.width / 2 + 70,
                                                                     y: 0,
                                                                     width: 50, height: 50))
        loadingIndicator.color = Colors.blue
        loadingIndicator.hidesWhenStopped = true
        navBar!.addSubview(loadingIndicator)
        loadingIndicator.startAnimating()

        userViewModel?.update(username: usrInput, email: emlInput, ava: avaContent, avaName: avaName,
                              password: pasInput, completion: { [weak self] (error) in
            DispatchQueue.main.async {
                if let error = error {
                    switch error {
                    case ErrorsUserViewModel.usernameAlreadyExists:
                        self?.username.setError(text: "Такое имя пользователя уже занято")
                    case ErrorsUserViewModel.usernameLengthIsWrong:
                        self?.username.setError(text: "Неверная длина имени пользователя, минимум: 4")
                    case ErrorsUserViewModel.emailFormatIsWrong:
                        self?.email.setError(text: "Неверный формат почты")
                    case ErrorsUserViewModel.emailAlreadyExists:
                        self?.email.setError(text: "Такая почта уже занята")
                    case ErrorsUserViewModel.passwordLengthIsWrong:
                        self?.password.setError(text: "Неверная длина пароля")
                    case ErrorsUserViewModel.noConnection:
                        self?._error(text: "Нет соединения с интернетом", color: Colors.darkGray)
                    case ErrorsUserViewModel.unauthorized:
                        Logger.log(error)
                        self?._error(text: "Вы не авторизованы")
                        sleep(3)
                        self?.delegateProfile?.logOut()
                    case ErrorsUserViewModel.noData:
                        Logger.log(error)
                        self?._error(text: "Невозможно загрузить данные", color: Colors.darkGray)
                    case ErrorsUserViewModel.notFound:
                        Logger.log(error)
                        self?._error(text: "Такого пользователя нет")
                        sleep(3)
                        self?.delegateProfile?.logOut()
                    default:
                        Logger.log(error)
                        self?._error(text: "Упс, что-то пошло не так.")
                    }
                    loadingIndicator.stopAnimating()
                    return
                }

                self?.password.textField.text = ""
                self?.password.clearState()
                self?.repeatPassword.textField.text = ""
                self?.repeatPassword.clearState()

                loadingIndicator.stopAnimating()
                self?.setupView()

                guard let a = self?.ava.image else { return }
                self?.delegateProfile?.updateAvatar(image: a)
            }
        })
    }

    @objc
    private func no_settings() {
        username.textField.text = dataState.username
        email.textField.text = dataState.email
        password.textField.text = ""
        repeatPassword.textField.text = ""

        username.clearState()
        email.clearState()
        password.clearState()
        repeatPassword.clearState()

        if let oldAvaImage = dataState.oldAva {
            ava.image = oldAvaImage
        }

        removeConstraint(height!)
        setupView()
    }

    // MARK: - close view/logout
    @objc
    func closeProfile() {
        height?.isActive = false
        no_settings()
        removeFromSuperview()
        delegateProfile?.enableTabBarButton()
    }

    @objc
    private func logout() {
        delegateProfile?.logOut()
    }

    // MARK: - ui error
    private func _error(text: String, color: UIColor? = Colors.red) {
        let er = UIError(text: text, place: scroll, color: color)
        scroll.addSubview(er)
        er.translatesAutoresizingMaskIntoConstraints = false
        er.leftAnchor.constraint(equalTo: navBar!.leftAnchor).isActive = true
        er.rightAnchor.constraint(equalTo: navBar!.rightAnchor).isActive = true
        er.topAnchor.constraint(equalTo: navBar!.bottomAnchor).isActive = true
    }
}

// MARK: - setup view
extension ProfileView {
    func setup() {
        setupView()
    }

    private func setupView() {
        self.translatesAutoresizingMaskIntoConstraints = false
        let currentWindow: UIWindow? = UIApplication.shared.keyWindow
        currentWindow?.addSubview(self)
        self.widthAnchor.constraint(equalTo: (superview?.safeAreaLayoutGuide.widthAnchor)!).isActive = true
        self.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        self.layer.cornerRadius = 20
        self.topAnchor.constraint(equalTo: (superview?.topAnchor)!).isActive = true
        self.leftAnchor.constraint(equalTo: (superview?.safeAreaLayoutGuide.leftAnchor)!).isActive = true
        self.rightAnchor.constraint(equalTo: (superview?.safeAreaLayoutGuide.rightAnchor)!).isActive = true
        self.backgroundColor = .white
        self.layer.shadowColor = Colors.darkDarkGray.cgColor
        self.layer.shadowRadius = 5.0
        self.layer.shadowOpacity = 50.0

        height = self.heightAnchor.constraint(equalToConstant: 465)
        height?.isActive = true

        let hideKey: UITapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(taped))
        self.addGestureRecognizer(hideKey)

        setScroll()
        setNoEdit()

        dataState.username = username.textField.text ?? ""
        dataState.email = email.textField.text ?? ""
        dataState.oldAva = ava.image
    }
}

// MARK: - nav
extension ProfileView {
    private func setNavButtons(edit_mode: Bool) {
        if !edit_mode {
            guard let markSettings = UIImage(named: "settings") else { return }
            let settings = SubstrateButton(image: markSettings, side: 33, target: self, action: #selector(setEdit),
                                           substrateColor: Colors.lightBlue)
            navBar?.addSubview(settings)
            settings.translatesAutoresizingMaskIntoConstraints = false
            settings.topAnchor.constraint(equalTo: navBar!.topAnchor, constant: 7).isActive = true
            settings.leftAnchor.constraint(equalTo: navBar!.leftAnchor, constant: 20).isActive = true

            guard let markLogout = UIImage(named: "logout") else { return }
            let substrateLogout = SubstrateButton(image: markLogout, side: 33, target: self,
                                                  action: #selector(logout), substrateColor: Colors.darkGray)
            navBar?.addSubview(substrateLogout)
            substrateLogout.translatesAutoresizingMaskIntoConstraints = false
            substrateLogout.topAnchor.constraint(equalTo: navBar!.topAnchor, constant: 7).isActive = true
            substrateLogout.rightAnchor.constraint(equalTo: navBar!.rightAnchor, constant: -20).isActive = true
        } else {
            guard let markYes = UIImage(named: "yes") else { return }
            let yes = SubstrateButton(image: markYes, side: 33, target: self, action: #selector(save_settings),
                                      substrateColor: Colors.yellow)
            navBar?.addSubview(yes)
            yes.translatesAutoresizingMaskIntoConstraints = false
            yes.topAnchor.constraint(equalTo: navBar!.topAnchor, constant: 7).isActive = true
            yes.rightAnchor.constraint(equalTo: navBar!.rightAnchor, constant: -20).isActive = true

            guard let markNo = UIImage(named: "close") else { return }
            let substrateNot = SubstrateButton(image: markNo, side: 33, target: self, action: #selector(no_settings),
                                     substrateColor: Colors.darkGray)
            navBar?.addSubview(substrateNot)
            substrateNot.translatesAutoresizingMaskIntoConstraints = false
            substrateNot.topAnchor.constraint(equalTo: navBar!.topAnchor, constant: 7).isActive = true
            substrateNot.leftAnchor.constraint(equalTo: navBar!.leftAnchor, constant: 20).isActive = true
        }
    }
}

// MARK: - scroll and keyboard
extension ProfileView {
    private func setScroll() {
        addSubview(scroll)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.topAnchor.constraint(equalTo: navBar!.bottomAnchor).isActive = true
        scroll.leftAnchor.constraint(equalTo: leftAnchor).isActive = true
        scroll.rightAnchor.constraint(equalTo: rightAnchor).isActive = true
        scroll.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true

        // tap on keyboard
        let tapp = UITapGestureRecognizer()
        scroll.addGestureRecognizer(tapp)
        tapp.addTarget(self, action: #selector(taped))
    }

    @objc
    func taped() {
        self.endEditing(true)
    }
}

// MARK: - set username, email
extension ProfileView {
    private func setFields() {
        [username, email].forEach {
            scroll.addSubview($0)
            $0.translatesAutoresizingMaskIntoConstraints = false
            $0.centerXAnchor.constraint(equalTo: scroll.centerXAnchor).isActive = true
            $0.heightAnchor.constraint(equalToConstant: 40).isActive = true
            $0.widthAnchor.constraint(equalToConstant: 300).isActive = true
        }
        username.topAnchor.constraint(equalTo: ava.bottomAnchor, constant: 30).isActive = true
        email.topAnchor.constraint(equalTo: username.bottomAnchor, constant: 30).isActive = true
    }
}

// MARK: - passwords
extension ProfileView {
    private func setPassword() {
        [password, repeatPassword].forEach {
            scroll.addSubview($0)
            $0.translatesAutoresizingMaskIntoConstraints = false
            $0.centerXAnchor.constraint(equalTo: scroll.centerXAnchor).isActive = true
            $0.heightAnchor.constraint(equalToConstant: 40).isActive = true
            $0.widthAnchor.constraint(equalToConstant: 300).isActive = true
            $0.isHidden = false
        }
        password.topAnchor.constraint(equalTo: email.bottomAnchor, constant: 30).isActive = true
        repeatPassword.topAnchor.constraint(equalTo: password.bottomAnchor, constant: 30).isActive = true
    }
}

// MARK: - ava
extension ProfileView {
    private func setAva() {
        scroll.addSubview(ava)
        ava.translatesAutoresizingMaskIntoConstraints = false
        ava.centerXAnchor.constraint(equalTo: scroll.centerXAnchor).isActive = true
        ava.topAnchor.constraint(equalTo: scroll.topAnchor, constant: 10).isActive = true
        ava.widthAnchor.constraint(equalToConstant: 170).isActive = true
        ava.heightAnchor.constraint(equalToConstant: 170).isActive = true
        ava.contentMode = .scaleAspectFill
        ava.layer.maskedCorners = [.layerMaxXMaxYCorner, .layerMaxXMinYCorner,
                                   .layerMinXMaxYCorner, .layerMinXMinYCorner]
        ava.layer.cornerRadius = 10
        ava.layer.masksToBounds = true

        let loadingIndicator = UIActivityIndicatorView(frame: CGRect(x: 60,
                                                                     y: 60,
                                                                     width: 50, height: 50))
        ava.addSubview(loadingIndicator)
        loadingIndicator.color = Colors.blue
        loadingIndicator.hidesWhenStopped = true
        loadingIndicator.startAnimating()

        userViewModel?.getAvatar(completion: { [weak self] (avatar, error) in
            DispatchQueue.main.async {
                loadingIndicator.stopAnimating()
                if let error = error {
                    switch error {
                    case ErrorsUserViewModel.noData:
                        Logger.log(error)
                        self?._error(text: "Невозможно загрузить фотографию", color: Colors.darkGray)
                    default:
                        Logger.log(error)
                        self?._error(text: "Упс, что-то пошло не так.")
                    }
                    return
                }

                guard let avatar = avatar else {
                    self?.ava.image = UIImage(named: "default_profile")
                    return
                }
                self?.ava.image = UIImage(contentsOfFile: avatar)
            }
        })
    }
}

// MARK: - picker
extension ProfileView: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController,
                               didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        if let url = info[UIImagePickerController.InfoKey.imageURL] as? URL {
            if let selected = info[UIImagePickerController.InfoKey.originalImage] as? UIImage {
                dataState.oldAva = ava.image
                ava.image = selected

                avaName = url.lastPathComponent
                avaContent = selected.jpegData(compressionQuality: 1.0)
            }
        }
        delegateProfile?.dismissAlert()
    }

    @objc private func chooseAva() {
        let alert = UIAlertController(title: "Выберите изображение",
                                      message: nil,
                                      preferredStyle: .actionSheet)

        alert.addAction(UIAlertAction(title: "Галерея",
                                      style: .default,
                                      handler: { _ in { self.testAva.sourceType = .photoLibrary
                                                        self.delegateProfile?.chooseAvatar(picker: self.testAva) }() }
            ))
        if UIImagePickerController.availableCaptureModes(for: .rear) != nil {
            alert.addAction(UIAlertAction(title: "Камера",
                                          style: .default,
                                          handler: { _ in { self.testAva.sourceType = .camera
                                                            self.testAva.cameraCaptureMode = .photo
                                                            self.delegateProfile?.chooseAvatar(picker: self.testAva)
                                            }() }
            ))
        }
        alert.addAction(UIAlertAction(title: "Отменить", style: UIAlertAction.Style.cancel, handler: nil))
        delegateProfile?.showAlert(alert: alert)
    }
}

// MARK: - bottom line
extension ProfileView {
    private func renderBottomLine() {
        let lineBottom = LineClose()
        scroll.addSubview(lineBottom)
        lineBottom.translatesAutoresizingMaskIntoConstraints = false
        lineBottom.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -15).isActive = true
        lineBottom.centerXAnchor.constraint(equalTo: self.centerXAnchor, constant: -23).isActive = true
    }
}
