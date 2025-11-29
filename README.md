# Milk App 🛒

A South African grocery comparison and shopping list app built with Flutter and Supabase.

## Features

- **Product Browsing**: View products and specials from major SA retailers (Pick n Pay, Woolworths, Shoprite, Checkers)
- **Smart Search**: Search products with real-time filtering, promo-only toggle, and sorting options
- **Shopping Lists**: Create and manage multiple shopping lists with color coding
- **Real-time Collaboration**: Share lists with friends/family and see changes instantly
- **Price Tracking**: Automatic total calculation with promo price support

## Tech Stack

- **Frontend**: Flutter (Dart)
- **Backend**: Supabase (PostgreSQL, Auth, Realtime)
- **State Management**: Riverpod
- **Routing**: go_router
- **Local Storage**: flutter_secure_storage, Hive

## Getting Started

### Prerequisites

- Flutter SDK (latest stable)
- Android Studio or VS Code with Flutter extension
- A Supabase project

### Setup

1. **Clone the repository**

   ```bash
   git clone https://github.com/YOUR_USERNAME/savvy-grocery.git
   cd savvy-grocery
   ```

2. **Install dependencies**

   ```bash
   flutter pub get
   ```

3. **Configure Supabase**

   - Copy `.env.example` to `.env`
   - Replace the placeholder values with your Supabase credentials

4. **Run the app**
   ```bash
   flutter run
   ```

### Database Setup

The app requires the following Supabase tables:

- `user_profiles` - User profile data
- `Products` - Product catalog (populated via web scraping)
- `Shopping_List_Overview` - Shopping list metadata
- `Shopping_List_Item_Level` - Individual list items
- `Shared_lists` - List sharing relationships

See the project documentation for full schema details and RLS policies.

## Project Structure

```
lib/
├── main.dart
├── app.dart
├── core/
│   ├── config/          # Supabase configuration
│   ├── constants/       # App constants, retailers
│   ├── theme/           # Colors, text styles
│   └── utils/           # Extensions, validators
├── data/
│   ├── models/          # Data models
│   ├── repositories/    # Data access layer
│   └── services/        # Realtime service
└── presentation/
    ├── providers/       # Riverpod providers
    ├── routes/          # go_router configuration
    ├── screens/         # UI screens
    └── widgets/         # Reusable widgets
```

## Retailers Supported

| Retailer   | Status |
| ---------- | ------ |
| Pick n Pay | ✅     |
| Woolworths | ✅     |
| Shoprite   | ✅     |
| Checkers   | ✅     |

## Roadmap

- [x] Authentication (email/password)
- [x] Product browsing with search & filters
- [x] Shopping list CRUD
- [x] Real-time collaboration
- [x] List sharing
- [ ] Product detail screen
- [ ] Dark mode
- [ ] Offline support
- [ ] Google OAuth
- [ ] Push notifications
- [ ] AI recipe suggestions

## Contributing

This is a personal project, but feedback and suggestions are welcome!

## License

MIT License - see LICENSE file for details.

## Author

Joshua van Straaten

---

Built with ❤️ in South Africa 🇿🇦
