import SwiftUI

struct SplashScreen: View {
    @State private var isActive = false
    @State private var size = 0.8
    @State private var opacity = 0.5
    
    var body: some View {
        if isActive {
            MainView()
        } else {
            ZStack {
                Color.blue.edgesIgnoringSafeArea(.all) // Solid color fallback
                
                VStack {
                    Image(systemName: "paperplane.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 100, height: 100)
                        .foregroundColor(.white)
                    
                    Text("Fletcher")
                        .font(.largeTitle)
                        .fontWeight(.heavy)
                        .foregroundColor(.white)
                }
                .scaleEffect(size)
                .opacity(opacity)
                .onAppear {
                    print("DEBUG: Splash Screen Appeared")
                    withAnimation(.easeIn(duration: 1.2)) {
                        self.size = 0.9
                        self.opacity = 1.0
                    }
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    print("DEBUG: Transitioning to MainView")
                    withAnimation {
                        self.isActive = true
                    }
                }
            }
        }
    }
}
