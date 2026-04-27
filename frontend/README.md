RoboChess Mobile
RoboChess Mobile is the companion Flutter application for the RoboChess Smart Board, enabling players to control, play, and analyze chess games using voice commands.

Features
Players can speak their moves using speech-to-text, and the app parses and validates them in real time against the current board state. The interactive chess board provides full game state management with legal move validation, powered by the chess and flutter_chess_board packages. Through the cross-connect interface, the app pairs with the RoboChess Smart Board to sync moves between the physical and digital boards.

The analysis dashboard lets users review games with move history, positional charts built with fl_chart, and checkmate visualizations. A learn section offers curated tutorials and chess learning resources, and users get a profile screen with an animated avatar and configurable app preferences.

Design and Tech Stack
The app features a dark theme with neon green accents, Google Fonts typography, and Material 3 design. It is built with Flutter using Riverpod for state management, Go Router for navigation, and Clean Architecture organized into data, domain, and presentation layers.
