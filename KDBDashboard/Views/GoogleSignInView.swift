import SwiftUI

/// Shows the Google device code while waiting for the user to authorize on another device
struct GoogleSignInView: View {
    @ObservedObject var googleService: GoogleCalendarService
    let deviceCode: DeviceCodeResponse

    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "laptopcomputer.and.iphone")
                .font(.system(size: 60))
                .foregroundColor(.orange)

            Text("Sign in on another device")
                .font(.title2)
                .foregroundColor(.white)

            VStack(spacing: 15) {
                Text("1. On your phone or computer, go to:")
                    .foregroundColor(.white.opacity(0.8))

                Text(deviceCode.verificationUrl)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.orange)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(10)

                Text("2. Enter this code:")
                    .foregroundColor(.white.opacity(0.8))

                Text(deviceCode.userCode)
                    .font(.system(size: 48, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .tracking(8)
                    .padding(.horizontal, 30)
                    .padding(.vertical, 15)
                    .background(Color.orange.opacity(0.3))
                    .cornerRadius(15)
            }

            HStack(spacing: 10) {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Waiting for authorization...")
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(.top, 10)

            Button {
                googleService.signOut()
            } label: {
                Text("Cancel")
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.card)
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
    }
}
