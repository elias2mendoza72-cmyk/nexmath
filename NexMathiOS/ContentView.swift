import SwiftUI

struct ContentView: View {
    @State private var showSplash = true

    var body: some View {
        ZStack {
            ChatScreen()

            if showSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .onAppear {
            guard showSplash else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                withAnimation(.easeOut(duration: 0.4)) {
                    showSplash = false
                }
            }
        }
    }
}

struct SplashView: View {
    @State private var pulse = false
    @State private var glowPulse = false
    @State private var float = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.04, green: 0.04, blue: 0.05), Color(red: 0.10, green: 0.10, blue: 0.18)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color(red: 0.34, green: 0.24, blue: 0.92).opacity(0.35))
                .frame(width: 320, height: 320)
                .blur(radius: 28)
                .scaleEffect(glowPulse ? 1.08 : 0.98)
                .opacity(glowPulse ? 0.65 : 0.45)

            VStack(spacing: 14) {
                Image("NexMathLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 128, height: 128)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .shadow(color: Color(red: 0.13, green: 0.83, blue: 0.93, opacity: 0.35), radius: 18, x: 0, y: 10)
                    .scaleEffect(pulse ? 1.03 : 0.99)
                    .offset(y: float ? -4 : 4)

                Image("NexMathWordmark")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 34)
                    .scaleEffect(pulse ? 1.01 : 1.0)

                Text("CALCULUS, INSTANTLY CLARIFIED.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.55))
                    .tracking(2.2)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) {
                pulse.toggle()
            }
            withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
                glowPulse.toggle()
            }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                float.toggle()
            }
        }
    }
}

#Preview {
    ContentView()
}
