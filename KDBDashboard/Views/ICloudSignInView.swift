import SwiftUI

/// tvOS-optimized sign-in form for iCloud CalDAV credentials
struct ICloudSignInView: View {
    @ObservedObject var icloudService: ICloudCalendarService
    @State private var email: String = ""
    @State private var appSpecificPassword: String = ""
    @State private var editingEmail = false
    @State private var editingPassword = false
    @State private var tempInput = ""
    var onDismiss: () -> Void

    enum FocusField {
        case emailButton
        case passwordButton
        case cancelButton
        case signInButton
    }

    @FocusState private var focusedField: FocusField?

    var body: some View {
        VStack(spacing: 25) {
            // Header
            Image(systemName: "icloud")
                .font(.system(size: 50))
                .foregroundColor(.blue)

            Text("Connect iCloud Calendar")
                .font(.title2)
                .foregroundColor(.white)

            // Instructions
            VStack(alignment: .leading, spacing: 8) {
                Text("You need an App-Specific Password:")
                    .foregroundColor(.white.opacity(0.8))
                    .font(.callout)

                Group {
                    Text("1. On another device, go to appleid.apple.com")
                    Text("2. Sign-In and Security > App-Specific Passwords")
                    Text("3. Generate a password named \"KDB Dashboard\"")
                    Text("4. Enter your Apple ID and the password below")
                }
                .font(.caption)
                .foregroundColor(.white.opacity(0.5))
            }

            // Input fields
            VStack(spacing: 15) {
                // Email field
                VStack(spacing: 4) {
                    Text("Apple ID Email")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button(action: {
                        tempInput = email
                        editingEmail = true
                    }) {
                        ICloudInputButtonContent(
                            text: email,
                            placeholder: "Enter Apple ID",
                            backgroundColor: Color.white.opacity(0.15)
                        )
                    }
                    .buttonStyle(ICloudInputButtonStyle())
                    .focused($focusedField, equals: .emailButton)
                }

                // Password field
                VStack(spacing: 4) {
                    Text("App-Specific Password")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button(action: {
                        tempInput = appSpecificPassword
                        editingPassword = true
                    }) {
                        ICloudInputButtonContent(
                            text: appSpecificPassword.isEmpty ? "" : String(repeating: "•", count: appSpecificPassword.count),
                            placeholder: "Enter Password",
                            backgroundColor: Color.white.opacity(0.15)
                        )
                    }
                    .buttonStyle(ICloudInputButtonStyle())
                    .focused($focusedField, equals: .passwordButton)
                }
            }
            .padding(.horizontal, 40)
            .alert("Enter Apple ID Email", isPresented: $editingEmail) {
                TextField("Email", text: $tempInput)
                    .textContentType(.emailAddress)
                    .autocapitalization(.none)
                Button("Cancel", role: .cancel) {
                    tempInput = ""
                }
                Button("OK") {
                    email = tempInput
                    tempInput = ""
                }
            } message: {
                Text("Enter your Apple ID email address")
            }
            .alert("Enter App-Specific Password", isPresented: $editingPassword) {
                TextField("Password", text: $tempInput)
                    .textContentType(.password)
                Button("Cancel", role: .cancel) {
                    tempInput = ""
                }
                Button("OK") {
                    appSpecificPassword = tempInput
                    tempInput = ""
                }
            } message: {
                Text("Enter your app-specific password")
            }

            // Error message
            if let error = icloudService.errorMessage {
                Text(error)
                    .font(.callout)
                    .foregroundColor(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            // Loading indicator
            if icloudService.isLoading {
                HStack(spacing: 10) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Connecting...")
                        .foregroundColor(.white.opacity(0.6))
                }
            }

            // Action buttons
            HStack(spacing: 30) {
                Button {
                    onDismiss()
                } label: {
                    Text("Cancel")
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.card)
                .focused($focusedField, equals: .cancelButton)

                Button {
                    Task {
                        await icloudService.signIn(email: email, password: appSpecificPassword)
                        if icloudService.isAuthenticated {
                            onDismiss()
                        }
                    }
                } label: {
                    Text("Sign In")
                        .foregroundColor(.white)
                        .fontWeight(.medium)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.card)
                .disabled(email.isEmpty || appSpecificPassword.isEmpty || icloudService.isLoading)
                .focused($focusedField, equals: .signInButton)
            }
        }
        .padding(50)
        .background(
            Color(.sRGB, red: 0.12, green: 0.12, blue: 0.18, opacity: 1.0)
        )
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .padding(40)
        .onAppear {
            // Set initial focus to email field
            focusedField = .emailButton
        }
    }
}

// Custom button style for iCloud input fields
struct ICloudInputButtonStyle: ButtonStyle {
    @Environment(\.isFocused) var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .environment(\.icloudInputButtonFocused, isFocused)
    }
}

// Custom environment key for iCloud input
private struct ICloudInputButtonFocusedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var icloudInputButtonFocused: Bool {
        get { self[ICloudInputButtonFocusedKey.self] }
        set { self[ICloudInputButtonFocusedKey.self] = newValue }
    }
}

// Content view for iCloud input buttons
struct ICloudInputButtonContent: View {
    let text: String
    let placeholder: String
    let backgroundColor: Color
    @Environment(\.icloudInputButtonFocused) var isFocused

    var body: some View {
        HStack {
            if text.isEmpty {
                Text(placeholder)
                    .font(.body)
                    .foregroundColor(isFocused ? .blue : .white.opacity(0.5))
            } else {
                Text(text)
                    .font(.body)
                    .foregroundColor(isFocused ? .blue : .white)
            }
            Spacer()
        }
        .padding(16)
        .background(backgroundColor)
        .cornerRadius(12)
        .frame(maxWidth: .infinity)
    }
}
