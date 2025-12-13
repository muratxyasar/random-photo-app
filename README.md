# Random Photo App

This Flutter application displays a random photo on the screen. It fetches images from an external API and presents them in a user-friendly interface.

## Features

- Fetches a random photo from an external API.
- Displays the photo on the main screen.
- Simple and clean user interface.

## Getting Started

To run this application, follow these steps:

1. **Clone the repository:**
   ```
   git clone <repository-url>
   ```

2. **Navigate to the project directory:**
   ```
   cd random-photo-app
   ```

3. **Install dependencies:**
   ```
   flutter pub get
   ```

4. **Run the application:**
   ```
   flutter run
   ```

## Project Structure

- `lib/main.dart`: Entry point of the application.
- `lib/screens/photo_screen.dart`: Contains the `PhotoScreen` widget that displays the random photo.
- `lib/services/photo_service.dart`: Contains the `PhotoService` class for fetching random photos.
- `lib/widgets/photo_widget.dart`: Contains the `PhotoWidget` for displaying the photo.

## API Used

This application uses an external API to fetch random photos. Make sure to check the API documentation for any usage limits or requirements.

## Contributing

Contributions are welcome! Please feel free to submit a pull request or open an issue for any suggestions or improvements.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.