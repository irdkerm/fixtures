# fixtures

Small Windows desktop fixture app using Windows PowerShell + WPF. There is no Electron runtime or installer bundle.

The app uses [football-data.org](https://www.football-data.org/) v4 and shows upcoming fixtures only. It intentionally does not show live scores, final scores, scorers, cards, lineups, odds, possession, match stats, or result information.

## API key

Set your football-data.org token in PowerShell before starting the app:

```powershell
$env:FOOTBALL_DATA_API_KEY="your_token_here"
```

## Run

Double-click `fixtures.vbs` to launch without a visible PowerShell window.

For a visible console while debugging, run:

```powershell
.\fixtures.cmd
```

Right-click the window to refresh manually. Fixture data refreshes every 15 minutes and countdowns update every 30 seconds.

## Build

There is nothing to build. The app is `fixtures.ps1`, `fixtures.cmd`, and the PNG assets in `assets/fixture-icons/`.
