# ViewPick 🎬
web version - https://adil-rahman-3063.github.io/viewpick_web/



**ViewPick** is a modern, interactive movie and TV show discovery application built with Flutter. It reimagines how you find your next watch by combining a Tinder-style swipe interface with smart, personalized recommendations.

## ✨ Features

*   **Swipe to Discover:** Effortlessly browse through movies and TV shows. Swipe **Right** to like (and add to watchlist), **Left** to dislike.
*   **Smart Recommendations:** The algorithm learns from your likes and dislikes to suggest content tailored to your taste.
    *   **Strict Language Preferences:** Cycles through your preferred languages to ensure you see content you can understand.
    *   **Genre-Based Suggestions:** Prioritizes genres you've liked in the past.
*   **Granular Dislike Options:** When you dislike an item, you can specify *why*:
    *   **Genre:** "I don't like Horror movies."
    *   **Language:** "I don't watch French films."
    *   **Year:** "I don't like movies from 1990" or "I don't like anything released before 2000."
*   **Comprehensive Details:** View trailers, cast & crew, plot summaries, and find out where to stream (Watch Providers).
*   **Explore & Search:** Search for specific titles or browse Trending and Popular lists.
*   **Library Management:** Keep track of what you want to watch (Watchlist) and what you've already seen (Watched History).
*   **Profile & Stats:** View your watching statistics and manage your preferences.

## 🛠️ Tech Stack

*   **Frontend:** [Flutter](https://flutter.dev/) (Dart)
*   **Backend / Database:** [Supabase](https://supabase.com/) (Authentication, Database, Realtime)
*   **Data Source:** [TMDB API](https://www.themoviedb.org/) (The Movie Database)
*   **Proxy Server:** Custom Node.js proxy for secure API communication.

## 🚀 Getting Started

### Prerequisites

*   [Flutter SDK](https://docs.flutter.dev/get-started/install) installed.
*   A Supabase project set up.
*   A TMDB API Key.

### Installation

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/yourusername/viewpick.git
    cd viewpick
    ```

2.  **Install dependencies:**
    ```bash
    flutter pub get
    ```

3.  **Environment Setup:**
    Create a `assets/credentials.env` file in the root directory and add your Supabase keys:
    ```env
    SUPABASE_URL=your_supabase_url
    SUPABASE_ANON_KEY=your_supabase_anon_key
    ```
    *Note: Ensure you have the `assets` folder configured in your `pubspec.yaml`.*

4.  **Run the App:**
    ```bash
    flutter run
    ```

### 🔒 Authentication & Deep Linking configuration

The application uses Supabase for authentication including email/password login and password resets via deep links.

**Android Setup (`AndroidManifest.xml`):**
To ensure password reset links work correctly (even when the app is closed), the following Intent Filter is required in `android/app/src/main/AndroidManifest.xml`:

```xml
<intent-filter android:autoVerify="true">
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <!-- Specific host for password reset -->
    <data android:scheme="viewpick" android:host="reset-password" />
    <!-- Catch-all for robust handling -->
    <data android:scheme="viewpick" android:host="*" />
</intent-filter>
```

**Testing Password Reset:**
1. Request a reset email from the "Forgot Password" page.
2. **Important:** For a true "Cold Start" test, close the app completely (swipe away from recent apps) before clicking the link in your email.
3. The app should launch and automatically navigate to the Password Change screen.

## 📱 Screenshots

| Swipe Interface | Details Page | Explore |
|:---:|:---:|:---:|
| *(Add Screenshot)* | *(Add Screenshot)* | *(Add Screenshot)* |

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
