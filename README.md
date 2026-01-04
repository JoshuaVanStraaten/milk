# Milk 🛒

A South African grocery comparison and shopping list app built with Flutter and Supabase. Compare prices across major retailers, create smart shopping lists, and generate AI-powered recipes with automatic ingredient matching.

## ✨ Features

### Product Browsing & Search

- View products and specials from major SA retailers
- Smart search with real-time filtering
- Promo-only toggle and sorting options
- Price comparison across stores

### Shopping Lists

- Create and manage multiple shopping lists with color coding
- Real-time collaboration with family/friends
- Automatic total calculation with promo price support
- Share lists via invite system

### 🆕 AI Recipe Generation

- Generate recipes from name/description using Google Gemini AI
- "Use Ingredients" mode - get recipe suggestions from what you have
- Automatic ingredient-to-product matching
- Re-match ingredients for specific stores
- Export recipe ingredients directly to shopping list
- Save favorite recipes to "My Recipes"

### Offline Support

- Full offline functionality with Hive local storage
- Background sync when connection restored
- Optimistic UI updates

### Additional Features

- Dark mode support
- Google OAuth authentication
- Guest browsing mode

## 🏪 Retailers Supported

| Retailer   | Products | Specials | Status |
| ---------- | -------- | -------- | ------ |
| Pick n Pay | ✅       | ✅       | Active |
| Woolworths | ✅       | ✅       | Active |
| Shoprite   | ✅       | ✅       | Active |
| Checkers   | ✅       | ✅       | Active |

## 🛠️ Tech Stack

- **Frontend**: Flutter (Dart)
- **Backend**: Supabase (PostgreSQL, Auth, Realtime)
- **AI**: Google Gemini API
- **State Management**: Riverpod
- **Routing**: go_router
- **Local Storage**: Hive, flutter_secure_storage

## 🚀 Getting Started

### Prerequisites

- Flutter SDK (3.19+ recommended)
- Android Studio or VS Code with Flutter extension
- A Supabase project
- Google Gemini API key (for AI recipes)

### Setup

1. **Clone the repository**

   ```bash
   git clone https://github.com/JoshuaVanStraaten/milk.git
   cd milk
   ```

2. **Install dependencies**

   ```bash
   flutter pub get
   ```

3. **Configure environment**

   ```bash
   cp .env.example .env
   ```

   Add your credentials to `.env`:

   ```
   SUPABASE_URL=your_supabase_url
   SUPABASE_ANON_KEY=your_anon_key
   GEMINI_API_KEY=your_gemini_api_key
   ```

4. **Run the app**
   ```bash
   flutter run
   ```

### Database Setup

Run the SQL migrations in your Supabase project:

1. `migrations/001_initial_schema.sql` - Core tables
2. `migrations/002_ai_recipes.sql` - Recipe tables and functions

See `/docs/database_schema.md` for full schema details.

## 📁 Project Structure

```
lib/
├── main.dart
├── app.dart
├── core/
│   ├── config/          # Supabase, environment config
│   ├── constants/       # App constants, retailers
│   ├── theme/           # Colors, text styles, dark mode
│   └── utils/           # Extensions, validators, helpers
├── data/
│   ├── models/          # Data models (Product, Recipe, ShoppingList)
│   ├── repositories/    # Data access layer
│   └── services/        # Realtime, Gemini AI, sync services
└── presentation/
    ├── providers/       # Riverpod state management
    ├── routes/          # go_router configuration
    ├── screens/         # UI screens
    └── widgets/         # Reusable components
```

## 📋 Development Milestones

### ✅ Completed

| Milestone        | Description                     | Date     |
| ---------------- | ------------------------------- | -------- |
| Authentication   | Email/password + Google OAuth   | Nov 2025 |
| Product Browsing | Search, filters, retailer tabs  | Nov 2025 |
| Shopping Lists   | CRUD, sharing, real-time sync   | Nov 2025 |
| Price Comparison | Compare products across stores  | Nov 2025 |
| Dark Mode        | Full dark theme support         | Dec 2025 |
| Offline Support  | Hive caching, background sync   | Dec 2025 |
| AI Recipes MVP   | Generate, match, export recipes | Jan 2026 |

### 🔜 Upcoming

| Milestone           | Description                      | Target  |
| ------------------- | -------------------------------- | ------- |
| Product Detail      | Full product view, price history | Q1 2026 |
| Push Notifications  | Price alerts, list reminders     | Q1 2026 |
| Recipe Enhancements | Images, sharing, meal planning   | Q2 2026 |
| Barcode Scanner     | Scan to find & compare           | Q2 2026 |

See `FUTURE_ENHANCEMENTS.md` for full roadmap.

## 🧪 Testing

```bash
# Run unit tests
flutter test

# Run integration tests
flutter test integration_test/

# Run with coverage
flutter test --coverage
```

## 📱 Screenshots

_Coming soon_

## 🤝 Contributing

This is a personal project, but feedback and suggestions are welcome! Feel free to:

- Open issues for bugs or feature requests
- Submit PRs for documentation improvements
- Share feedback on the app experience

## 📄 License

MIT License - see [LICENSE](LICENSE) file for details.

## 👤 Author

**Joshua van Straaten**

- Location: South Africa 🇿🇦

---

<p align="center">
  Built with ❤️ in South Africa 🇿🇦
  <br>
  <em>Helping South Africans shop smarter, save more</em>
</p>
